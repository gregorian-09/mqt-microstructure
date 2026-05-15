/** @file Collectors.mqh @brief Circular-buffer collectors for ticks, quotes, order book snapshots, and trades. */

#include "DataTypes.mqh"

#ifndef MQT_COLLECTORS_MQH
#define MQT_COLLECTORS_MQH

/** Circular buffer of MqtTick entries with automatic trade direction classification. */
class CMqtTickCollector
{
private:
   MqtTick m_ticks[];        /*!< Ring buffer of ticks. */
   int      m_capacity;       /*!< Maximum number of stored ticks. */
   int      m_count;          /*!< Current number of stored ticks. */
   int      m_head;           /*!< Index of the oldest tick. */
   int      m_tail;           /*!< Index of the next insertion slot. */
   string   m_symbol;         /*!< Symbol being collected. */
   ulong    m_last_volume;    /*!< Volume of the last tick (used for classification). */
   double   m_last_price;     /*!< Price of the last tick (used for classification). */

   int NextIndex(int idx) const
   {
      return (idx + 1) % m_capacity;
   }

   void ClassifyTick(MqtTick &tick)
   {
      if ((tick.flags & TICK_FLAG_BUY) == TICK_FLAG_BUY)
      {
         tick.direction = MQT_TICK_BUY;
         return;
      }
      if ((tick.flags & TICK_FLAG_SELL) == TICK_FLAG_SELL)
      {
         tick.direction = MQT_TICK_SELL;
         return;
      }

      if (tick.last > m_last_price)
         tick.direction = MQT_TICK_BUY;
      else if (tick.last < m_last_price)
         tick.direction = MQT_TICK_SELL;
      else if (tick.last == m_last_price)
      {
         if (tick.volume > m_last_volume)
         {
            if (tick.last > tick.MidPrice())
               tick.direction = MQT_TICK_BUY;
            else if (tick.last < tick.MidPrice())
               tick.direction = MQT_TICK_SELL;
            else
               tick.direction = MQT_TICK_UNKNOWN;
         }
         else
            tick.direction = MQT_TICK_UNKNOWN;
      }
   }

public:
   /** @param capacity Maximum number of ticks to hold (default: MQT_DEFAULT_BUFFER_SIZE). */
   CMqtTickCollector()
   {
      m_capacity = MQT_DEFAULT_BUFFER_SIZE;
      m_count = 0;
      m_head = 0;
      m_tail = 0;
      m_symbol = "";
      m_last_volume = 0;
      m_last_price = 0;
      ArrayResize(m_ticks, m_capacity);
   }

   /** @param capacity Maximum number of ticks to hold. */
   CMqtTickCollector(int capacity)
   {
      m_capacity = (capacity > 0) ? capacity : MQT_DEFAULT_BUFFER_SIZE;
      m_count = 0;
      m_head = 0;
      m_tail = 0;
      m_symbol = "";
      m_last_volume = 0;
      m_last_price = 0;
      ArrayResize(m_ticks, m_capacity);
   }

   ~CMqtTickCollector() {}

   /** Initialise the collector for a given symbol and reset the buffer.
     *  @param symbol Instrument name.
     *  @return true */
   bool Init(string symbol)
   {
      m_symbol = symbol;
      m_count = 0;
      m_head = 0;
      m_tail = 0;
      m_last_volume = 0;
      m_last_price = 0;
      return true;
   }

