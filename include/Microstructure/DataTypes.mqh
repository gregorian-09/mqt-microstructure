/**
 * @file DataTypes.mqh
 * @brief Core data structures used throughout the library.
 *
 * All time-stamped structs use time_msc (milliseconds since 1970-01-01)
 * for sub-second precision.  Helper methods on MqtTick/MqtQuote/MqtTrade
 * provide accessors for the most common calculations (spread, mid-price,
 * trade direction from flags).
 */
#include "Constants.mqh"
#include "Config.mqh"

#ifndef MQT_DATATYPES_MQH
#define MQT_DATATYPES_MQH

/**
 * Guard definitions for TICK_FLAG_BUY/SELL on MQL5 builds older than 1720.
 */
#ifndef TICK_FLAG_BUY
#define TICK_FLAG_BUY 8
#endif
#ifndef TICK_FLAG_SELL
#define TICK_FLAG_SELL 16
#endif

/**
 * Enhanced tick structure.
 *
 * Mirrors MqlTick but adds a pre-computed direction field and
 * convenience methods for spread, mid-price, and flag-based
 * classification.  Use FromMqlTick() to populate from raw API data.
 */
struct MqtTick
{
   long      time_msc;               /*!< Millisecond timestamp */
   double    bid;                    /*!< Current bid price */
   double    ask;                    /*!< Current ask price */
   double    last;                   /*!< Last trade price */
   ulong     volume;                 /*!< Last trade volume (integer) */
   double    volume_real;            /*!< Last trade volume (float) */
   uint      flags;                  /*!< MqlTick flags (TICK_FLAG_*) */
   ENUM_MQT_TICK_DIRECTION direction;/*!< Pre-classified trade direction */

   MqtTick()
   {
      time_msc = 0; bid = 0; ask = 0; last = 0;
      volume = 0; volume_real = 0; flags = 0;
      direction = MQT_TICK_UNKNOWN;
   }

   /** @return Spread as ask-bid (0 if crossed or no quote). */
   double Spread() const { return (ask > bid && bid > 0) ? ask - bid : 0; }

   /** @return true if bid >= ask (market data error during stress). */
   bool IsCrossed() const { return bid > 0 && ask > 0 && bid >= ask; }

   /**
   * Mid-price, falling back to last if quote is crossed or missing.
   * @return (ask+bid)/2, or last, or 0.
   */
   double MidPrice() const
   {
      if (!IsCrossed() && ask > 0 && bid > 0)
         return (ask + bid) * 0.5;
      return (last > 0) ? last : 0;
   }

   /**
   * Log return from a previous price.
   * @param prev_price Previous reference price
   * @return ln(last / prev_price), or 0 if invalid.
   */
   double LogReturnFrom(double prev_price) const
   {
      return (last > 0 && prev_price > 0) ? MathLog(last / prev_price) : 0;
   }

   /** @return true if TICK_FLAG_BUY is set in flags. */
   bool IsBuy()  const { return (flags & TICK_FLAG_BUY) == TICK_FLAG_BUY; }
   /** @return true if TICK_FLAG_SELL is set in flags. */
   bool IsSell() const { return (flags & TICK_FLAG_SELL) == TICK_FLAG_SELL; }
   /** @return true if we have a valid (non-crossed) bid-ask pair. */
   bool HasBidAsk() const { return !IsCrossed() && bid > 0 && ask > 0; }
   /** @return true if this tick carries a trade (last > 0 and volume > 0). */
   bool HasTrade() const { return last > 0 && volume > 0; }

   /**
   * Populate this struct from the raw MQL5 MqlTick.
   * Copies time_msc, prices, volume, volume_real, and flags.
   */
   void FromMqlTick(const MqlTick &src)
   {
      time_msc = src.time_msc;
      bid = src.bid;
      ask = src.ask;
      last = src.last;
      volume = src.volume;
      volume_real = src.volume_real;
      flags = src.flags;
   }
};

/**
 * Quote snapshot with optional depth volumes.
 *
 * Used by CMqtQuoteCollector for tracking bid/ask updates over time.
 */
struct MqtQuote
{
   long      time_msc;          /*!< Millisecond timestamp */
   double    bid;               /*!< Bid price */
   double    ask;               /*!< Ask price */
   ulong     bid_volume;        /*!< Volume available at best bid */
   ulong     ask_volume;        /*!< Volume available at best ask */
   double    bid_depth;         /*!< Total bid depth (all levels) */
   double    ask_depth;         /*!< Total ask depth (all levels) */

   MqtQuote()
   {
      time_msc = 0; bid = 0; ask = 0;
      bid_volume = 0; ask_volume = 0;
      bid_depth = 0; ask_depth = 0;
   }

   /** @return Spread or 0. */
   double Spread() const { return (ask > 0 && bid > 0) ? ask - bid : 0; }
   /** @return (ask+bid)/2 or 0. */
   double MidPrice() const { return (ask + bid) * 0.5; }
   /** @return ln(ask/bid) or 0. */
   double LogBidAskRatio() const
   {
      return (bid > 0 && ask > 0) ? MathLog(ask / bid) : 0;
   }
   /** @return (ask-bid)/mid or 0. */
   double RelativeSpread() const
   {
      double mid = MidPrice();
      return (mid > 0) ? (ask - bid) / mid : 0;
   }
};

