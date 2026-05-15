/** @file EventCoordinator.mqh @brief Central coordinator that wires all microstructure modules together and dispatches events. */

#include "DataTypes.mqh"
#include "Collectors.mqh"
#include "Liquidity.mqh"
#include "OrderFlow.mqh"
#include "PriceImpact.mqh"
#include "Volatility.mqh"
#include "TradeClassification.mqh"
#include "DurationAnalysis.mqh"
#include "MarketModels.mqh"
#include "BookResiliency.mqh"
#include "VolumeProfile.mqh"
#include "InfoShare.mqh"
#include "Serialization.mqh"

#ifndef MQT_EVENT_COORDINATOR_MQH
#define MQT_EVENT_COORDINATOR_MQH

/** Callback for buffer overflow events. */
typedef void (*MqtOverflowCallback)(string symbol, int dropped_count, int module_id);

/** Central event coordinator that initialises, owns, and dispatches data to all microstructure modules. */
class CMqtEventCoordinator
{
public:
   /** Priority entry for a module. */
   struct MqtModulePriority
   {
      uint module;
      int  priority;
   };

private:
   string    m_symbol;
   MqtConfig m_cfg;
   int       m_error;
   bool      m_initialized;
   bool      m_overloaded;
   long      m_last_warning_msc;
   int       m_overflow_drops;
   MqtOverflowCallback m_overflow_cb;

   CMqtTickCollector        *m_ticks;
   CMqtQuoteCollector       *m_quotes;
   CMqtTradeCollector       *m_trades;
   CMqtOrderBookCollector   *m_book;
   CMqtSpreadAnalyzer       *m_spread;
   CMqtDepthAnalyzer        *m_depth;
   CMqtCumulativeVolumeDelta *m_cvd;
   CMqtOrderFlowImbalance   *m_flow;
   CMqtVPIN                 *m_vpin;
   CMqtFlowToxicity         *m_toxicity;
   CMqtKyleLambda           *m_kyle;
   CMqtAmihudIlliquidity    *m_amihud;
   CMqtHasbrouckImpact      *m_hasbrouck;
   CMqtRealizedVolatility   *m_vol;
   CMqtMicrostructureNoise  *m_noise;
   CMqtVolatilitySignature  *m_sig;
   CMqtTickRule             *m_tick_rule;
   CMqtLeeReady             *m_lee_ready;
   CMqtBatchClassifier      *m_classifier;
   CMqtTradeDuration        *m_duration;
   CMqtACDModel             *m_acd;
   CMqtIntensityEstimator   *m_intensity;
   CMqtRegimeDetector       *m_regime;
   CMqtMarketMakerModel     *m_mm_model;
   CMqtMicrostructureScore  *m_score;
   CMqtBookResiliency       *m_resiliency;
   CMqtVolumeProfile        *m_vol_profile;
   CMqtHasbrouckInfoShare   *m_info_share;

   // Hot-path flags (precomputed in Init, checked every tick)
   bool      m_run_cvd;
   bool      m_run_vpin;
   bool      m_run_kyle;
   bool      m_run_duration;
   bool      m_run_vol_profile;
   bool      m_run_spread;
   int       m_tick_counter;
   int       m_cross_check_throttle;

   struct MqtAllocRecord
   {
      void    *ptr;
      string  name;
   };
   MqtAllocRecord m_alloc_log[28];
   int m_alloc_count;

   void LogAlloc(void *ptr, string name)
   {
      if (m_alloc_count < 28)
      {
         m_alloc_log[m_alloc_count].ptr = ptr;
         m_alloc_log[m_alloc_count].name = name;
         m_alloc_count++;
      }
   }

   template<typename T>
   T* SafeAlloc(T* &ptr, string name)
   {
      if (ptr != NULL)
         return ptr;
      ptr = new T();
      if (ptr == NULL)
      {
         m_error = MQT_ERR_MEMORY;
         if (m_cfg.log_errors)
            Print("MQT: allocation failed for ", name);
      }
      else
      {
         LogAlloc(ptr, name);
      }
      return ptr;
   }

   template<typename T, typename P1>
   T* SafeAlloc1(T* &ptr, string name, P1 p1)
   {
      if (ptr != NULL)
         return ptr;
      ptr = new T(p1);
      if (ptr == NULL)
      {
         m_error = MQT_ERR_MEMORY;
         if (m_cfg.log_errors)
            Print("MQT: allocation failed for ", name);
      }
      else
      {
         LogAlloc(ptr, name);
      }
      return ptr;
   }

