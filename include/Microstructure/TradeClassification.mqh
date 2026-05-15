/** @file TradeClassification.mqh @brief Tick-rule, Lee-Ready, quote-based, aggressor, and batch trade classification. */

#include "DataTypes.mqh"

#ifndef MQT_TRADECLASSIFICATION_MQH
#define MQT_TRADECLASSIFICATION_MQH

/** Simple tick-rule classifier: price rise = buy, price fall = sell, volume comparison on equality. */
class CMqtTickRule
{
private:
   double   m_last_price;
   ulong    m_last_volume;

public:
   CMqtTickRule()
   {
      m_last_price = 0;
      m_last_volume = 0;
   }

   /** @return Classified direction (MQT_TICK_UNKNOWN for the first tick). */
   ENUM_MQT_TICK_DIRECTION Classify(double price, ulong volume)
   {
      if (m_last_price == 0)
      {
         m_last_price = price;
         m_last_volume = volume;
         return MQT_TICK_UNKNOWN;
      }

      ENUM_MQT_TICK_DIRECTION direction;

      if (price > m_last_price)
         direction = MQT_TICK_BUY;
      else if (price < m_last_price)
         direction = MQT_TICK_SELL;
      else
      {
         if (volume > m_last_volume)
            direction = MQT_TICK_BUY;
         else if (volume < m_last_volume)
            direction = MQT_TICK_SELL;
         else
            direction = MQT_TICK_UNKNOWN;
      }

      m_last_price = price;
      m_last_volume = volume;

      return direction;
   }

   /** Reversed tick rule (price rise = sell).
     *  @return Classified direction. */
   ENUM_MQT_TICK_DIRECTION ClassifyReverse(double price, ulong volume)
   {
      if (m_last_price == 0)
      {
         m_last_price = price;
         m_last_volume = volume;
         return MQT_TICK_UNKNOWN;
      }

      ENUM_MQT_TICK_DIRECTION direction;

      if (price > m_last_price)
         direction = MQT_TICK_SELL;
      else if (price < m_last_price)
         direction = MQT_TICK_BUY;
      else
      {
         if (volume > m_last_volume)
            direction = MQT_TICK_SELL;
         else if (volume < m_last_volume)
            direction = MQT_TICK_BUY;
         else
            direction = MQT_TICK_UNKNOWN;
      }

      m_last_price = price;
      m_last_volume = volume;

      return direction;
   }

   /** @return Classified direction from a MqlTick. */
   ENUM_MQT_TICK_DIRECTION ClassifyTick(const MqlTick &tick)
   {
      return Classify(tick.last, (ulong)tick.volume);
   }

   /** Reset internal state. */
   void Reset()
   {
      m_last_price = 0;
      m_last_volume = 0;
   }
};

/** Lee-Ready trade classification: price vs. bid-ask midpoint + tick test for ambiguous ticks. */
class CMqtLeeReady
{
private:
   double   m_last_price;
   double   m_last_bid;
   double   m_last_ask;
   double   m_prev_bid;
   double   m_prev_ask;

public:
   CMqtLeeReady()
   {
      m_last_price = 0;
      m_last_bid = 0;
      m_last_ask = 0;
      m_prev_bid = 0;
      m_prev_ask = 0;
   }