   /** Append a MqlTick and return the classified tick in one operation.
     *  Eliminates the separate GetLast() call that reads back what was just written.
     *  @param src      Source tick.
     *  @param out      [out] Receives the classified MqtTick.
     *  @return true */
   bool Add(const MqlTick &src, MqtTick &out)
   {
      if (m_count == m_capacity)
      {
         m_head = NextIndex(m_head);
         m_count--;
      }

      out.time_msc = src.time_msc;
      out.bid = src.bid;
      out.ask = src.ask;
      out.last = src.last;
      out.volume = src.volume;
      out.volume_real = src.volume_real;
      out.flags = src.flags;

      if ((out.flags & TICK_FLAG_BUY) == TICK_FLAG_BUY)
         out.direction = MQT_TICK_BUY;
      else if ((out.flags & TICK_FLAG_SELL) == TICK_FLAG_SELL)
         out.direction = MQT_TICK_SELL;
      else if (out.last > m_last_price)
         out.direction = MQT_TICK_BUY;
      else if (out.last < m_last_price)
         out.direction = MQT_TICK_SELL;
      else if (out.last == m_last_price)
      {
         if (out.volume > m_last_volume)
         {
            double mid = out.MidPrice();
            if (out.last > mid)
               out.direction = MQT_TICK_BUY;
            else if (out.last < mid)
               out.direction = MQT_TICK_SELL;
            else
               out.direction = MQT_TICK_UNKNOWN;
         }
         else
            out.direction = MQT_TICK_UNKNOWN;
      }

      m_ticks[m_tail] = out;
      m_last_price = out.last;
      m_last_volume = out.volume;
      m_tail = NextIndex(m_tail);
      m_count++;

      return true;
   }

   /** Append a MqlTick (no output — legacy, for internal bulk use).
     *  @param src Source tick.
     *  @return true */
   bool AddSimple(const MqlTick &src)
   {
      if (m_count == m_capacity)
      {
         m_head = NextIndex(m_head);
         m_count--;
      }

      m_ticks[m_tail].FromMqlTick(src);
      ClassifyTick(m_ticks[m_tail]);
      m_last_price = m_ticks[m_tail].last;
      m_last_volume = m_ticks[m_tail].volume;
      m_tail = NextIndex(m_tail);
      m_count++;
      return true;
   }

   /** Append a manually constructed last-price tick.
     *  @param price   Trade price.
     *  @param volume  Trade volume.
     *  @param time_msc Timestamp in milliseconds (0 = current time).
     *  @return true */
   bool AddFromLastPrice(double price, ulong volume, long time_msc = 0)
   {
      if (m_count == m_capacity)
      {
         m_head = NextIndex(m_head);
         m_count--;
      }

      if (time_msc == 0)
         time_msc = TimeCurrent() * 1000;

      m_ticks[m_tail].time_msc = time_msc;
      m_ticks[m_tail].last = price;
      m_ticks[m_tail].volume = volume;
      m_ticks[m_tail].volume_real = (double)volume;
      m_ticks[m_tail].bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      m_ticks[m_tail].ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);

      ClassifyTick(m_ticks[m_tail]);

      m_last_price = m_ticks[m_tail].last;
      m_last_volume = m_ticks[m_tail].volume;
      m_tail = NextIndex(m_tail);
      m_count++;

      return true;
   }

   /** Convert MqlRates bars into ticks and append them.
     *  @param rates Array of MqlRates.
     *  @param count Number of bars to process.
     *  @return Number of ticks added. */
   int CopyTicksFromRates(const MqlRates &rates[], int count)
   {
      int added = 0;
      for (int i = 0; i < count; i++)
      {
         if (rates[i].real_volume > 0)
         {
            MqlTick tick;
            tick.time = rates[i].time;
            tick.time_msc = (long)rates[i].time * 1000;
            tick.bid = rates[i].close;
            tick.ask = rates[i].close;
            tick.last = rates[i].close;
            tick.volume = (ulong)rates[i].real_volume;
            tick.volume_real = (double)rates[i].real_volume;
            AddSimple(tick);
            added++;
         }
      }
      return added;
   }

   /** Load historical ticks from the terminal into the buffer.
     *  @param from_msc Start of range in milliseconds.
     *  @param to_msc   End of range in milliseconds.
     *  @return Number of ticks loaded. */
   int HistoryTicks(long from_msc, long to_msc)
   {
      MqlTick raw_ticks[];
      int got = CopyTicksRange(m_symbol, raw_ticks, COPY_TICKS_ALL,
                                (ulong)from_msc, (ulong)to_msc);
      if (got > 0)
      {
         int limit = MathMin(got, m_capacity);
         int start = MathMax(0, got - limit);
         for (int i = start; i < got; i++)
            AddSimple(raw_ticks[i]);
      }
      return got;
   }

   /** @return Number of ticks currently stored. */
   int Count() const
   {
      return m_count;
   }

   /** Retrieve a tick by its logical index.
     *  @param[out] out Destination tick.
     *  @return true if the index is valid. */
   bool GetAt(int index, MqtTick &out) const
   {
      if (index < 0 || index >= m_count)
         return false;
      int idx = (m_head + index) % m_capacity;
      out = m_ticks[idx];
      return true;
   }

   /** @param[out] out Receives the most recent tick.
     *  @return true if the buffer is non-empty. */
   bool GetLast(MqtTick &out) const
   {
      if (m_count == 0)
         return false;
      int idx = (m_tail - 1 + m_capacity) % m_capacity;
      out = m_ticks[idx];
      return true;
   }

   /** @param index Logical tick index.
     *  @return Copy of the tick at that index (default-constructed if invalid). */
   MqtTick operator[](int index) const
   {
      MqtTick result;
      GetAt(index, result);
      return result;
   }

   /** Reset the buffer. */
   void Clear()
   {
      m_count = 0;
      m_head = 0;
      m_tail = 0;
      m_last_volume = 0;
      m_last_price = 0;
   }

   string Symbol() const { return m_symbol; }
   int Capacity() const { return m_capacity; }
};

