/** @file Backtest.mqh @brief Historical tick player and time-bar aggregator for backtesting. */

#include "DataTypes.mqh"
#include "Collectors.mqh"

#ifndef MQT_BACKTEST_MQH
#define MQT_BACKTEST_MQH

/** Replays historical ticks from terminal storage into collectors. */
class CMqtHistoryPlayer
{
private:
   MqlTick   m_ticks[];
   int       m_total;
   int       m_position;
   string    m_symbol;
   int       m_error;

public:
   CMqtHistoryPlayer()
   {
      m_total = 0;
      m_position = 0;
      m_symbol = "";
      m_error = MQT_ERR_OK;
   }

   int LastError() const { return m_error; }
   int Position() const { return m_position; }
   int Total() const { return m_total; }

   /** Load ticks within a date range.
     *  @param symbol   Instrument name.
     *  @param from     Start datetime.
     *  @param to       End datetime.
     *  @param max_ticks Maximum ticks to load.
     *  @return true on success. */
   bool LoadRange(string symbol, datetime from, datetime to, int max_ticks = 500000)
   {
      m_symbol = symbol;
      m_position = 0;

      int got = CopyTicksRange(m_symbol, m_ticks, COPY_TICKS_ALL,
                                (ulong)from * 1000, (ulong)to * 1000);
      if (got <= 0)
      {
         m_error = MQT_ERR_INSUFFICIENT_DATA;
         m_total = 0;
         return false;
      }

      if (got > max_ticks)
      {
         int offset = got - max_ticks;
         ArrayCopy(m_ticks, m_ticks, 0, offset, max_ticks);
         m_total = max_ticks;
      }
      else
      {
         m_total = got;
      }

      return true;
   }

   /** Load a fixed number of ticks from a start date.
     *  @return true on success. */
   bool LoadCount(string symbol, datetime from, int count)
   {
      m_symbol = symbol;
      m_position = 0;

      int got = CopyTicks(m_symbol, m_ticks, COPY_TICKS_ALL, (ulong)from * 1000, count);
      if (got <= 0)
      {
         m_error = MQT_ERR_INSUFFICIENT_DATA;
         m_total = 0;
         return false;
      }

      m_total = got;
      return true;
   }

   /** Advance to the next tick.
     *  @return true if a tick is available. */
   bool NextTick(MqlTick &tick)
   {
      if (m_position >= m_total)
         return false;

      tick = m_ticks[m_position];
      m_position++;
      return true;
   }

   /** Feed ticks into a CMqtTickCollector.
     *  @param n Number of ticks to feed (-1 = all remaining).
     *  @return Number of ticks fed. */
   int FeedCollector(CMqtTickCollector *collector, int n = -1)
   {
      if (collector == NULL)
      {
         m_error = MQT_ERR_NULL_POINTER;
         return 0;
      }

      int limit = (n < 0) ? (m_total - m_position) : MathMin(n, m_total - m_position);
      int fed = 0;

      for (int i = 0; i < limit && m_position < m_total; i++)
      {
         collector.AddSimple(m_ticks[m_position]);
         m_position++;
         fed++;
      }

      return fed;
   }

   /** Feed ticks into a CMqtTradeCollector (only ticks with trade data).
     *  @param n Number of ticks to feed (-1 = all remaining).
     *  @return Number of trades fed. */
   int FeedTradeCollector(CMqtTradeCollector *collector, int n = -1)
   {
      if (collector == NULL)
      {
         m_error = MQT_ERR_NULL_POINTER;
         return 0;
      }

      int limit = (n < 0) ? (m_total - m_position) : MathMin(n, m_total - m_position);
      int fed = 0;

      for (int i = 0; i < limit && m_position < m_total; i++)
      {
         if (m_ticks[m_position].last > 0 && m_ticks[m_position].volume > 0)
         {
            collector.AddFromTick(m_ticks[m_position]);
            fed++;
         }
         m_position++;
      }

      return fed;
   }

