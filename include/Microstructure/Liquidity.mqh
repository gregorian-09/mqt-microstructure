/** @file Liquidity.mqh @brief Spread, depth, and composite liquidity analysis. */

#include "Collectors.mqh"

#ifndef MQT_LIQUIDITY_MQH
#define MQT_LIQUIDITY_MQH

/** Computes quoted, effective, and realized spreads from a tick collector. */
class CMqtSpreadAnalyzer
{
private:
   CMqtTickCollector *m_tick_collector;
   double m_quoted_spread_buffer[];    /*!< Rolling buffer of quoted spreads. */
   double m_effective_spread_buffer[]; /*!< Rolling buffer of effective spreads. */
   double m_realized_spread_buffer[];  /*!< Rolling buffer of realized spreads. */
   int    m_buffer_size;
   int    m_quote_count;
   double m_last_mid;

public:
   CMqtSpreadAnalyzer()
   {
      m_tick_collector = NULL;
      m_buffer_size = 1000;
      m_quote_count = 0;
      m_last_mid = 0;
      ArrayResize(m_quoted_spread_buffer, m_buffer_size);
      ArrayResize(m_effective_spread_buffer, m_buffer_size);
      ArrayResize(m_realized_spread_buffer, m_buffer_size);
   }

   /** @param collector  Source tick collector.
    *  @param buffer_size Rolling buffer size for spread history. */
   CMqtSpreadAnalyzer(CMqtTickCollector *collector, int buffer_size = 1000)
   {
      m_tick_collector = collector;
      m_buffer_size = buffer_size;
      m_quote_count = 0;
      m_last_mid = 0;
      ArrayResize(m_quoted_spread_buffer, m_buffer_size);
      ArrayResize(m_effective_spread_buffer, m_buffer_size);
      ArrayResize(m_realized_spread_buffer, m_buffer_size);
   }

   /** @param collector Tick collector to use. */
   void SetCollector(CMqtTickCollector *collector)
   {
      m_tick_collector = collector;
   }

   /** @return Current quoted spread as a fraction of the mid-price. */
   double QuotedSpread()
   {
      MqtTick tick;
      if (!m_tick_collector.GetLast(tick))
         return 0;

      if (tick.IsCrossed())
         return 0;

      double spread = tick.Spread();
      double mid = tick.MidPrice();
      if (mid > 0)
         return spread / mid;
      return 0;
   }

   /** @return Effective half-spread of the last trade. */
   double EffectiveSpread()
   {
      MqtTick tick;
      if (!m_tick_collector.GetLast(tick))
         return 0;

      if (tick.IsCrossed())
         return 0;

      double mid = tick.MidPrice();
      if (mid <= 0)
         return 0;

      double eff = 0;
      if (tick.direction == MQT_TICK_BUY && tick.last > 0 && tick.ask > 0)
         eff = 2.0 * (tick.last - mid) / mid;
      else if (tick.direction == MQT_TICK_SELL && tick.last > 0 && tick.bid > 0)
         eff = 2.0 * (mid - tick.last) / mid;

      if (m_quote_count < m_buffer_size)
      {
         m_effective_spread_buffer[m_quote_count] = eff;
         m_quote_count++;
      }

      return eff;
   }

   /** @param hold_ticks Number of ticks to look ahead.
     *  @return Realized spread after hold_ticks. */
   double RealizedSpread(int hold_ticks = 5)
   {
      MqtTick current, future;
      if (!m_tick_collector.GetLast(current))
         return 0;

      if (m_tick_collector.Count() <= hold_ticks)
         return 0;

      if (!m_tick_collector.GetAt(m_tick_collector.Count() - 1 - hold_ticks, future))
         return 0;

      double mid_current = current.MidPrice();
      double mid_future = future.MidPrice();

      if (mid_current <= 0 || mid_future <= 0)
         return 0;

      double realized = 0;
      if (current.direction == MQT_TICK_BUY)
         realized = 2.0 * (mid_future - mid_current) / mid_current;
      else if (current.direction == MQT_TICK_SELL)
         realized = 2.0 * (mid_current - mid_future) / mid_current;

      if (m_quote_count < m_buffer_size)
      {
         m_realized_spread_buffer[m_quote_count] = realized;
         m_quote_count++;
      }

      return realized;
   }

   /** @return Half the quoted spread. */
   double HalfSpread()
   {
      double qs = QuotedSpread();
      return qs * 0.5;
   }