/** Circular buffer of MqtQuote entries (best bid/ask snapshots). */
class CMqtQuoteCollector
{
private:
   MqtQuote m_quotes[];       /*!< Ring buffer of quotes. */
   int       m_capacity;      /*!< Maximum number of stored quotes. */
   int       m_count;         /*!< Current number of stored quotes. */
   int       m_head;          /*!< Index of the oldest quote. */
   int       m_tail;          /*!< Index of the next insertion slot. */
   string    m_symbol;        /*!< Symbol being collected. */

   int NextIndex(int idx) const
   {
      return (idx + 1) % m_capacity;
   }

public:
   /** @param capacity Maximum number of quotes to hold (default: MQT_DEFAULT_BUFFER_SIZE). */
   CMqtQuoteCollector()
   {
      m_capacity = MQT_DEFAULT_BUFFER_SIZE;
      m_count = 0;
      m_head = 0;
      m_tail = 0;
      m_symbol = "";
      ArrayResize(m_quotes, m_capacity);
   }

   /** @param capacity Maximum number of quotes to hold. */
   CMqtQuoteCollector(int capacity)
   {
      m_capacity = (capacity > 0) ? capacity : MQT_DEFAULT_BUFFER_SIZE;
      m_count = 0;
      m_head = 0;
      m_tail = 0;
      m_symbol = "";
      ArrayResize(m_quotes, m_capacity);
   }

   /** Initialise the collector for a given symbol.
     *  @param symbol Instrument name.
     *  @return true */
   bool Init(string symbol)
   {
      m_symbol = symbol;
      m_count = 0;
      m_head = 0;
      m_tail = 0;
      return true;
   }

   /** Append a quote.
     *  @param bid       Best bid price.
     *  @param ask       Best ask price.
     *  @param bid_vol   Bid volume.
     *  @param ask_vol   Ask volume.
     *  @param bid_depth Cumulative bid depth.
     *  @param ask_depth Cumulative ask depth.
     *  @param time_msc  Timestamp in milliseconds (0 = current time).
     *  @return true */
   bool Add(double bid, double ask, ulong bid_vol = 0, ulong ask_vol = 0,
            double bid_depth = 0, double ask_depth = 0, long time_msc = 0)
   {
      if (m_count == m_capacity)
      {
         m_head = NextIndex(m_head);
         m_count--;
      }

      if (time_msc == 0)
         time_msc = TimeCurrent() * 1000;

      m_quotes[m_tail].time_msc = time_msc;
      m_quotes[m_tail].bid = bid;
      m_quotes[m_tail].ask = ask;
      m_quotes[m_tail].bid_volume = bid_vol;
      m_quotes[m_tail].ask_volume = ask_vol;
      m_quotes[m_tail].bid_depth = bid_depth;
      m_quotes[m_tail].ask_depth = ask_depth;

      m_tail = NextIndex(m_tail);
      m_count++;

      return true;
   }