   void FreeAll()
   {
      for (int i = 0; i < m_alloc_count; i++)
      {
         if (m_alloc_log[i].ptr != NULL)
         {
            delete m_alloc_log[i].ptr;
            m_alloc_log[i].ptr = NULL;
         }
      }
      m_alloc_count = 0;
      m_initialized = false;
   }

public:
   /** All member pointers initialised to NULL. */
   CMqtEventCoordinator()
   {
      m_symbol = "";
      m_error = MQT_ERR_OK;
      m_initialized = false;
      m_overloaded = false;
      m_last_warning_msc = 0;
      m_overflow_drops = 0;
      m_overflow_cb = NULL;
      m_alloc_count = 0;

      m_ticks = NULL; m_quotes = NULL; m_trades = NULL; m_book = NULL;
      m_spread = NULL; m_depth = NULL; m_cvd = NULL; m_flow = NULL;
      m_vpin = NULL; m_toxicity = NULL; m_kyle = NULL; m_amihud = NULL;
      m_hasbrouck = NULL; m_vol = NULL; m_noise = NULL; m_sig = NULL;
      m_tick_rule = NULL; m_lee_ready = NULL; m_classifier = NULL;
      m_duration = NULL; m_acd = NULL; m_intensity = NULL;
      m_regime = NULL; m_mm_model = NULL; m_score = NULL;
      m_resiliency = NULL; m_vol_profile = NULL; m_info_share = NULL;
   }

   ~CMqtEventCoordinator()
   {
      FreeAll();
   }

   int LastError() const { return m_error; }
   bool IsInitialized() const { return m_initialized; }
   bool IsOverloaded() const { return m_overloaded; }
   string Symbol() const { return m_symbol; }
   MqtConfig Config() const { return m_cfg; }

   /** @param cb Callback invoked when buffers overflow. */
   void SetOverflowCallback(MqtOverflowCallback cb)
   {
      m_overflow_cb = cb;
   }

   /** @return Total number of dropped ticks due to overload. */
   int DroppedCount() const { return m_overflow_drops; }

