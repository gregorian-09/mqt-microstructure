# UML Diagrams

This document provides class hierarchy, component, and sequence diagrams using Mermaid notation.

---

## Class Hierarchy — Core Data Types

```mermaid
classDiagram
    class MqtTick {
        +long time_msc
        +double bid
        +double ask
        +double last
        +ulong volume
        +double volume_real
        +uint flags
        +ENUM_MQT_TICK_DIRECTION direction
        +Spread() double
        +MidPrice() double
        +IsCrossed() bool
        +IsBuy() bool
        +IsSell() bool
        +HasTrade() bool
        +FromMqlTick(MqlTick&) void
    }

    class MqtQuote {
        +long time_msc
        +double bid
        +double ask
        +ulong bid_volume
        +ulong ask_volume
        +Spread() double
        +MidPrice() double
        +RelativeSpread() double
    }

    class MqtTrade {
        +long time_msc
        +double price
        +ulong volume
        +ENUM_MQT_TRADE_DIRECTION aggressor
        +bool is_aggressive
    }

    class MqtOrderBookSnapshot {
        +long time_msc
        +MqtOrderBookLevel bids[50]
        +MqtOrderBookLevel asks[50]
        +int bid_count
        +int ask_count
        +double bid_depth_total
        +double ask_depth_total
        +Imbalance() double
        +Microprice() double
        +WeightedAveragePrice(double,ENUM_MQT_BOOK_SIDE) double
    }

    class MqtMicrostructureStats {
        +long time_start_msc
        +long time_end_msc
        +int tick_count
        +int trade_count
        +double avg_spread
        +double kyle_lambda
        +double vpin
        +ToString() string
    }

    class MqtConfig {
        +string symbol
        +int tick_buffer_size
        +int kyle_regression_window
        +uint active_modules
        +SetHighFreq() void
        +SetAnalysis() void
    }
```

---

## Collectors Hierarchy

```mermaid
classDiagram
    class CMqtTickCollector {
        -MqtTick m_ticks[]
        +Init(string) bool
        +Add(MqlTick&) bool
        +GetAt(int, MqtTick&) bool
        +GetLast(MqtTick&) bool
        +Count() int
        +HistoryTicks(long, long) int
        +Clear() void
    }

    class CMqtQuoteCollector {
        -MqtQuote m_quotes[]
        +Init(string) bool
        +Add(double, double) bool
        +GetLast(MqtQuote&) bool
        +Count() int
    }

    class CMqtTradeCollector {
        -MqtTrade m_trades[]
        +Init(string) bool
        +AddTrade(double, ulong, uint, long) bool
        +AddFromTick(MqlTick&) bool
        +GetLast(MqtTrade&) bool
    }

    class CMqtOrderBookCollector {
        -MqtOrderBookSnapshot m_snapshots[]
        +Init(string) bool
        +Snapshot() bool
        +GetLast(MqtOrderBookSnapshot&) bool
        +IsBookOpen() bool
    }
```

---

## Analyzers Hierarchy

```mermaid
classDiagram
    class CMqtSpreadAnalyzer {
        -CMqtTickCollector* m_tick_collector
        +SetCollector(CMqtTickCollector*) void
        +QuotedSpread() double
        +EffectiveSpread() double
        +AverageQuotedSpread(int) double
        +AverageEffectiveSpread(int) double
    }

    class CMqtDepthAnalyzer {
        -CMqtOrderBookCollector* m_book_collector
        +SetCollector(CMqtOrderBookCollector*) void
        +TotalBidDepth() double
        +TotalAskDepth() double
        +DepthImbalance() double
        +WeightedAveragePrice(double) double
    }

    class CMqtCumulativeVolumeDelta {
        +AddFromTick(MqtTick&) bool
        +Cumulative() double
        +Delta(int) double
        +DeltaRatio(int) double
        +ZScore(int) double
    }

    class CMqtVPIN {
        +InitAdaptive(string, int) void
        +AddTrade(double, ulong, ENUM_MQT_TICK_DIRECTION) bool
        +CurrentVPIN() double
        +AverageVPIN(int) double
        +IsToxic(int, double) bool
    }

    class CMqtKyleLambda {
        +SetWindow(int) void
        +SetThrottle(int) void
        +AddFromTick(MqtTick&) bool
        +CurrentLambda() double
        +AverageLambda(int) double
    }

    class CMqtRealizedVolatility {
        +ComputeFromPrices(double[], int) double
        +ComputeParkinson(double[], double[], int) double
        +ComputeGarmanKlass(double[], double[], double[], double[], int) double
        +ComputeYangZhang(double[], double[], double[], double[], int) double
        +Average(int) double
    }

    class CMqtTradeDuration {
        +AddTrade(long) bool
        +AverageDuration(int) double
        +TradeIntensity(int) double
        +DurationAutocorr(int, int) double
    }

    class CMqtLeeReady {
        +Classify(double, ulong, double, double) ENUM_MQT_TRADE_DIRECTION
        +ClassifyMqlTick(MqlTick&) ENUM_MQT_TRADE_DIRECTION
        +Reset() void
    }
```

---

## Advanced Models Hierarchy