   /** Snapshot the current bid/ask from the terminal and append it.
     *  @return true */
   bool AddFromSymbol()
   {
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      return Add(bid, ask);
   }

   /** @return Number of quotes currently stored. */
   int Count() const { return m_count; }

   /** Retrieve a quote by its logical index.
     *  @param[out] out Destination quote.
     *  @return true if the index is valid. */
   bool GetAt(int index, MqtQuote &out) const
   {
      if (index < 0 || index >= m_count)
         return false;
      int idx = (m_head + index) % m_capacity;
      out = m_quotes[idx];
      return true;
   }

   /** @param[out] out Receives the most recent quote.
     *  @return true if the buffer is non-empty. */
   bool GetLast(MqtQuote &out) const
   {
      if (m_count == 0)
         return false;
      int idx = (m_tail - 1 + m_capacity) % m_capacity;
      out = m_quotes[idx];
      return true;
   }

   /** Reset the buffer. */
   void Clear()
   {
      m_count = 0;
      m_head = 0;
      m_tail = 0;
   }

   string Symbol() const { return m_symbol; }
};

/** Circular buffer of full order-book snapshots using MarketBookGet. */
class CMqtOrderBookCollector
{
private:
   MqtOrderBookSnapshot m_snapshots[]; /*!< Ring buffer of book snapshots. */
   int   m_capacity;                   /*!< Maximum number of stored snapshots. */
   int   m_count;                      /*!< Current number of stored snapshots. */
   int   m_head;                       /*!< Index of the oldest snapshot. */
   int   m_tail;                       /*!< Index of the next insertion slot. */
   string m_symbol;                    /*!< Symbol being collected. */
   bool   m_book_open;                 /*!< true if MarketBookAdd has been called. */

   int NextIndex(int idx) const
   {
      return (idx + 1) % m_capacity;
   }

public:
   /** @param capacity Maximum number of snapshots to hold (default: 1000). */
   CMqtOrderBookCollector()
   {
      m_capacity = 1000;
      m_count = 0;
      m_head = 0;
      m_tail = 0;
      m_symbol = "";
      m_book_open = false;
      ArrayResize(m_snapshots, m_capacity);
   }

   /** @param capacity Maximum number of snapshots to hold. */
   CMqtOrderBookCollector(int capacity)
   {
      m_capacity = (capacity > 0) ? capacity : 1000;
      m_count = 0;
      m_head = 0;
      m_tail = 0;
      m_symbol = "";
      m_book_open = false;
      ArrayResize(m_snapshots, m_capacity);
   }

   ~CMqtOrderBookCollector()
   {
      if (m_book_open)
      {
         MarketBookRelease(m_symbol);
         m_book_open = false;
      }
   }

   /** Initialise the collector and subscribe to MarketBook for the symbol.
     *  @param symbol Instrument name.
     *  @return true if MarketBookAdd succeeded. */
   bool Init(string symbol)
   {
      m_symbol = symbol;
      m_count = 0;
      m_head = 0;
      m_tail = 0;

      if (m_book_open)
      {
         MarketBookRelease(m_symbol);
         m_book_open = false;
      }

      bool ok = MarketBookAdd(m_symbol);
      if (ok)
         m_book_open = true;

      return ok;
   }