   /** Initialise all modules specified in the config's active_modules bitmask.
     *  @param cfg Configuration struct.
     *  @return true on success. */
   bool Init(const MqtConfig &cfg)
   {
      m_cfg = cfg;
      m_symbol = cfg.symbol;
      m_error = MQT_ERR_OK;
      m_alloc_count = 0;

   if ((m_cfg.active_modules & MQT_MODULE_TICK_COLLECTOR) != 0)
   {
      SafeAlloc1(m_ticks, "TickCollector", m_cfg.tick_buffer_size);
      if (m_ticks) m_ticks.Init(m_symbol);
   }
   if ((m_cfg.active_modules & MQT_MODULE_QUOTE_COLLECTOR) != 0)
   {
      SafeAlloc1(m_quotes, "QuoteCollector", m_cfg.quote_buffer_size);
      if (m_quotes) m_quotes.Init(m_symbol);
   }
   if ((m_cfg.active_modules & MQT_MODULE_TRADE_COLLECTOR) != 0)
   {
      SafeAlloc1(m_trades, "TradeCollector", m_cfg.trade_buffer_size);
      if (m_trades) m_trades.Init(m_symbol);
   }
   if ((m_cfg.active_modules & MQT_MODULE_BOOK_COLLECTOR) != 0)
   {
      SafeAlloc1(m_book, "BookCollector", m_cfg.book_snapshot_count);
      if (m_book && !m_book.Init(m_symbol) && m_cfg.log_errors)
         Print("MQT: MarketBookAdd failed for ", m_symbol, " error=", GetLastError());
   }
   if ((m_cfg.active_modules & MQT_MODULE_SPREAD_ANALYZER) != 0)
   {
      SafeAlloc(m_spread, "SpreadAnalyzer");
      if (m_spread && m_ticks)
         m_spread.SetCollector(m_ticks);
   }
   if ((m_cfg.active_modules & MQT_MODULE_DEPTH_ANALYZER) != 0)
   {
      SafeAlloc(m_depth, "DepthAnalyzer");
      if (m_depth && m_book)
         m_depth.SetCollector(m_book);
   }
   if ((m_cfg.active_modules & MQT_MODULE_CVD) != 0)
   {
      SafeAlloc1(m_cvd, "CVD", m_cfg.cvd_lookback);
   }
   if ((m_cfg.active_modules & MQT_MODULE_VPIN) != 0)
   {
      SafeAlloc(m_vpin, "VPIN");
      if (m_vpin)
      {
         m_vpin.InitAdaptive(m_symbol);
         if (m_vpin.GetBucketVolume() <= 0)
            m_vpin.InitFromAverageVolume(m_symbol);
      }
   }
   if ((m_cfg.active_modules & MQT_MODULE_KYLE) != 0)
   {
      SafeAlloc(m_kyle, "KyleLambda");
      if (m_kyle)
      {
         m_kyle.SetWindow(m_cfg.kyle_regression_window);
         m_kyle.SetThrottle(5);
      }
   }
   if ((m_cfg.active_modules & MQT_MODULE_AMIHUD) != 0)
      SafeAlloc(m_amihud, "Amihud");
   if ((m_cfg.active_modules & MQT_MODULE_HASBROUCK) != 0)
   {
      SafeAlloc(m_hasbrouck, "Hasbrouck");
      if (m_hasbrouck)
         m_hasbrouck.SetThrottle(3);
   }
   if ((m_cfg.active_modules & MQT_MODULE_VOLATILITY) != 0)
   {
      SafeAlloc(m_vol, "Volatility");
      if (m_vol)
         m_vol.SetSamplingFrequency(m_cfg.volatility_lookback);
   }
   if ((m_cfg.active_modules & MQT_MODULE_NOISE) != 0)
      SafeAlloc(m_noise, "Noise");
   if ((m_cfg.active_modules & MQT_MODULE_DURATION) != 0)
   {
      SafeAlloc(m_duration, "Duration");
      SafeAlloc(m_acd, "ACD");
      SafeAlloc(m_intensity, "Intensity");
   }
   if ((m_cfg.active_modules & MQT_MODULE_BOOK_RESILIENCY) != 0)
   {
      SafeAlloc(m_resiliency, "Resiliency");
      if (m_resiliency)
         m_resiliency.SetBookCollector(m_book);
   }
   if ((m_cfg.active_modules & MQT_MODULE_VOLUME_PROFILE) != 0)
   {
      SafeAlloc(m_vol_profile, "VolProfile");
      if (m_vol_profile)
         m_vol_profile.InitAuto(m_symbol, m_cfg.volume_profile_bins);
   }
   if ((m_cfg.active_modules & MQT_MODULE_INFO_SHARE) != 0)
   {
      SafeAlloc(m_info_share, "InfoShare");
      if (m_info_share)
         m_info_share.SetLags(m_cfg.hasbrouck_lags);
   }

      SafeAlloc(m_flow, "FlowImbalance");
      SafeAlloc(m_toxicity, "FlowToxicity");
      SafeAlloc(m_sig, "VolSignature");
      SafeAlloc(m_tick_rule, "TickRule");
      SafeAlloc(m_lee_ready, "LeeReady");
      SafeAlloc(m_classifier, "Classifier");
      SafeAlloc(m_regime, "RegimeDetector");
      SafeAlloc(m_mm_model, "MMModel");
      SafeAlloc(m_score, "MicroScore");

      if (m_toxicity && m_vpin)
         m_toxicity.SetVPIN(m_vpin);

      m_run_cvd          = (m_cvd != NULL);
      m_run_vpin         = (m_vpin != NULL);
      m_run_kyle         = (m_kyle != NULL);
      m_run_duration     = (m_duration != NULL);
      m_run_vol_profile  = (m_vol_profile != NULL);
      m_run_spread       = (m_spread != NULL);
      m_tick_counter     = 0;
      m_cross_check_throttle = 100;

      m_initialized = true;
      return true;
   }

   /** Inject externally-owned collectors (bypasses internal allocation).
     *  @param t  Tick collector (nullable).
     *  @param q  Quote collector (nullable).
     *  @param tr Trade collector (nullable).
     *  @param b  Book collector (nullable). */
   void SetExternals(CMqtTickCollector *t, CMqtQuoteCollector *q,
                     CMqtTradeCollector *tr, CMqtOrderBookCollector *b)
   {
      m_ticks = t;
      m_quotes = q;
      m_trades = tr;
      m_book = b;

      m_run_cvd          = (m_cvd != NULL);
      m_run_vpin         = (m_vpin != NULL);
      m_run_kyle         = (m_kyle != NULL);
      m_run_duration     = (m_duration != NULL);
      m_run_vol_profile  = (m_vol_profile != NULL);
      m_run_spread       = (m_spread != NULL);
   }