   /** @param lookback Number of past observations.
     *  @return Average quoted spread over lookback. */
   double AverageQuotedSpread(int lookback = 100)
   {
      if (m_quote_count == 0)
         return 0;

      int n = MathMin(lookback, m_quote_count);
      double sum = 0;
      int valid = 0;

      for (int i = 0; i < n; i++)
      {
         if (m_quoted_spread_buffer[i] > 0)
         {
            sum += m_quoted_spread_buffer[i];
            valid++;
         }
      }

      return (valid > 0) ? sum / valid : 0;
   }

   /** @param lookback Number of past observations.
     *  @return Average effective spread over lookback. */
   double AverageEffectiveSpread(int lookback = 100)
   {
      if (m_quote_count == 0)
         return 0;

      int n = MathMin(lookback, m_quote_count);
      double sum = 0;
      int valid = 0;

      for (int i = m_quote_count - n; i < m_quote_count; i++)
      {
         int idx = i % m_buffer_size;
         if (m_effective_spread_buffer[idx] > 0)
         {
            sum += m_effective_spread_buffer[idx];
            valid++;
         }
      }

      return (valid > 0) ? sum / valid : 0;
   }

   /** @return Spread cost per share (half the effective spread). */
   double SpreadCostPerShare()
   {
      double eff = AverageEffectiveSpread();
      return eff * 0.5;
   }

   /** Clear all spread history. */
   void Reset()
   {
      m_quote_count = 0;
      ArrayInitialize(m_quoted_spread_buffer, 0);
      ArrayInitialize(m_effective_spread_buffer, 0);
      ArrayInitialize(m_realized_spread_buffer, 0);
   }
};

/** Measures order-book depth, imbalance, and market-impact cost from snapshots. */
class CMqtDepthAnalyzer
{
private:
   CMqtOrderBookCollector *m_book_collector;
   double   m_bid_depth_avg;
   double   m_ask_depth_avg;
   int      m_depth_levels;

public:
   CMqtDepthAnalyzer()
   {
      m_book_collector = NULL;
      m_bid_depth_avg = 0;
      m_ask_depth_avg = 0;
      m_depth_levels = 10;
   }

   /** @param collector Source order-book collector.
    *  @param levels    Number of price levels to consider. */
   CMqtDepthAnalyzer(CMqtOrderBookCollector *collector, int levels = 10)
   {
      m_book_collector = collector;
      m_bid_depth_avg = 0;
      m_ask_depth_avg = 0;
      m_depth_levels = levels;
   }

   /** @param collector Order-book collector to use. */
   void SetCollector(CMqtOrderBookCollector *collector)
   {
      m_book_collector = collector;
   }

   /** @param levels Number of price levels to consider (clamped to MQT_MAX_BOOK_DEPTH). */
   void SetDepthLevels(int levels)
   {
      m_depth_levels = MathMax(1, MathMin(levels, MQT_MAX_BOOK_DEPTH));
   }

   /** @return Total volume on the bid side up to m_depth_levels. */
   double TotalBidDepth()
   {
      MqtOrderBookSnapshot snap;
      if (!m_book_collector.GetLast(snap))
         return 0;

      double total = 0;
      int n = MathMin(snap.bid_count, m_depth_levels);
      for (int i = 0; i < n; i++)
         total += (double)snap.bids[i].volume;

      return total;
   }

   /** @return Total volume on the ask side up to m_depth_levels. */
   double TotalAskDepth()
   {
      MqtOrderBookSnapshot snap;
      if (!m_book_collector.GetLast(snap))
         return 0;

      double total = 0;
      int n = MathMin(snap.ask_count, m_depth_levels);
      for (int i = 0; i < n; i++)
         total += (double)snap.asks[i].volume;

      return total;
   }

   /** @return Signed depth imbalance in [-1, 1] (positive = more bid depth). */
   double DepthImbalance()
   {
      double bid = TotalBidDepth();
      double ask = TotalAskDepth();
      double total = bid + ask;

      if (total > 0)
         return (bid - ask) / total;
      return 0;
   }

   /** @param level Price level index (0 = top).
     *  @param side  Book side.
     *  @return Volume at the given level, or 0. */
   double DepthAtLevel(int level, ENUM_MQT_BOOK_SIDE side)
   {
      MqtOrderBookSnapshot snap;
      if (!m_book_collector.GetLast(snap))
         return 0;

      if (side == MQT_BOOK_BID && level < snap.bid_count)
         return (double)snap.bids[level].volume;
      else if (side == MQT_BOOK_ASK && level < snap.ask_count)
         return (double)snap.asks[level].volume;

      return 0;
   }

