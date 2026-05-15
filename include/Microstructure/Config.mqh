/**
 * @file Config.mqh
 * @brief Single configuration struct consumed by CMqtEventCoordinator.
 *
 * Use MqtConfig().SetHighFreq() or .SetAnalysis() for common presets.
 * Active modules are selected via the active_modules bitmask using
 * ENUM_MQT_MODULE_FLAG values.
 */
#include "Constants.mqh"

#ifndef MQT_CONFIG_MQH
#define MQT_CONFIG_MQH

/**
 * Master configuration for the microstructure analysis pipeline.
 *
 * Every field has a safe default.  Most numeric fields are lookback
 * windows measured in number of observations (ticks, trades, etc.).
 * Presets SetHighFreq() and SetAnalysis() override groups of fields
 * for common use cases.
 */
struct MqtConfig
{
   string    symbol;                         /*!< Trading symbol (default: _Symbol) */

   // Buffer sizes
   int       tick_buffer_size;               /*!< Tick collector capacity */
   int       quote_buffer_size;              /*!< Quote collector capacity */
   int       trade_buffer_size;              /*!< Trade collector capacity */
   int       book_snapshot_count;            /*!< Order book snapshots stored */

   // Analysis windows
   int       kyle_regression_window;         /*!< OLS window for Kyle's lambda */
   int       vpin_bucket_count;              /*!< VPIN volume buckets */
   int       volatility_lookback;            /*!< RV averaging window */
   int       spread_lookback;                /*!< Spread averaging window */
   int       depth_levels;                   /*!< Book depth levels to track */
   int       duration_lookback;              /*!< Duration averaging window */
   int       cvd_lookback;                   /*!< CVD window */
   int       noise_lookback;                 /*!< Noise variance window */
   int       hasbrouck_lags;                 /*!< VAR lag count */
   int       signature_max_lag;              /*!< Max lag for vol signature */
   int       intensity_interval_sec;         /*!< Trade intensity sample interval (s) */
   int       regime_lookback;                /*!< Regime detector lookback */
   int       volume_profile_bins;            /*!< Price bins for volume profile */

   double    bucket_volume_multiplier;       /*!< VPIN bucket volume scaling */

   double    impact_spread_threshold;        /*!< Spread ratio for stress detection */
   double    impact_vol_threshold;           /*!< Volatility for stress detection */
   double    toxicity_threshold;             /*!< VPIN z-score toxicity threshold */

   bool      use_flags_classification;       /*!< Prefer TICK_FLAG_BUY/SELL */
   bool      enable_book_depth;              /*!< Subscribe to DOM */
   bool      adaptive_buffers;               /*!< Grow buffers on overflow */
   bool      log_errors;                     /*!< Print errors to Experts log */

   uint      active_modules;                /*!< Bitmask of ENUM_MQT_MODULE_FLAG */

   /**
   * Default constructor with safe defaults for medium-frequency analysis.
   */
   MqtConfig()
   {
      symbol                = _Symbol;
      tick_buffer_size      = MQT_DEFAULT_BUFFER_SIZE;
      quote_buffer_size     = MQT_DEFAULT_BUFFER_SIZE;
      trade_buffer_size     = MQT_DEFAULT_BUFFER_SIZE;
      book_snapshot_count   = 1000;
      kyle_regression_window = 50;
      vpin_bucket_count     = MQT_PIN_BUCKETS;
      volatility_lookback   = 100;
      spread_lookback       = 100;
      depth_levels          = 10;
      duration_lookback     = 100;
      cvd_lookback          = 100;
      noise_lookback        = 50;
      hasbrouck_lags        = 10;
      signature_max_lag     = MQT_SIGNATURE_LAGS;
      intensity_interval_sec = 60;
      regime_lookback       = 50;
      volume_profile_bins   = 24;
      bucket_volume_multiplier = 1.0;
      impact_spread_threshold  = 0.005;
      impact_vol_threshold     = 0.02;
      toxicity_threshold       = 2.0;
      use_flags_classification = true;
      enable_book_depth        = false;
      adaptive_buffers         = false;
      log_errors               = true;
      active_modules           = MQT_MODULE_ALL;
   }

   /**
   * High-frequency trading preset.
   *
   * Larger tick buffer, shorter regression windows, tighter thresholds.
   *
   * @param tick_buf Tick collector capacity (default: 50000)
   */
   void SetHighFreq(int tick_buf = 50000)
   {
      tick_buffer_size      = tick_buf;
      kyle_regression_window = 20;
      volatility_lookback   = 50;
      hasbrouck_lags        = 5;
      duration_lookback     = 200;
   }

   /**
   * Research / analysis preset.
   *
   * Smaller buffer, longer lookbacks, more lags for statistical accuracy.
   *
   * @param tick_buf Tick collector capacity (default: 10000)
   */
   void SetAnalysis(int tick_buf = 10000)
   {
      tick_buffer_size      = tick_buf;
      kyle_regression_window = 100;
      volatility_lookback   = 200;
      hasbrouck_lags        = 20;
      duration_lookback     = 50;
   }
};

#endif
