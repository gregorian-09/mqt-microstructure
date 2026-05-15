# MQT — Market Microstructure Analysis Library for MQL5

A comprehensive, production-grade market microstructure analysis library for MetaTrader 5.  
Covers tick-level data collection, liquidity analysis, order flow, price impact, volatility estimation, trade classification, duration modelling, and advanced microstructure models.

---

## Features

| Domain | Classes | What it measures |
|--------|---------|------------------|
| **Data Collection** | `CMqtTickCollector`, `CMqtQuoteCollector`, `CMqtTradeCollector`, `CMqtOrderBookCollector` | Circular-buffered real-time capture of ticks, quotes, trades, and DOM snapshots |
| **Liquidity** | `CMqtSpreadAnalyzer`, `CMqtDepthAnalyzer`, `CMqtCompositeLiquidity` | Quoted/effective/realized spreads, market depth, WAP, liquidity score |
| **Order Flow** | `CMqtCumulativeVolumeDelta`, `CMqtOrderFlowImbalance`, `CMqtVPIN`, `CMqtFlowToxicity` | CVD, OFI imbalance, Volume-synchronised PIN, flow toxicity & regime |
| **Price Impact** | `CMqtKyleLambda`, `CMqtAmihudIlliquidity`, `CMqtHasbrouckImpact`, `CMqtAlmgrenChriss` | Kyle's lambda (throttled OLS), Amihud ratio, VAR impulse response, Almgren-Chriss execution |
| **Volatility** | `CMqtRealizedVolatility`, `CMqtMicrostructureNoise`, `CMqtVolatilitySignature` | Classic/Parkinson/Garman-Klass/Yang-Zhang RV, noise variance, signature plots |
| **Trade Classification** | `CMqtTickRule`, `CMqtLeeReady`, `CMqtQuoteClassification`, `CMqtAggressorDetection`, `CMqtBatchClassifier` | Tick test, Lee-Ready, quote-based, flags-first, consensus voting |
| **Duration** | `CMqtTradeDuration`, `CMqtACDModel`, `CMqtIntensityEstimator`, `CMqtDiurnalAdjustment` | Duration statistics, ACD(1,1) with MLE, hazard rate, intraday seasonality |
| **Advanced Models** | `CMqtMarketMakerModel`, `CMqtMicrostructureScore`, `CMqtRegimeDetector`, `CMqtLiquiditySurface` | Spread decomposition, composite score, 4-regime detection, liquidity surface |
| **Book Analytics** | `CMqtBookResiliency` | Post-trade depth recovery rate & elasticity |
| **Volume Profile** | `CMqtVolumeProfile` | Price-bin distribution, POC, value area, entropy, skew |
| **Information Share** | `CMqtHasbrouckInfoShare` | VAR-based permanent vs. temporary impact decomposition |
| **Infrastructure** | `CMqtEventCoordinator`, `CMqtFileSerializer`, `CMqtHistoryPlayer`, `CMqtTickAggregator` | Central orchestrator, binary serialization, historical replay, tick-to-OHLC |

---

## Quick Start

```mql5
#include <Microstructure.mqh>

CMqtEventCoordinator ms;

int OnInit() {
   MqtConfig cfg;
   cfg.symbol = _Symbol;
   cfg.SetHighFreq(50000);
   cfg.active_modules = MQT_MODULE_ALL;
   return ms.Init(cfg) ? INIT_SUCCEEDED : INIT_FAILED;
}

void OnTick()              { ms.OnTick(_LastTick); }
void OnBookEvent(string &s) { ms.OnBookEvent(s);  }
void OnTimer()             { ms.OnTimer();         }

void OnDeinit(const int) {
   MqtMicrostructureStats stats;
   ms.ComputeStats(stats);
   Print(stats.ToString());
}
```

---

## Project Structure

```
include/
  Microstructure.mqh              # Master include — add this to your EA
  Microstructure/
    Constants.mqh                  # Enums, error codes, defines
    Config.mqh                     # MqtConfig — unified configuration struct
    DataTypes.mqh                  # Core structs (Tick, Quote, Trade, Book, Stats)
    Collectors.mqh                 # CMqtTickCollector, CMqtQuoteCollector, etc.
    Liquidity.mqh                  # Spread & depth analysers
    OrderFlow.mqh                  # CVD, OFI, VPIN, flow toxicity
    PriceImpact.mqh                # Kyle's lambda, Amihud, Hasbrouck, Almgren-Chriss
    Volatility.mqh                 # Realised volatility, noise, signature
    TradeClassification.mqh        # Tick rule, Lee-Ready, quote-based, consensus
    DurationAnalysis.mqh           # Duration statistics, ACD model, intensity
    MarketModels.mqh               # Spread decomposition, score, regime, liquidity surface
    BookResiliency.mqh             # Order book recovery after trades
    VolumeProfile.mqh              # Volume distribution across price bins
    InfoShare.mqh                  # Hasbrouck information share
    Serialization.mqh              # Binary file I/O for stats and snapshots
    Backtest.mqh                   # History player and tick aggregator
    EventCoordinator.mqh           # Central orchestrator wiring all modules together
docs/
  ARCHITECTURE.md                  # Architecture overview with Mermaid diagrams
  API.md                           # Complete API reference
  MICROSTRUCTURE.md                # Microstructure concepts for traders
  UML.md                           # UML class and sequence diagrams
  CONTRIBUTING.md                  # Contributor guide
```

---

## Requirements

- **MetaTrader 5** build 1720 or later
- Symbol must have tick history available for `CopyTicksRange`
- Depth of Market requires broker support (`MarketBookAdd`/`MarketBookGet`)

---

## License

MIT — see LICENSE file.
