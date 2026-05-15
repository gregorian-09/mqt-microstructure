/**
 * @file Constants.mqh
 * @brief Fixed defines, error codes, and enumerations shared by all modules.
 *
 * Every class in the library reports errors via LastError() using the
 * ENUM_MQT_ERR codes defined here.  Module selection bitflags
 * (ENUM_MQT_MODULE_FLAG) are combined with bitwise OR and passed to
 * MqtConfig::active_modules.
 */
#ifndef MQT_CONSTANTS_MQH
#define MQT_CONSTANTS_MQH

#define MQT_MAX_BOOK_DEPTH         50
#define MQT_DEFAULT_HISTORY_SIZE   100000
#define MQT_DEFAULT_BUFFER_SIZE    10000
#define MQT_PIN_BUCKETS            50
#define MQT_SIGNATURE_LAGS         100
#define MQT_MAX_IMPACT_ORDER_SIZE  1000
#define MQT_MAX_SYMBOLS            10
#define MQT_FILE_MAGIC     0x4D535400
#define MQT_FILE_VERSION          1

/**
 * Error codes returned by LastError() across all classes.
 */
enum ENUM_MQT_ERR
{
   MQT_ERR_OK                  = 0,
   MQT_ERR_INIT_FAILED         = -1,
   MQT_ERR_NULL_POINTER        = -2,
   MQT_ERR_INSUFFICIENT_DATA   = -3,
   MQT_ERR_BUFFER_FULL         = -4,
   MQT_ERR_MARKET_BOOK_UNAVAIL = -5,
   MQT_ERR_INVALID_PARAM       = -6,
   MQT_ERR_FILE_IO             = -7,
   MQT_ERR_MEMORY              = -8,
   MQT_ERR_NOT_INITIALIZED     = -9,
   MQT_ERR_TIMEOUT             = -10
};

/**
 * Tick-implied trade direction from tick test or TICK_FLAG_BUY/SELL.
 */
enum ENUM_MQT_TICK_DIRECTION
{
   MQT_TICK_UNKNOWN = 0,
   MQT_TICK_BUY     = 1,
   MQT_TICK_SELL    = -1
};

/**
 * Trade classification algorithm selector.
 */
enum ENUM_MQT_CLASSIFICATION_METHOD
{
   MQT_CLASS_TICK_RULE,
   MQT_CLASS_LEE_READY,
   MQT_CLASS_REVERSE_TICK,
   MQT_CLASS_QUOTE_BASED
};

/**
 * Price impact model selector.
 */
enum ENUM_MQT_IMPACT_MODEL
{
   MQT_IMPACT_KYLE,
   MQT_IMPACT_HUBERMAN_STANZL,
   MQT_IMPACT_ALMGREN_CHRISS,
   MQT_IMPACT_HASBROUCK_VAR
};

/**
 * Volatility estimator selector.
 */
enum ENUM_MQT_VOLATILITY_ESTIMATOR
{
   MQT_VOL_CLASSIC,
   MQT_VOL_YANG_ZHANG,
   MQT_VOL_PARKINSON,
   MQT_VOL_GARMAN_KLASS,
   MQT_VOL_SUBSAMPLED
};

/**
 * Duration / ACD model selector.
 */
enum ENUM_MQT_DURATION_MODEL
{
   MQT_DURATION_ACD,
   MQT_DURATION_LOG_ACD,
   MQT_DURATION_EXPONENTIAL,
   MQT_DURATION_WEIBULL
};

/**
 * Order book side enumeration.
 */
enum ENUM_MQT_BOOK_SIDE
{
   MQT_BOOK_BID,
   MQT_BOOK_ASK,
   MQT_BOOK_BOTH
};

/**
 * Liquidity metric type.
 */
enum ENUM_MQT_LIQUIDITY_METRIC
{
   MQT_LIQ_QUOTED_SPREAD,
   MQT_LIQ_EFFECTIVE_SPREAD,
   MQT_LIQ_REALIZED_SPREAD,
   MQT_LIQ_DEPTH_AT_LEVEL,
   MQT_LIQ_COMPOSITE
};

/**
 * Market regime classification.
 */
enum ENUM_MQT_MARKET_REGIME
{
   MQT_REGIME_UNKNOWN,
   MQT_REGIME_QUIET,
   MQT_REGIME_NORMAL,
   MQT_REGIME_STRESSED,
   MQT_REGIME_FLASH_CRASH
};

/**
 * Order time-in-force types.
 */
enum ENUM_MQT_TIME_IN_FORCE
{
   MQT_TIF_IMMEDIATE_OR_CANCEL,
   MQT_TIF_FILL_OR_KILL,
   MQT_TIF_GOOD_TILL_CANCELLED,
   MQT_TIF_GOOD_TILL_TIME
};

/**
 * Aggressor trade direction.  BUY/SELL indicate the initiator.
 */
enum ENUM_MQT_TRADE_DIRECTION
{
   MQT_TRADE_BUY     = 1,
   MQT_TRADE_SELL    = -1,
   MQT_TRADE_NEUTRAL = 0
};

/**
 * Internal event types routed by CMqtEventCoordinator.
 */
enum ENUM_MQT_EVENT_TYPE
{
   MQT_EVENT_TICK,
   MQT_EVENT_QUOTE,
   MQT_EVENT_TRADE,
   MQT_EVENT_BOOK,
   MQT_EVENT_TIMER,
   MQT_EVENT_CUSTOM
};

/**
 * Bitmask flags for selecting active modules.
 * Combine with bitwise OR:  MQT_MODULE_TICK_COLLECTOR | MQT_MODULE_VPIN
 */
enum ENUM_MQT_MODULE_FLAG
{
   MQT_MODULE_TICK_COLLECTOR    = 1,
   MQT_MODULE_QUOTE_COLLECTOR   = 2,
   MQT_MODULE_TRADE_COLLECTOR   = 4,
   MQT_MODULE_BOOK_COLLECTOR    = 8,
   MQT_MODULE_SPREAD_ANALYZER   = 16,
   MQT_MODULE_DEPTH_ANALYZER    = 32,
   MQT_MODULE_CVD               = 64,
   MQT_MODULE_VPIN              = 128,
   MQT_MODULE_KYLE              = 256,
   MQT_MODULE_AMIHUD            = 512,
   MQT_MODULE_HASBROUCK         = 1024,
   MQT_MODULE_VOLATILITY        = 2048,
   MQT_MODULE_NOISE             = 4096,
   MQT_MODULE_DURATION          = 8192,
   MQT_MODULE_BOOK_RESILIENCY   = 16384,
   MQT_MODULE_VOLUME_PROFILE    = 32768,
   MQT_MODULE_INFO_SHARE        = 65536,
   MQT_MODULE_ALL               = 2147483647
};

#endif