   /** Process an incoming MqlTick — routes to all active sub-modules.
     *  Hot path — minimize allocations, branches, and function calls.
     *  @return true on success. */
   bool OnTick(const MqlTick &tick)
   {
      if (!m_initialized)
      {
         m_error = MQT_ERR_NOT_INITIALIZED;
         return false;
      }

      // Classify + store in one operation (no separate GetLast)
      MqtTick lt;
      if (m_ticks != NULL)
         m_ticks.Add(tick, lt);
      else
         return false;

      // Trade collector: extract from raw tick (avoids re-reading buffer)
      if (m_trades != NULL && tick.last > 0 && tick.volume > 0)
         m_trades.AddFromTick(tick);

      // IsCrossed throttle: only check every N ticks
      m_tick_counter++;
      if (m_tick_counter >= m_cross_check_throttle)
      {
         m_tick_counter = 0;
         if (lt.IsCrossed())
         {
            if (m_cfg.log_errors)
               Print("MQT: crossed market on ", m_symbol);
            return false;
         }
      }

      // Hot-path analyzer dispatch (precomputed flags, no bit-testing)
      if (m_run_cvd && lt.direction != MQT_TICK_UNKNOWN)
         m_cvd.AddFromTick(lt);
      if (m_run_vpin && lt.direction != MQT_TICK_UNKNOWN)
         m_vpin.AddTrade(lt.last, lt.volume, lt.direction);
      if (m_run_kyle)
         m_kyle.AddFromTick(lt);
      if (m_run_duration && lt.HasTrade())
      {
         m_duration.AddTrade(lt.time_msc);
         m_intensity.AddTrade(lt.time_msc);
      }
      if (m_run_vol_profile)
         m_vol_profile.AddTick(lt);
      if (m_run_spread)
         m_spread.EffectiveSpread();

      return true;
   }

   /** Process a depth-book change event.
     *  @return true on success. */
   bool OnBookEvent(string &symbol)
   {
      if (!m_initialized || symbol != m_symbol)
         return false;
      if (m_book == NULL)
         return false;

      if (m_overloaded)
      {
         if (TimeCurrent() * 1000 - m_last_warning_msc > 10000)
         {
            m_overloaded = false;
            m_last_warning_msc = TimeCurrent() * 1000;
         }
         return false;
      }

      if (!m_book.Snapshot())
         return false;

      MqtOrderBookSnapshot snap;
      if (!m_book.GetLast(snap))
         return false;

      if (snap.bid_count > 0 && snap.ask_count > 0)
      {
         if (snap.bids[0].price >= snap.asks[0].price)
         {
            if (m_cfg.log_errors && TimeCurrent() - m_last_warning_msc / 1000 > 60)
               Print("MQT: crossed book on ", m_symbol);
            m_last_warning_msc = TimeCurrent() * 1000;
            return false;
         }
      }

      if (m_depth != NULL)
         m_depth.DepthImbalance();

      if (m_resiliency != NULL)
         m_resiliency.OnBookSnapshot(snap);

      return true;
   }

   /** Process an external trade event.
     *  @return true on success. */
   bool OnTrade(double price, ulong volume, uint flags, long time_msc)
   {
      if (!m_initialized)
         return false;

      if (m_trades != NULL)
         m_trades.AddTrade(price, volume, flags, time_msc);

      if (m_resiliency != NULL)
         m_resiliency.OnTrade(time_msc, price, volume);

      if (m_info_share != NULL)
      {
         double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
         double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
         double mid = (bid > 0 && ask > 0 && bid < ask) ?
            (bid + ask) * 0.5 : price;

         static double prev_mid = 0;
         if (prev_mid > 0)
         {
            double ret = MathLog(mid / prev_mid);
             double sign = ((flags & TICK_FLAG_BUY) != 0) ? 1.0 :
                          ((flags & TICK_FLAG_SELL) != 0) ? -1.0 : 0;
            m_info_share.Add(ret, sign);
         }
         prev_mid = mid;
      }

      return true;
   }

   /** Periodic timer — drives intensity estimation and flow imbalance.
     *  @return true on success. */
   bool OnTimer()
   {
      if (!m_initialized)
         return false;

      if (m_intensity != NULL)
         m_intensity.EstimateIntensity(m_cfg.intensity_interval_sec);

      if (m_flow != NULL && m_cvd != NULL)
      {
         double buy = MathMax(0.0, m_cvd.Delta(m_cfg.cvd_lookback));
         double sell = MathMax(0.0, -m_cvd.Delta(m_cfg.cvd_lookback));
         m_flow.AddBuyVolume(buy);
         m_flow.AddSellVolume(sell);
      }

      return true;
   }