   /** Capture the current market depth and store it as a snapshot.
     *  @return true on success. */
   bool Snapshot()
   {
      if (!m_book_open)
         return false;

      MqlBookInfo book[];
      if (!MarketBookGet(m_symbol, book))
         return false;

      if (m_count == m_capacity)
      {
         m_head = NextIndex(m_head);
         m_count--;
      }

      m_snapshots[m_tail].time_msc = TimeCurrent() * 1000;
      m_snapshots[m_tail].bid_count = 0;
      m_snapshots[m_tail].ask_count = 0;
      m_snapshots[m_tail].bid_depth_total = 0;
      m_snapshots[m_tail].ask_depth_total = 0;

      int total = ArraySize(book);
      MqtOrderBookLevel tmp_bids[MQT_MAX_BOOK_DEPTH];
      MqtOrderBookLevel tmp_asks[MQT_MAX_BOOK_DEPTH];
      int bid_count = 0, ask_count = 0;

      for (int i = 0; i < total; i++)
      {
         if (book[i].type == BOOK_TYPE_SELL || book[i].type == BOOK_TYPE_SELL_MARKET)
         {
            if (ask_count < MQT_MAX_BOOK_DEPTH)
            {
               tmp_asks[ask_count].price = book[i].price;
               tmp_asks[ask_count].volume = book[i].volume;
               tmp_asks[ask_count].volume_real = book[i].volume_real;
               ask_count++;
               m_snapshots[m_tail].ask_depth_total += (double)book[i].volume;
            }
         }
         else if (book[i].type == BOOK_TYPE_BUY || book[i].type == BOOK_TYPE_BUY_MARKET)
         {
            if (bid_count < MQT_MAX_BOOK_DEPTH)
            {
               tmp_bids[bid_count].price = book[i].price;
               tmp_bids[bid_count].volume = book[i].volume;
               tmp_bids[bid_count].volume_real = book[i].volume_real;
               bid_count++;
               m_snapshots[m_tail].bid_depth_total += (double)book[i].volume;
            }
         }
      }

      for (int i = 0; i < bid_count; i++)
      {
         int best = i;
         for (int j = i + 1; j < bid_count; j++)
         {
            if (tmp_bids[j].price > tmp_bids[best].price)
               best = j;
         }
         m_snapshots[m_tail].bids[m_snapshots[m_tail].bid_count] = tmp_bids[best];
         m_snapshots[m_tail].bid_count++;
         if (best != i)
         {
            MqtOrderBookLevel temp = tmp_bids[i];
            tmp_bids[i] = tmp_bids[best];
            tmp_bids[best] = temp;
         }
      }

      for (int i = 0; i < ask_count; i++)
      {
         int best = i;
         for (int j = i + 1; j < ask_count; j++)
         {
            if (tmp_asks[j].price < tmp_asks[best].price)
               best = j;
         }
         m_snapshots[m_tail].asks[m_snapshots[m_tail].ask_count] = tmp_asks[best];
         m_snapshots[m_tail].ask_count++;
         if (best != i)
         {
            MqtOrderBookLevel temp = tmp_asks[i];
            tmp_asks[i] = tmp_asks[best];
            tmp_asks[best] = temp;
         }
      }

      m_tail = NextIndex(m_tail);
      m_count++;

      return true;
   }

   /** @return Number of snapshots currently stored. */
   int Count() const { return m_count; }

   /** Retrieve a snapshot by its logical index.
     *  @param[out] out Destination snapshot.
     *  @return true if the index is valid. */
   bool GetAt(int index, MqtOrderBookSnapshot &out) const
   {
      if (index < 0 || index >= m_count)
         return false;
      int idx = (m_head + index) % m_capacity;
      out = m_snapshots[idx];
      return true;
   }

   /** @param[out] out Receives the most recent snapshot.
     *  @return true if the buffer is non-empty. */
   bool GetLast(MqtOrderBookSnapshot &out) const
   {
      if (m_count == 0)
         return false;
      int idx = (m_tail - 1 + m_capacity) % m_capacity;
      out = m_snapshots[idx];
      return true;
   }

   /** Reset the buffer. */
   void Clear()
   {
      m_count = 0;
      m_head = 0;
      m_tail = 0;
   }

   string Symbol() const { return m_symbol; }
   bool IsBookOpen() const { return m_book_open; }
};

/** Circular buffer of MqtTrade entries with aggressor-side classification. */
class CMqtTradeCollector
{
private:
   MqtTrade m_trades[];     /*!< Ring buffer of trades. */
   int      m_capacity;     /*!< Maximum number of stored trades. */
   int      m_count;        /*!< Current number of stored trades. */
   int      m_head;         /*!< Index of the oldest trade. */
   int      m_tail;         /*!< Index of the next insertion slot. */
   string   m_symbol;       /*!< Symbol being collected. */
   double   m_last_price;   /*!< Price of the last trade (used for classification). */

   int NextIndex(int idx) const
   {
      return (idx + 1) % m_capacity;
   }