   /** @param price Trade price.
     *  @param volume Trade volume.
     *  @param bid    Current best bid.
     *  @param ask    Current best ask.
     *  @return MQT_TRADE_BUY, MQT_TRADE_SELL, or MQT_TRADE_NEUTRAL. */
   ENUM_MQT_TRADE_DIRECTION Classify(double price, ulong volume,
                                      double bid, double ask)
   {
      if (bid <= 0 || ask <= 0)
      {
         m_last_price = price;
         return MQT_TRADE_NEUTRAL;
      }

      double mid = (bid + ask) * 0.5;

      if (price > mid)
      {
         m_last_price = price;
         m_prev_bid = m_last_bid;
         m_prev_ask = m_last_ask;
         m_last_bid = bid;
         m_last_ask = ask;
         return MQT_TRADE_BUY;
      }

      if (price < mid)
      {
         m_last_price = price;
         m_prev_bid = m_last_bid;
         m_prev_ask = m_last_ask;
         m_last_bid = bid;
         m_last_ask = ask;
         return MQT_TRADE_SELL;
      }

      if (price == mid)
      {
         if (m_last_price == 0)
         {
            m_last_price = price;
            m_prev_bid = m_last_bid;
            m_prev_ask = m_last_ask;
            m_last_bid = bid;
            m_last_ask = ask;
            return MQT_TRADE_NEUTRAL;
         }

         if (price > m_last_price)
         {
            m_last_price = price;
            m_prev_bid = m_last_bid;
            m_prev_ask = m_last_ask;
            m_last_bid = bid;
            m_last_ask = ask;
            return MQT_TRADE_BUY;
         }
         else if (price < m_last_price)
         {
            m_last_price = price;
            m_prev_bid = m_last_bid;
            m_prev_ask = m_last_ask;
            m_last_bid = bid;
            m_last_ask = ask;
            return MQT_TRADE_SELL;
         }
         else
         {
            if (volume > 0)
            {
               if (m_last_bid > 0 && m_last_ask > 0)
               {
                  if (bid < m_last_bid)
                  {
                     m_last_price = price;
                     m_prev_bid = m_last_bid;
                     m_prev_ask = m_last_ask;
                     m_last_bid = bid;
                     m_last_ask = ask;
                     return MQT_TRADE_SELL;
                  }
                  else if (ask > m_last_ask)
                  {
                     m_last_price = price;
                     m_prev_bid = m_last_bid;
                     m_prev_ask = m_last_ask;
                     m_last_bid = bid;
                     m_last_ask = ask;
                     return MQT_TRADE_BUY;
                  }
               }
            }

            m_last_price = price;
            m_prev_bid = m_last_bid;
            m_prev_ask = m_last_ask;
            m_last_bid = bid;
            m_last_ask = ask;
            return MQT_TRADE_NEUTRAL;
         }
      }

      m_last_price = price;
      m_prev_bid = m_last_bid;
      m_prev_ask = m_last_ask;
      m_last_bid = bid;
      m_last_ask = ask;
      return MQT_TRADE_NEUTRAL;
   }

   /** @return Classified direction from a MqlTick. */
   ENUM_MQT_TRADE_DIRECTION ClassifyMqlTick(const MqlTick &tick)
   {
      return Classify(tick.last, (ulong)tick.volume, tick.bid, tick.ask);
   }

   /** @return Classified direction from an MqtTick. */
   ENUM_MQT_TRADE_DIRECTION ClassifyMqtTick(const MqtTick &tick)
   {
      return Classify(tick.last, tick.volume, tick.bid, tick.ask);
   }

   /** Reset internal state. */
   void Reset()
   {
      m_last_price = 0;
      m_last_bid = 0;
      m_last_ask = 0;
      m_prev_bid = 0;
      m_prev_ask = 0;
   }

   /** @return Last recorded mid-price. */
   double LastMid() const
   {
      if (m_last_bid > 0 && m_last_ask > 0)
         return (m_last_bid + m_last_ask) * 0.5;
      return 0;
   }
};

/** Quote-based classification: trade at ask = buy, at bid = sell. */
class CMqtQuoteClassification
{
private:
   double   m_last_bid;
   double   m_last_ask;
   double   m_mid_price;

public:
   CMqtQuoteClassification()
   {
      m_last_bid = 0;
      m_last_ask = 0;
      m_mid_price = 0;
   }

   /** @return Classified direction based on price vs. bid/ask. */
   ENUM_MQT_TRADE_DIRECTION Classify(double price, double bid, double ask)
   {
      m_last_bid = bid;
      m_last_ask = ask;
      m_mid_price = (bid + ask) * 0.5;

      if (price >= ask)
         return MQT_TRADE_BUY;
      else if (price <= bid)
         return MQT_TRADE_SELL;

      return MQT_TRADE_NEUTRAL;
   }