   /** @param val true to suppress book events temporarily. */
   void SetOverloaded(bool val)
   {
      m_overloaded = val;
      if (val)
         m_last_warning_msc = TimeCurrent() * 1000;
   }

   /** Populate a MqtMicrostructureStats summary from all active modules.
     *  @return true on success. */
   bool ComputeStats(MqtMicrostructureStats &stats)
   {
      if (!m_initialized)
      {
         m_error = MQT_ERR_NOT_INITIALIZED;
         return false;
      }

      stats = MqtMicrostructureStats();
      stats.time_end_msc = TimeCurrent() * 1000;

      if (m_ticks != NULL) stats.tick_count = m_ticks.Count();
      if (m_trades != NULL) stats.trade_count = m_trades.Count();
      if (m_quotes != NULL) stats.quote_count = m_quotes.Count();

      if (m_spread != NULL)
      {
         stats.avg_spread = m_spread.AverageQuotedSpread(m_cfg.spread_lookback);
         stats.avg_effective_spread = m_spread.AverageEffectiveSpread(m_cfg.spread_lookback);
      }

      if (m_cvd != NULL)
      {
         stats.total_volume = m_cvd.Volume(m_cfg.cvd_lookback);
         stats.net_order_flow = m_cvd.Cumulative();
      }

      if (m_vol != NULL)
         stats.realized_volatility = m_vol.Average(m_cfg.volatility_lookback);

      if (m_kyle != NULL)
         stats.kyle_lambda = m_kyle.AverageLambda(m_cfg.kyle_regression_window);

      if (m_amihud != NULL)
         stats.amihud_illiquidity = m_amihud.AverageIlliquidity(m_cfg.spread_lookback);

      if (m_depth != NULL)
      {
         stats.avg_bid_depth = m_depth.TotalBidDepth();
         stats.avg_ask_depth = m_depth.TotalAskDepth();
      }

      if (m_vpin != NULL)
         stats.vpin = m_vpin.CurrentVPIN();

      if (m_duration != NULL)
         stats.trade_intensity = m_duration.TradeIntensity(m_cfg.duration_lookback);

      if (m_resiliency != NULL)
         stats.book_resiliency = m_resiliency.AverageResiliency(20);

      if (m_info_share != NULL)
         stats.info_share = m_info_share.InformationShare();

      if (m_vol_profile != NULL)
         stats.volume_profile_entropy = m_vol_profile.Entropy();

      return true;
   }

   // -- Accessors to owned modules -------------------------------------------

   CMqtTickCollector        *Ticks() { return m_ticks; }
   CMqtQuoteCollector       *Quotes() { return m_quotes; }
   CMqtTradeCollector       *Trades() { return m_trades; }
   CMqtOrderBookCollector   *Book() { return m_book; }
   CMqtSpreadAnalyzer       *Spread() { return m_spread; }
   CMqtDepthAnalyzer        *Depth() { return m_depth; }
   CMqtCumulativeVolumeDelta *CVD() { return m_cvd; }
   CMqtOrderFlowImbalance   *Flow() { return m_flow; }
   CMqtVPIN                 *VPIN() { return m_vpin; }
   CMqtKyleLambda           *Kyle() { return m_kyle; }
   CMqtAmihudIlliquidity    *Amihud() { return m_amihud; }
   CMqtHasbrouckImpact      *Hasbrouck() { return m_hasbrouck; }
   CMqtRealizedVolatility   *Vol() { return m_vol; }
   CMqtMicrostructureNoise  *Noise() { return m_noise; }
   CMqtTradeDuration        *Duration() { return m_duration; }
   CMqtIntensityEstimator   *Intensity() { return m_intensity; }
   CMqtRegimeDetector       *Regime() { return m_regime; }
   CMqtMarketMakerModel     *MMModel() { return m_mm_model; }
   CMqtMicrostructureScore  *Score() { return m_score; }
   CMqtBookResiliency       *Resiliency() { return m_resiliency; }
   CMqtVolumeProfile        *VolProfile() { return m_vol_profile; }
   CMqtHasbrouckInfoShare   *InfoShare() { return m_info_share; }
};

#endif