   /** Jump to a specific tick position.
     *  @return true if the position is valid. */
   bool Seek(int position)
   {
      if (position < 0 || position >= m_total)
         return false;
      m_position = position;
      return true;
   }

   /** Reset playback to the start. */
   void Reset()
   {
      m_position = 0;
   }

   /** @return Fraction of ticks consumed [0, 1]. */
   double Progress() const
   {
      return (m_total > 0) ? (double)m_position / (double)m_total : 0;
   }
};

/** Aggregates ticks into fixed-interval OHLC bars. */
class CMqtTickAggregator
{
private:
   MqtOHLC   m_bars[]; /*!< Ring buffer of completed bars. */
   int       m_capacity;
   int       m_count;
   long      m_interval_msc;
   long      m_bar_start_msc;
   double    m_bar_open;
   double    m_bar_high;
   double    m_bar_low;
   double    m_bar_close;
   long      m_bar_volume;
   bool      m_in_bar;

public:
   /** @param capacity Maximum number of bars to store (default: 10000). */
   CMqtTickAggregator()
   {
      m_capacity = 10000;
      m_count = 0;
      m_interval_msc = 60000;
      m_bar_start_msc = 0;
      m_bar_open = 0;
      m_bar_high = 0;
      m_bar_low = 0;
      m_bar_close = 0;
      m_bar_volume = 0;
      m_in_bar = false;
      ArrayResize(m_bars, m_capacity);
   }

   /** @param milliseconds Bar interval (minimum 1000 ms). */
   void SetInterval(long milliseconds)
   {
      m_interval_msc = MathMax(1000, milliseconds);
   }

   /** Feed a tick into the current bar.
     *  @return true. */
   bool AddTick(const MqtTick &tick)
   {
      if (tick.last <= 0)
         return false;

      long bar_idx = tick.time_msc / m_interval_msc;
      long bar_start = bar_idx * m_interval_msc;

      if (!m_in_bar)
      {
         m_bar_start_msc = bar_start;
         m_bar_open = tick.last;
         m_bar_high = tick.last;
         m_bar_low = tick.last;
         m_bar_close = tick.last;
         m_bar_volume = (long)tick.volume;
         m_in_bar = true;
         return true;
      }

      if (bar_start == m_bar_start_msc)
      {
         m_bar_high = MathMax(m_bar_high, tick.last);
         m_bar_low = (m_bar_low > 0) ? MathMin(m_bar_low, tick.last) : tick.last;
         m_bar_close = tick.last;
         m_bar_volume += (long)tick.volume;
         return true;
      }

      if (m_count == m_capacity)
      {
         for (int i = 1; i < m_capacity; i++)
            m_bars[i - 1] = m_bars[i];
         m_count--;
      }

      m_bars[m_count].time_msc = m_bar_start_msc;
      m_bars[m_count].open = m_bar_open;
      m_bars[m_count].high = m_bar_high;
      m_bars[m_count].low = m_bar_low;
      m_bars[m_count].close = m_bar_close;
      m_bars[m_count].volume = m_bar_volume;
      m_count++;

      m_bar_start_msc = bar_start;
      m_bar_open = tick.last;
      m_bar_high = tick.last;
      m_bar_low = tick.last;
      m_bar_close = tick.last;
      m_bar_volume = (long)tick.volume;

      return true;
   }

   int Count() const { return m_count; }

   /** @param[out] out Destination bar.
     *  @return true if the index is valid. */
   bool GetBar(int index, MqtOHLC &out) const
   {
      if (index < 0 || index >= m_count)
         return false;
      out = m_bars[index];
      return true;
   }

   /** Clear all bars and reset. */
   void Reset()
   {
      m_count = 0;
      m_in_bar = false;
      m_bar_volume = 0;
      m_bar_start_msc = 0;
   }
};

#endif
