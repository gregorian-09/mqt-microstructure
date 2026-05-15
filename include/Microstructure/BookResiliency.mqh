/** @file BookResiliency.mqh @brief Order-book resiliency measurement — how quickly depth recovers after a trade. */

#include "Collectors.mqh"

#ifndef MQT_BOOK_RESILIENCY_MQH
#define MQT_BOOK_RESILIENCY_MQH

/** Tracks order-book recovery speed following a trade event. */
class CMqtBookResiliency
{
private:
   CMqtOrderBookCollector *m_book;
   double   m_resiliency[];     /*!< Ring buffer of resiliency values (1/recovery-time). */
   double   m_recovery_times[]; /*!< Ring buffer of recovery durations (ms). */
   int      m_capacity;
   int      m_count;
   int      m_head;
   int      m_tail;
   int      m_error;
   double   m_prev_bid_depth;
   double   m_prev_ask_depth;
   double   m_prev_mid;
   double   m_current_resiliency;
   long     m_last_trade_msc;
   long     m_recovery_start_msc;
   bool     m_in_recovery;
   double   m_depth_before_trade;
   double   m_baseline_bid_depth;
   double   m_baseline_ask_depth;

   int NextIndex(int idx) const { return (idx + 1) % m_capacity; }

public:
   /** @param capacity Ring-buffer capacity (default: 500). */
   CMqtBookResiliency()
   {
      m_book = NULL;
      m_capacity = 500;
      m_count = 0;
      m_head = 0;
      m_tail = 0;
      m_error = MQT_ERR_OK;
      m_prev_bid_depth = 0;
      m_prev_ask_depth = 0;
      m_prev_mid = 0;
      m_current_resiliency = 0;
      m_last_trade_msc = 0;
      m_recovery_start_msc = 0;
      m_in_recovery = false;
      m_depth_before_trade = 0;
      m_baseline_bid_depth = 0;
      m_baseline_ask_depth = 0;
      ArrayResize(m_resiliency, m_capacity);
      ArrayResize(m_recovery_times, m_capacity);
   }

   /** @return Last error code. */
   int LastError() const { return m_error; }

   /** @param book Order-book collector to use. */
   void SetBookCollector(CMqtOrderBookCollector *book)
   {
      m_book = book;
   }

   /** Compute baseline depth from recent snapshots.
     *  @return true on success. */
   bool SetBaseline(int lookback = 10)
   {
      if (m_book == NULL || m_book.Count() < lookback)
      {
         m_error = MQT_ERR_INSUFFICIENT_DATA;
         return false;
      }

      double bid_sum = 0, ask_sum = 0;
      int n = MathMin(lookback, m_book.Count());

      for (int i = 0; i < n; i++)
      {
         MqtOrderBookSnapshot snap;
         if (m_book.GetAt(m_book.Count() - 1 - i, snap))
         {
            bid_sum += snap.bid_depth_total;
            ask_sum += snap.ask_depth_total;
         }
      }

      m_baseline_bid_depth = bid_sum / n;
      m_baseline_ask_depth = ask_sum / n;
      return true;
   }

   /** Record a trade and begin tracking recovery.
     *  @return true. */
   bool OnTrade(long time_msc, double price, ulong volume)
   {
      m_last_trade_msc = time_msc;

      if (m_book == NULL || m_book.Count() == 0)
         return false;

      MqtOrderBookSnapshot snap;
      if (!m_book.GetLast(snap))
         return false;

      m_depth_before_trade = snap.bid_depth_total + snap.ask_depth_total;
      m_prev_mid = (snap.bids[0].price + snap.asks[0].price) * 0.5;
      m_in_recovery = true;
      m_recovery_start_msc = time_msc;

      return true;
   }

   /** Feed a post-trade book snapshot to measure recovery progress.
     *  @return true if recovery completed (snapshot consumed as a full event). */
   bool OnBookSnapshot(const MqtOrderBookSnapshot &snap)
   {
      if (!m_in_recovery)
      {
         m_prev_bid_depth = snap.bid_depth_total;
         m_prev_ask_depth = snap.ask_depth_total;
         return false;
      }

      double current_depth = snap.bid_depth_total + snap.ask_depth_total;
      double baseline = m_baseline_bid_depth + m_baseline_ask_depth;

      if (baseline <= 0)
      {
         baseline = m_depth_before_trade;
         if (baseline <= 0)
         {
            m_prev_bid_depth = snap.bid_depth_total;
            m_prev_ask_depth = snap.ask_depth_total;
            return false;
         }
      }

      double recovery_ratio = current_depth / baseline;
      long elapsed = snap.time_msc - m_recovery_start_msc;

      if (recovery_ratio >= 0.95)
      {
         m_current_resiliency = (elapsed > 0) ? 1.0 / (double)elapsed : 0;

         if (m_count == m_capacity)
         {
            m_head = NextIndex(m_head);
            m_count--;
         }
         m_resiliency[m_tail] = m_current_resiliency;
         m_recovery_times[m_tail] = (double)elapsed;
         m_tail = NextIndex(m_tail);
         m_count++;

         m_in_recovery = false;
      }
      else
      {
         m_current_resiliency = recovery_ratio / MathMax(1.0, (double)elapsed);
      }

      m_prev_bid_depth = snap.bid_depth_total;
      m_prev_ask_depth = snap.ask_depth_total;

      return !m_in_recovery;
   }

   /** @return Most recent resiliency (1/recovery-time or partial ratio/elapsed). */
   double CurrentResiliency() const { return m_current_resiliency; }

   /** @param lookback Number of events.
     *  @return Mean resiliency over lookback. */
   double AverageResiliency(int lookback = 20)
   {
      if (m_count == 0) return 0;
      int n = MathMin(lookback, m_count);
      double sum = 0;
      for (int i = 0; i < n; i++)
      {
         int idx = (m_tail - 1 - i + m_capacity) % m_capacity;
         sum += m_resiliency[idx];
      }
      return sum / n;
   }

   /** @param lookback Number of events.
     *  @return Mean recovery time (ms) over lookback. */
   double AverageRecoveryTime(int lookback = 20)
   {
      if (m_count == 0) return 0;
      int n = MathMin(lookback, m_count);
      double sum = 0;
      for (int i = 0; i < n; i++)
      {
         int idx = (m_tail - 1 - i + m_capacity) % m_capacity;
         sum += m_recovery_times[idx];
      }
      return sum / n;
   }

   /** @return Depth / average recovery time. */
   double DepthElasticity()
   {
      if (m_depth_before_trade <= 0 || m_count == 0)
         return 0;

      double avg_recovery = AverageRecoveryTime(10);
      return (avg_recovery > 0) ? m_depth_before_trade / avg_recovery : 0;
   }

   bool IsInRecovery() const { return m_in_recovery; }
   int Count() const { return m_count; }

   /** Clear all data. */
   void Reset()
   {
      m_count = 0;
      m_head = 0;
      m_tail = 0;
      m_in_recovery = false;
      m_current_resiliency = 0;
      m_depth_before_trade = 0;
   }
};

#endif