/**
 * Trade record with classified aggressor side.
 *
 * Used by CMqtTradeCollector for order-flow and impact analysis.
 */
struct MqtTrade
{
   long      time_msc;                /*!< Millisecond timestamp */
   double    price;                   /*!< Execution price */
   ulong     volume;                  /*!< Executed volume */
   ENUM_MQT_TRADE_DIRECTION aggressor;/*!< Inferred aggressor direction */
   bool      is_aggressive;           /*!< True if direction is not NEUTRAL */

   MqtTrade()
   {
      time_msc = 0; price = 0; volume = 0;
      aggressor = MQT_TRADE_NEUTRAL;
      is_aggressive = false;
   }
};

/**
 * A single price level in the order book.
 *
 * Mirrors MqlBookInfo: volume is long (signed) per the official struct.
 * volume_real provides greater precision when available.
 */
struct MqtOrderBookLevel
{
   double    price;           /*!< Level price */
   long      volume;          /*!< Volume at this level (long per MqlBookInfo) */
   double    volume_real;     /*!< Volume with greater accuracy */

   MqtOrderBookLevel()
   {
      price = 0; volume = 0; volume_real = 0;
   }
};

/**
 * Complete order book snapshot with sorted bids and asks.
 *
 * Bids are sorted descending (best bid at [0]).
 * Asks are sorted ascending (best ask at [0]).
 * Sorting is handled by CMqtOrderBookCollector::Snapshot().
 */
struct MqtOrderBookSnapshot
{
   long                   time_msc;             /*!< Snapshot timestamp (ms) */
      MqtOrderBookLevel      bids[MQT_MAX_BOOK_DEPTH]; /*!< Bid levels, desc price */
      MqtOrderBookLevel      asks[MQT_MAX_BOOK_DEPTH]; /*!< Ask levels, asc price */
   int                    bid_count;            /*!< Number of valid bid levels */
   int                    ask_count;            /*!< Number of valid ask levels */
   double                 bid_depth_total;      /*!< Sum of volume across all bid levels */
   double                 ask_depth_total;      /*!< Sum of volume across all ask levels */

   MqtOrderBookSnapshot()
   {
      time_msc = 0; bid_count = 0; ask_count = 0;
      bid_depth_total = 0; ask_depth_total = 0;
   }

   /**
   * Order book imbalance.
   * @return (bid_depth - ask_depth) / (bid_depth + ask_depth)
   */
   double Imbalance() const
   {
      double total = bid_depth_total + ask_depth_total;
      return (total > 0) ? (bid_depth_total - ask_depth_total) / total : 0;
   }

   /** @return bid_depth / ask_depth */
   double BidAskVolumeRatio() const
   {
      return (ask_depth_total > 0) ? bid_depth_total / ask_depth_total : 0;
   }

   /**
   * Microprice: volume-weighted mid using depth at best levels.
   * @return (best_bid * ask_depth + best_ask * bid_depth) / (bid_depth + ask_depth)
   */
   double Microprice() const
   {
      double total = bid_depth_total + ask_depth_total;
      if (total > 0 && bid_count > 0 && ask_count > 0)
      {
         return (bids[0].price * ask_depth_total +
                 asks[0].price * bid_depth_total) / total;
      }
      return 0;
   }

   /**
   * Weighted average price for a notional order on a given side.
   * Walks the book level-by-level until the notional is filled.
   * @param notional Order size in volume units
   * @param side     MQT_BOOK_BID or MQT_BOOK_ASK
   * @return Average fill price, or 0 if insufficient depth.
   */
   double WeightedAveragePrice(double notional, ENUM_MQT_BOOK_SIDE side) const
   {
      double remaining = notional;
      double total_cost = 0;
      int n = (side == MQT_BOOK_BID) ? bid_count : ask_count;

      for (int i = 0; i < n && remaining > 0; i++)
      {
         double level_vol = (side == MQT_BOOK_BID) ?
            (double)bids[i].volume : (double)asks[i].volume;
         double level_price = (side == MQT_BOOK_BID) ?
            bids[i].price : asks[i].price;

         double filled = MathMin(remaining, level_vol);
         total_cost += filled * level_price;
         remaining -= filled;
      }

      double filled_total = notional - remaining;
      return (filled_total > 0) ? total_cost / filled_total : 0;
   }
};

/**
 * Aggregated microstructure statistics for a time window.
 *
 * Populated by CMqtEventCoordinator::ComputeStats().  Every field
 * is a running average or cumulative value.  Call ToString() for
 * a formatted log line.
 */
