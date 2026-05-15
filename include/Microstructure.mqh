/**
 * @file Microstructure.mqh
 * @brief Master include for the microstructure analysis library.
 *
 * Include this single file in your EA or script to access all
 * collectors, analyzers, models, and the event coordinator.
 *
 * Usage:
 * @code
 * #include <Microstructure.mqh>
 * CMqtEventCoordinator ms;
 * ms.Init(MqtConfig().SetHighFreq());
 * // then call ms.OnTick(), ms.OnBookEvent(), etc.
 * @endcode
 */
#ifndef MICROSTRUCTURE_MQH
#define MICROSTRUCTURE_MQH

#include "Microstructure/Constants.mqh"
#include "Microstructure/Config.mqh"
#include "Microstructure/DataTypes.mqh"
#include "Microstructure/Collectors.mqh"
#include "Microstructure/Liquidity.mqh"
#include "Microstructure/OrderFlow.mqh"
#include "Microstructure/PriceImpact.mqh"
#include "Microstructure/Volatility.mqh"
#include "Microstructure/TradeClassification.mqh"
#include "Microstructure/DurationAnalysis.mqh"
#include "Microstructure/MarketModels.mqh"
#include "Microstructure/BookResiliency.mqh"
#include "Microstructure/VolumeProfile.mqh"
#include "Microstructure/InfoShare.mqh"
#include "Microstructure/Serialization.mqh"
#include "Microstructure/Backtest.mqh"
#include "Microstructure/EventCoordinator.mqh"

#endif