   /** @param notional Notional amount to execute.
     *  @return Volume-weighted average price for a market buy order. */
   double WeightedAveragePrice(double notional)
   {
      MqtOrderBookSnapshot snap;
      if (!m_book_collector.GetLast(snap))
         return 0;

      double remaining = notional;
      double total_cost = 0;

      for (int i = 0; i < snap.ask_count && remaining > 0; i++)
      {
         double filled = MathMin(remaining, (double)snap.asks[i].volume);
         total_cost += filled * snap.asks[i].price;
         remaining -= filled;
      }

      if (notional > 0 && remaining < notional)
         return total_cost / (notional - remaining);

      return 0;
   }

   /** @param notional Notional to execute.
     *  @param side     Buy or sell.
     *  @return Relative market-impact cost. */
   double MarketImpactCost(double notional, ENUM_MQT_BOOK_SIDE side)
   {
      MqtOrderBookSnapshot snap;
      if (!m_book_collector.GetLast(snap))
         return 0;

      double best_price = (side == MQT_BOOK_ASK) ? snap.asks[0].price : snap.bids[0].price;
      double exec_price = WeightedAveragePrice(notional);

      if (best_price > 0 && exec_price > 0)
      {
         if (side == MQT_BOOK_ASK)
            return (exec_price / best_price) - 1.0;
         else
            return 1.0 - (exec_price / best_price);
      }

      return 0;
   }

   /** @param lookback Number of past snapshots.
     *  @return Average total depth (bid+ask) across lookback. */
   double AverageDepth(int lookback = 10)
   {
      if (m_book_collector.Count() == 0)
         return 0;

      double bid_sum = 0;
      double ask_sum = 0;
      int n = MathMin(lookback, m_book_collector.Count());

      for (int i = 0; i < n; i++)
      {
         MqtOrderBookSnapshot snap;
         if (m_book_collector.GetAt(m_book_collector.Count() - 1 - i, snap))
         {
            for (int j = 0; j < MathMin(snap.bid_count, m_depth_levels); j++)
               bid_sum += (double)snap.bids[j].volume;
            for (int j = 0; j < MathMin(snap.ask_count, m_depth_levels); j++)
               ask_sum += (double)snap.asks[j].volume;
         }
      }

      m_bid_depth_avg = bid_sum / n;
      m_ask_depth_avg = ask_sum / n;

      return (m_bid_depth_avg + m_ask_depth_avg) * 0.5;
   }
};

/** Combines spread and depth scores into a single liquidity rating. */
class CMqtCompositeLiquidity
{
private:
   CMqtSpreadAnalyzer  *m_spread;
   CMqtDepthAnalyzer   *m_depth;
   double m_spread_weight;
   double m_depth_weight;
   double m_impact_weight;

public:
   CMqtCompositeLiquidity()
   {
      m_spread = NULL;
      m_depth = NULL;
      m_spread_weight = 0.4;
      m_depth_weight = 0.3;
      m_impact_weight = 0.3;
   }

   /** @param spread Underlying spread analyzer.
    *  @param depth  Underlying depth analyzer. */
   void SetComponents(CMqtSpreadAnalyzer *spread, CMqtDepthAnalyzer *depth)
   {
      m_spread = spread;
      m_depth = depth;
   }

   /** @param spread_w Weight for the spread component.
     *  @param depth_w  Weight for the depth component.
     *  @param impact_w Weight for the impact component. */
   void SetWeights(double spread_w, double depth_w, double impact_w)
   {
      double total = spread_w + depth_w + impact_w;
      if (total > 0)
      {
         m_spread_weight = spread_w / total;
         m_depth_weight = depth_w / total;
         m_impact_weight = impact_w / total;
      }
   }

   /** @return Composite liquidity score in [0, 1]. */
   double Score()
   {
      double spread_score = 0;
      double depth_score = 0;

      if (m_spread != NULL)
      {
         double qs = m_spread.AverageQuotedSpread(50);
         if (qs > 0)
            spread_score = MathExp(-qs * 1000);
         else
            spread_score = 1.0;
      }

      if (m_depth != NULL)
      {
         double depth = m_depth.AverageDepth(10);
         depth_score = 1.0 - MathExp(-depth / 1000.0);
      }

      return m_spread_weight * spread_score + m_depth_weight * depth_score;
   }

   /** @return Categorical rating 1.0–5.0 based on Score(). */
   double LiquidityRating()
   {
      double s = Score();
      if (s >= 0.8) return 5.0;
      if (s >= 0.6) return 4.0;
      if (s >= 0.4) return 3.0;
      if (s >= 0.2) return 2.0;
      return 1.0;
   }
};

#endif