   /** @return Normalised position of price within the spread [0, 1]. */
   double TradePositionRelative(double price) const
   {
      double spread = m_last_ask - m_last_bid;
      if (spread > 0)
         return (price - m_last_bid) / spread;
      return 0.5;
   }

   /** @return true if price is at or above the ask. */
   bool IsAtAsk(double price, double tolerance = 0.0) const
   {
      return price >= m_last_ask - tolerance;
   }

   /** @return true if price is at or below the bid. */
   bool IsAtBid(double price, double tolerance = 0.0) const
   {
      return price <= m_last_bid + tolerance;
   }

   /** @return Absolute distance from mid-price as a fraction. */
   double DistanceFromMid(double price) const
   {
      if (m_mid_price > 0)
         return MathAbs(price - m_mid_price) / m_mid_price;
      return 0;
   }

   /** Reset internal state. */
   void Reset()
   {
      m_last_bid = 0;
      m_last_ask = 0;
      m_mid_price = 0;
   }
};

/** Aggressor-side detection: flags, quote comparison, and tick-test fallback. */
class CMqtAggressorDetection
{
private:
   double   m_prev_price;
   double   m_prev_bid;
   double   m_prev_ask;

public:
   CMqtAggressorDetection()
   {
      m_prev_price = 0;
      m_prev_bid = 0;
      m_prev_ask = 0;
   }

   /** @return true if price is at or above the ask. */
   bool IsAggressiveBuy(double price, double bid, double ask) const
   {
      if (ask > 0)
         return price >= ask;
      return false;
   }

   /** @return true if price is at or below the bid. */
   bool IsAggressiveSell(double price, double bid, double ask) const
   {
      if (bid > 0)
         return price <= bid;
      return false;
   }

   /** @return Aggression level (>0 = buy aggression, <0 = sell aggression). */
   double AggressionLevel(double price, double bid, double ask) const
   {
      double spread = ask - bid;
      if (spread <= 0)
         return 0;

      if (price >= ask)
         return (price - ask) / spread + 1.0;
      else if (price <= bid)
         return (bid - price) / spread - 1.0;

      return 0;
   }

   /** @return Detected aggressor side from a MqlTick. */
   ENUM_MQT_TRADE_DIRECTION Detect(const MqlTick &tick)
   {
      if ((tick.flags & TICK_FLAG_BUY) == TICK_FLAG_BUY)
         return MQT_TRADE_BUY;
      if ((tick.flags & TICK_FLAG_SELL) == TICK_FLAG_SELL)
         return MQT_TRADE_SELL;

      if (tick.last > 0 && tick.ask > 0 && tick.bid > 0)
      {
         if (tick.last >= tick.ask)
            return MQT_TRADE_BUY;
         if (tick.last <= tick.bid)
            return MQT_TRADE_SELL;
      }

      if (m_prev_price > 0)
      {
         if (tick.last > m_prev_price)
            return MQT_TRADE_BUY;
         if (tick.last < m_prev_price)
            return MQT_TRADE_SELL;
      }

      m_prev_price = tick.last;
      m_prev_bid = tick.bid;
      m_prev_ask = tick.ask;

      return MQT_TRADE_NEUTRAL;
   }

   /** @param ticks Array of MqtTick entries.
     *  @param n     Number of ticks.
     *  @return Aggression intensity in [-1, 1]. */
   double AggressionIntensity(const MqtTick &ticks[], int n,
                               double bid, double ask)
   {
      int aggressive_buys = 0;
      int aggressive_sells = 0;

      for (int i = 0; i < n; i++)
      {
         if (IsAggressiveBuy(ticks[i].last, bid, ask))
            aggressive_buys++;
         else if (IsAggressiveSell(ticks[i].last, bid, ask))
            aggressive_sells++;
      }

      double total = aggressive_buys + aggressive_sells;
      if (total > 0)
         return (aggressive_buys - aggressive_sells) / total;

      return 0;
   }