```mermaid
classDiagram
    class CMqtMarketMakerModel {
        +DecomposeSpread(CMqtSpreadAnalyzer*, CMqtKyleLambda*, int) bool
        +AdverseSelectionComponent() double
        +ProbabilityOfInformedTrading() double
    }

    class CMqtMicrostructureScore {
        +Compute(CMqtSpreadAnalyzer*, CMqtDepthAnalyzer*, ...) bool
        +TotalScore() double
        +Rating() string
    }

    class CMqtRegimeDetector {
        +Detect(CMqtSpreadAnalyzer*, CMqtRealizedVolatility*, ...) ENUM_MQT_MARKET_REGIME
        +IsStressRegime(CMqtSpreadAnalyzer*, CMqtRealizedVolatility*) bool
    }

    class CMqtBookResiliency {
        +SetBookCollector(CMqtOrderBookCollector*) void
        +OnTrade(long, double, ulong) bool
        +OnBookSnapshot(MqtOrderBookSnapshot&) bool
        +AverageResiliency(int) double
        +AverageRecoveryTime(int) double
    }

    class CMqtVolumeProfile {
        +InitAuto(string, int) bool
        +AddTrade(double, ulong) bool
        +VWAP() double
        +POCPrice() double
        +ValueAreaLow(double) double
        +ValueAreaHigh(double) double
        +Entropy() double
    }

    class CMqtHasbrouckInfoShare {
        +SetLags(int) void
        +Add(double, double) bool
        +InformationShare() double
        +PermanentImpact() double
    }
```

---

## Event Coordinator

```mermaid
classDiagram
    class MqtOverflowCallback {
        <<typedef>>
        void(string symbol, int count, int module)
    }

    class CMqtEventCoordinator {
        -CMqtTickCollector* m_ticks
        -CMqtSpreadAnalyzer* m_spread
        -CMqtKyleLambda* m_kyle
        -CMqtBookResiliency* m_resiliency
        -CMqtHasbrouckInfoShare* m_info_share
        -MqtOverflowCallback m_overflow_cb
        +Init(MqtConfig&) bool
        +OnTick(MqlTick&) bool
        +OnBookEvent(string&) bool
        +OnTimer() bool
        +ComputeStats(MqtMicrostructureStats&) bool
        +SetOverloaded(bool) void
        +SetOverflowCallback(MqtOverflowCallback) void
        +DroppedCount() int
        +Ticks() CMqtTickCollector*
        +Kyle() CMqtKyleLambda*
        +Score() CMqtMicrostructureScore*
    }

    class CMqtFileSerializer {
        +OpenWrite(string) bool
        +OpenRead(string) bool
        +WriteStats(MqtMicrostructureStats&) bool
        +ReadStats(MqtMicrostructureStats&) bool
        +WriteSnapshot(MqtOrderBookSnapshot&) bool
        +Close() void
    }

    class CMqtHistoryPlayer {
        +LoadRange(string, datetime, datetime, int) bool
        +NextTick(MqlTick&) bool
        +FeedCollector(CMqtTickCollector*, int) int
        +Progress() double
    }
```

---

## Sequence Diagram — Tick Processing

```mermaid
sequenceDiagram
    participant EA as Expert Advisor
    participant EC as CMqtEventCoordinator
    participant TC as CMqtTickCollector
    participant Cvd as CMqtCumulativeVolumeDelta
    participant Vpin as CMqtVPIN
    participant Kyle as CMqtKyleLambda
    participant VolP as CMqtVolumeProfile

    EA->>EC: OnTick(rawTick)
    EC->>TC: Add(rawTick)
    EC->>EC: GetLast(checkTick)

    alt crossed market
        EC-->>EA: return false
    else valid tick
        EC->>Cvd: AddFromTick(checkTick)
        EC->>Vpin: AddTrade(checkTick.last, vol, dir)
        EC->>Kyle: AddFromTick(checkTick)
        EC->>VolP: AddTick(checkTick)
        EC-->>EA: return true
    end
```

---

## Sequence Diagram — Book Event with Resiliency

```mermaid
sequenceDiagram
    participant EA as Expert Advisor
    participant EC as CMqtEventCoordinator
    participant BC as CMqtOrderBookCollector
    participant DA as CMqtDepthAnalyzer
    participant BR as CMqtBookResiliency

    EA->>EC: OnBookEvent(symbol)
    EC->>BC: Snapshot()
    BC-->>EC: book data
    EC->>DA: DepthImbalance()
    EC->>BR: OnBookSnapshot(snap)
    BR-->>EC: recovery status
    EC-->>EA: return true
```

---

## Package Diagram

```mermaid
packages
    package "Microstructure Library" {
        package "Collectors" {
            CMqtTickCollector
            CMqtQuoteCollector
            CMqtTradeCollector
            CMqtOrderBookCollector
        }
        package "Analyzers" {
            CMqtSpreadAnalyzer
            CMqtDepthAnalyzer
            CMqtCumulativeVolumeDelta
            CMqtOrderFlowImbalance
            CMqtVPIN
            CMqtKyleLambda
            CMqtAmihudIlliquidity
            CMqtRealizedVolatility
            CMqtMicrostructureNoise
            CMqtTradeDuration
            CMqtACDModel
            CMqtLeeReady
            CMqtTickRule
        }
        package "Models" {
            CMqtMarketMakerModel
            CMqtMicrostructureScore
            CMqtRegimeDetector
            CMqtBookResiliency
            CMqtVolumeProfile
            CMqtHasbrouckInfoShare
        }
        package "Infrastructure" {
            CMqtEventCoordinator
            CMqtFileSerializer
            CMqtHistoryPlayer
            CMqtTickAggregator
        }
    }
```