struct MqtMicrostructureStats
{
   long      time_start_msc;              /*!< Window start (ms) */
   long      time_end_msc;                /*!< Window end (ms) */
   int       tick_count;                  /*!< Total ticks observed */
   int       trade_count;                 /*!< Trades observed */
   int       quote_count;                 /*!< Quote updates observed */
   double    avg_spread;                  /*!< Average quoted spread (bps * 1e-4) */
   double    avg_effective_spread;        /*!< Average effective spread */
   double    avg_realized_spread;         /*!< Average realised spread */
   double    total_volume;                /*!< Cumulative volume */
   double    net_order_flow;              /*!< Net signed volume (buy - sell) */
   double    realized_volatility;         /*!< Realised volatility */
   double    kyle_lambda;                 /*!< Kyle's lambda (price impact slope) */
   double    amihud_illiquidity;          /*!< Amihud illiquidity ratio */
   double    avg_bid_depth;               /*!< Average bid depth */
   double    avg_ask_depth;               /*!< Average ask depth */
   double    vpin;                        /*!< Volume-synchronised PIN */
   double    trade_intensity;             /*!< Trades per second */
   double    book_resiliency;             /*!< Order book recovery rate */
   double    info_share;                  /*!< Hasbrouck information share */
   double    volume_profile_entropy;      /*!< Normalised entropy of vol distribution */

   MqtMicrostructureStats()
   {
      time_start_msc = 0; time_end_msc = 0;
      tick_count = 0; trade_count = 0; quote_count = 0;
      avg_spread = 0; avg_effective_spread = 0; avg_realized_spread = 0;
      total_volume = 0; net_order_flow = 0; realized_volatility = 0;
      kyle_lambda = 0; amihud_illiquidity = 0;
      avg_bid_depth = 0; avg_ask_depth = 0; vpin = 0;
      trade_intensity = 0; book_resiliency = 0;
      info_share = 0; volume_profile_entropy = 0;
   }

   /**
   * Format as a human-readable string for the Experts log.
   * @return Multi-line formatted report.
   */
   string ToString() const
   {
      string out;
      StringConcatenate(out,
         "Stats [", TimeToString((datetime)(time_start_msc/1000)),
         " - ", TimeToString((datetime)(time_end_msc/1000)), "]\n",
         "  Ticks: ", tick_count, " | Trades: ", trade_count, "\n",
         "  Avg Spread: ", DoubleToString(avg_spread, 6), "\n",
         "  Eff Spread: ", DoubleToString(avg_effective_spread, 6), "\n",
         "  Rlzd Spread: ", DoubleToString(avg_realized_spread, 6), "\n",
         "  Volume: ", DoubleToString(total_volume, 0), "\n",
         "  Net OF: ", DoubleToString(net_order_flow, 0), "\n",
         "  RV: ", DoubleToString(realized_volatility, 6), "\n",
         "  Kyle Lambda: ", DoubleToString(kyle_lambda, 8), "\n",
         "  Amihud: ", DoubleToString(amihud_illiquidity, 10), "\n",
         "  VPIN: ", DoubleToString(vpin, 4), "\n",
         "  Intensity: ", DoubleToString(trade_intensity, 4), "\n",
         "  Resiliency: ", DoubleToString(book_resiliency, 4), "\n",
         "  Info Share: ", DoubleToString(info_share, 4));
      return out;
   }
};

/**
 * Result of a univariate OLS regression.
 *
 * Used internally by CMqtKyleLambda and other regression-based models.
 */
struct MqtRegressionResult
{
   double  alpha;              /*!< Intercept */
   double  beta;               /*!< Slope coefficient */
   double  alpha_se;           /*!< Standard error of intercept */
   double  beta_se;            /*!< Standard error of slope */
   double  r_squared;          /*!< R-squared (goodness of fit) */
   double  resid_variance;     /*!< Residual variance */
   int     observations;       /*!< Number of observations used */

   MqtRegressionResult()
   {
      alpha = 0; beta = 0; alpha_se = 0; beta_se = 0;
      r_squared = 0; resid_variance = 0; observations = 0;
   }
};

/**
 * Duration model estimation result.
 */
struct MqtDurationResult
{
   double  expected_duration;  /*!< Conditional expected duration */
   double  intensity;          /*!< Hazard rate */
   double  shape_param;        /*!< Weibull shape parameter */
   double  scale_param;        /*!< Weibull / exponential scale */
   double  resid_autocorr;     /*!< Residual autocorrelation at lag 1 */

   MqtDurationResult()
   {
      expected_duration = 0; intensity = 0;
      shape_param = 1.0; scale_param = 1.0; resid_autocorr = 0;
   }
};

/**
 * OHLC bar aggregated from tick data.
 *
 * Produced by CMqtTickAggregator for volume-profile and
 * volatility calculations at bar-level granularity.
 */
struct MqtOHLC
{
   long      time_msc;    /*!< Bar open time (ms) */
   double    open;        /*!< Open price */
   double    high;        /*!< High price */
   double    low;         /*!< Low price */
   double    close;       /*!< Close price */
   long      volume;      /*!< Total volume in bar */

   MqtOHLC()
   {
      time_msc = 0; open = 0; high = 0;
      low = 0; close = 0; volume = 0;
   }
};

#endif