   /** Reset internal state. */
   void Reset()
   {
      m_prev_price = 0;
      m_prev_bid = 0;
      m_prev_ask = 0;
   }
};

/** Batch classifier combining Lee-Ready, tick rule, and quote methods with consensus voting. */
class CMqtBatchClassifier
{
private:
   CMqtLeeReady    m_lee_ready;
   CMqtTickRule    m_tick_rule;
   CMqtQuoteClassification m_quote_class;

public:
   /** Classify a single trade using the chosen method.
     *  @return Classified direction. */
   ENUM_MQT_TRADE_DIRECTION Classify(double price, ulong volume,
                                      double bid, double ask,
                                      ENUM_MQT_CLASSIFICATION_METHOD method)
   {
      switch (method)
      {
         case MQT_CLASS_LEE_READY:
            return m_lee_ready.Classify(price, volume, bid, ask);
         case MQT_CLASS_TICK_RULE:
            return (ENUM_MQT_TRADE_DIRECTION)m_tick_rule.Classify(price, volume);
         case MQT_CLASS_REVERSE_TICK:
            return (ENUM_MQT_TRADE_DIRECTION)m_tick_rule.ClassifyReverse(price, volume);
         case MQT_CLASS_QUOTE_BASED:
            return m_quote_class.Classify(price, bid, ask);
      }
      return MQT_TRADE_NEUTRAL;
   }

   /** Classify using exchange-provided trade flags.
     *  @return MQT_TRADE_BUY, MQT_TRADE_SELL, or MQT_TRADE_NEUTRAL. */
   ENUM_MQT_TRADE_DIRECTION ClassifyWithFlags(uint flags)
   {
      if ((flags & TICK_FLAG_BUY) == TICK_FLAG_BUY)
         return MQT_TRADE_BUY;
      if ((flags & TICK_FLAG_SELL) == TICK_FLAG_SELL)
         return MQT_TRADE_SELL;
      return MQT_TRADE_NEUTRAL;
   }

   /** Majority-vote consensus across all three classifiers.
     *  @return Classified direction. */
   ENUM_MQT_TRADE_DIRECTION Consensus(double price, ulong volume,
                                       double bid, double ask, uint flags = 0)
   {
      if ((flags & TICK_FLAG_BUY) == TICK_FLAG_BUY)
         return MQT_TRADE_BUY;
      if ((flags & TICK_FLAG_SELL) == TICK_FLAG_SELL)
         return MQT_TRADE_SELL;

      ENUM_MQT_TRADE_DIRECTION lr = m_lee_ready.Classify(price, volume, bid, ask);
      ENUM_MQT_TRADE_DIRECTION tr = (ENUM_MQT_TRADE_DIRECTION)m_tick_rule.Classify(price, volume);
      ENUM_MQT_TRADE_DIRECTION qc = m_quote_class.Classify(price, bid, ask);

      int buy_votes = 0;
      int sell_votes = 0;

      if (lr == MQT_TRADE_BUY) buy_votes++;
      else if (lr == MQT_TRADE_SELL) sell_votes++;

      if (tr == MQT_TRADE_BUY) buy_votes++;
      else if (tr == MQT_TRADE_SELL) sell_votes++;

      if (qc == MQT_TRADE_BUY) buy_votes++;
      else if (qc == MQT_TRADE_SELL) sell_votes++;

      if (buy_votes > sell_votes)
         return MQT_TRADE_BUY;
      else if (sell_votes > buy_votes)
         return MQT_TRADE_SELL;

      return MQT_TRADE_NEUTRAL;
   }

   /** Reset all sub-classifiers. */
   void ResetAll()
   {
      m_lee_ready.Reset();
      m_tick_rule.Reset();
      m_quote_class.Reset();
   }
};

#endif