   ENUM_MQT_TRADE_DIRECTION ClassifyAggressor(double price, uint flags,
         double bid, double ask)
   {
      if ((flags & TICK_FLAG_BUY) == TICK_FLAG_BUY)
         return MQT_TRADE_BUY;
      if ((flags & TICK_FLAG_SELL) == TICK_FLAG_SELL)
         return MQT_TRADE_SELL;

      if (price >= ask && ask > 0)
         return MQT_TRADE_BUY;
      if (price <= bid && bid > 0)
         return MQT_TRADE_SELL;

      if (price > m_last_price)
         return MQT_TRADE_BUY;
      if (price < m_last_price)
         return MQT_TRADE_SELL;

      return MQT_TRADE_NEUTRAL;
   }

public:
   /** @param capacity Maximum number of trades to hold (default: MQT_DEFAULT_BUFFER_SIZE). */
   CMqtTradeCollector()
   {
      m_capacity = MQT_DEFAULT_BUFFER_SIZE;
      m_count = 0;
      m_head = 0;
      m_tail = 0;
      m_symbol = "";
      m_last_price = 0;
      ArrayResize(m_trades, m_capacity);
   }

   /** @param capacity Maximum number of trades to hold. */
   CMqtTradeCollector(int capacity)
   {
      m_capacity = (capacity > 0) ? capacity : MQT_DEFAULT_BUFFER_SIZE;
      m_count = 0;
      m_head = 0;
      m_tail = 0;
      m_symbol = "";
      m_last_price = 0;
      ArrayResize(m_trades, m_capacity);
   }

   /** Initialise the collector for a given symbol.
     *  @param symbol Instrument name.
     *  @return true */
   bool Init(string symbol)
   {
      m_symbol = symbol;
      m_count = 0;
      m_head = 0;
      m_tail = 0;
      m_last_price = 0;
      return true;
   }

   /** Append a trade and classify its aggressor side.
     *  @param price    Trade price.
     *  @param volume   Trade volume.
     *  @param flags    Tick flags (TICK_FLAG_BUY / TICK_FLAG_SELL).
     *  @param time_msc Timestamp in milliseconds (0 = current time).
     *  @return true */
   bool AddTrade(double price, ulong volume, uint flags = 0, long time_msc = 0)
   {
      if (m_count == m_capacity)
      {
         m_head = NextIndex(m_head);
         m_count--;
      }

      if (time_msc == 0)
         time_msc = TimeCurrent() * 1000;

      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);

      m_trades[m_tail].time_msc = time_msc;
      m_trades[m_tail].price = price;
      m_trades[m_tail].volume = volume;
      m_trades[m_tail].aggressor = ClassifyAggressor(price, flags, bid, ask);
      m_trades[m_tail].is_aggressive = (m_trades[m_tail].aggressor != MQT_TRADE_NEUTRAL);

      m_last_price = price;

      m_tail = NextIndex(m_tail);
      m_count++;

      return true;
   }

   /** Extract a trade from a MqlTick and append it.
     *  @param tick Source tick.
     *  @return true if the tick contains valid trade data. */
   bool AddFromTick(const MqlTick &tick)
   {
      if (tick.last > 0 && tick.volume > 0)
         return AddTrade(tick.last, tick.volume, tick.flags, tick.time_msc);
      return false;
   }

   /** @return Number of trades currently stored. */
   int Count() const { return m_count; }

   /** Retrieve a trade by its logical index.
     *  @param[out] out Destination trade.
     *  @return true if the index is valid. */
   bool GetAt(int index, MqtTrade &out) const
   {
      if (index < 0 || index >= m_count)
         return false;
      int idx = (m_head + index) % m_capacity;
      out = m_trades[idx];
      return true;
   }

   /** @param[out] out Receives the most recent trade.
     *  @return true if the buffer is non-empty. */
   bool GetLast(MqtTrade &out) const
   {
      if (m_count == 0)
         return false;
      int idx = (m_tail - 1 + m_capacity) % m_capacity;
      out = m_trades[idx];
      return true;
   }

   /** Reset the buffer. */
   void Clear()
   {
      m_count = 0;
      m_head = 0;
      m_tail = 0;
      m_last_price = 0;
   }

   string Symbol() const { return m_symbol; }
};

#endif
