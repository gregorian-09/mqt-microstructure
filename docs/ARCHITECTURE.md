# Architecture

This document describes the design, data flow, and component relationships of the MQT market microstructure analysis library.

---

## Overview

MQT is an **event-driven, modular** library organised as a pipeline:

```
Market Data (ticks, quotes, DOM)
        │
        ▼
  ┌─ Collectors ──┐    Circular buffers, flag-based classification
        │
        ▼
  ┌─ Analyzers ───┐    Liquidity, Order Flow, Impact, Volatility, etc.
        │
        ▼
  ┌─ Models ──────┐    Composite scores, regime detection, spread decomposition
        │
        ▼
  ┌─ Coordinator ─┐    Event routing, lifecycle, serialization
```

All modules are **optional** — enable only what you need via the `active_modules` bitmask in `MqtConfig`.

---

## Data Flow

```mermaid
flowchart TB
    subgraph Input["Market Data Sources"]
        TICK[MqlTick from OnTick]
        DOM[MqlBookInfo from OnBookEvent]
        RATES[MqlRates from CopyRates]
    end

    subgraph Collectors["Collectors Layer"]
        TC[CMqtTickCollector]
        QC[CMqtQuoteCollector]
        TRC[CMqtTradeCollector]
        BC[CMqtOrderBookCollector]
    end

    subgraph Analyzers["Analyzers Layer"]
        SA[CMqtSpreadAnalyzer]
        DA[CMqtDepthAnalyzer]
        CVD[CMqtCumulativeVolumeDelta]
        V[CMqtVPIN]
        KL[CMqtKyleLambda]
        RV[CMqtRealizedVolatility]
        TD[CMqtTradeDuration]
        VP[CMqtVolumeProfile]
    end

    subgraph Models["Advanced Models"]
        MM[CMqtMarketMakerModel]
        MS[CMqtMicrostructureScore]
        RD[CMqtRegimeDetector]
        BR[CMqtBookResiliency]
        IS[CMqtHasbrouckInfoShare]
        LS[CMqtLiquiditySurface]
    end

    subgraph Infrastructure["Infrastructure"]
        EC[CMqtEventCoordinator]
        SER[CMqtFileSerializer]
        HP[CMqtHistoryPlayer]
    end

    TICK --> TC
    TICK --> TRC
    DOM --> BC

    TC --> SA
    TC --> CVD
    TC --> V
    TC --> KL
    TC --> RV
    TC --> TD
    TC --> VP

    BC --> DA
    BC --> BR

    SA --> MM
    SA --> MS
    SA --> RD
    KL --> MS
    KL --> RD
    RV --> RD
    V --> RD
    CVD --> RD

    EC --> TC
    EC --> SA
    EC --> KL
    EC --> MM
    EC --> MS
    EC --> RD
    EC --> SER
    EC --> HP
```

---

## Event-Driven Design

The `CMqtEventCoordinator` is the central hub. It owns (or is given) pointers to all modules and routes MQL5 events:

```mermaid
sequenceDiagram
    participant EA as Expert Advisor
    participant EC as CMqtEventCoordinator
    participant TC as CMqtTickCollector
    participant SA as CMqtSpreadAnalyzer
    participant KL as CMqtKyleLambda
    participant MS as CMqtMicrostructureScore

    EA->>EC: OnInit(config)
    EC->>TC: Init(symbol)
    EC->>SA: SetCollector(TC)
    EC->>KL: SetWindow(50)
    EC-->>EA: true

    loop Every Tick
        EA->>EC: OnTick(mqlTick)
        EC->>TC: Add(mqlTick)
        EC->>SA: EffectiveSpread()
        EC->>KL: AddFromTick(mqtTick)
    end

    loop On Demand
        EA->>EC: ComputeStats(stats)
        EC->>SA: AverageQuotedSpread()
        EC->>KL: AverageLambda()
        EC->>MS: Compute(...)
        MS->>MS: TotalScore()
        EC-->>EA: stats
    end
```

---

## Circular Buffer Design

Every collector uses a **fixed-capacity circular buffer** with O(1) push and automatic eviction of the oldest element on overflow.

```mermaid
flowchart LR
    subgraph Buffer["Circular Buffer (capacity N)"]
        H[head → oldest]
        T[tail → next write]
        E1[...]
        E2[...]
        E3[...]
    end

    H --> E1
    T --> E2
```

Key properties:

| Property | Behaviour |
|----------|-----------|
| **Push** `Add()` | Writes at `tail`, advances `tail = (tail+1) % N`. If `count == N`, advances `head` (drops oldest). |
| **Read** `GetAt(i)` | Returns element at `(head + i) % N` for `0 <= i < count`. |
| **Eviction** | Silent — no callback by default. Use `MqtOverflowCallback` via `SetOverflowCallback()` to detect drops. |
| **Count** | `Count()` returns the number of valid elements (`0..N`). |

---

## Module Dependency Graph

```mermaid
flowchart LR
    TC[CMqtTickCollector]
    SA[CMqtSpreadAnalyzer]
    DA[CMqtDepthAnalyzer]
    CVD[CMqtCumulativeVolumeDelta]
    V[CMqtVPIN]
    KL[CMqtKyleLambda]
    RV[CMqtRealizedVolatility]
    TD[CMqtTradeDuration]
    MM[CMqtMarketMakerModel]
    RD[CMqtRegimeDetector]
    MS[CMqtMicrostructureScore]
    BR[CMqtBookResiliency]
    VP[CMqtVolumeProfile]
    IS[CMqtHasbrouckInfoShare]

    SA --> MM
    SA --> MS
    SA --> RD
    DA --> MS
    CVD --> MS
    V --> RD
    V --> MS
    KL --> MM
    KL --> MS
    RV --> RD
    RV --> MS
    TD --> MS
    BR --> MS
    IS --> MS
    VP --> MS
```

Dependencies flow **upward**: Collectors have no dependencies on analyzers. Analyzers depend only on collector data (or on other analyzers for composite models). The `CMqtEventCoordinator` wires everything together and has visibility of all modules.

---

## Configuration System

`MqtConfig` uses a flat struct with safe defaults. Two preset methods override groups of fields:

```mermaid
flowchart TB
    MC[MqtConfig]
    MC --> D[Default: medium-frequency analysis]
    MC --> HF[SetHighFreq: large buffer, short windows]
    MC --> AN[SetAnalysis: small buffer, long windows]

    D --> DB[tick_buffer: 10K, kyle_window: 50, vol_lookback: 100]
    HF --> HB[tick_buffer: 50K, kyle_window: 20, vol_lookback: 50]
    AN --> AB[tick_buffer: 10K, kyle_window: 100, vol_lookback: 200]
```

Module selection:
```mermaid
flowchart LR
    CFG[MqtConfig.active_modules]
    CFG --> FLAGS[MQT_MODULE_TICK_COLLECTOR | MQT_MODULE_KYLE | ...]

    FLAGS --> AND{bitwise AND}
    AND -->|nonzero| INIT[Module initialised]
    AND -->|zero| SKIP[Module skipped]
```

---

## Serialization Format

Binary files use a simple header + payload format:

```
┌──────────────────────────────┐
│  Magic: 0x4D535400 (4 bytes) │
│  Version: 1 (4 bytes)        │
├──────────────────────────────┤
│  Stats or Snapshot payload   │
│  (variable length)           │
└──────────────────────────────┘
```

All `time_msc` and `volume` fields use 8-byte writes (`FileWriteLong`/`FileReadLong`) to avoid the 4-byte truncation bug in `FileWriteInteger`.
