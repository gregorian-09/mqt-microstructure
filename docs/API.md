# API Reference

Complete reference for all public classes, methods, and structs in the MQT library.

---

## Data Types (`DataTypes.mqh`)

### MqtTick

Enhanced tick with pre-classified direction and convenience methods.

| Method | Returns | Description |
|--------|---------|-------------|
| `Spread()` | `double` | ask − bid (0 if crossed) |
| `MidPrice()` | `double` | (ask+bid)/2, falls back to last |
| `IsCrossed()` | `bool` | true if bid ≥ ask |
| `IsBuy()` | `bool` | (flags & TICK_FLAG_BUY) != 0 |
| `IsSell()` | `bool` | (flags & TICK_FLAG_SELL) != 0 |
| `HasBidAsk()` | `bool` | Valid non-crossed bid-ask pair |
| `HasTrade()` | `bool` | last > 0 && volume > 0 |
| `LogReturnFrom(prev)` | `double` | ln(last / prev) |
| `FromMqlTick(src)` | `void` | Populate from MqlTick |

### MqtQuote

| Method | Returns | Description |
|--------|---------|-------------|
| `Spread()` | `double` | ask − bid |
| `MidPrice()` | `double` | (ask+bid)/2 |
| `RelativeSpread()` | `double` | (ask−bid) / mid |
| `LogBidAskRatio()` | `double` | ln(ask/bid) |

### MqtOrderBookSnapshot

| Method | Returns | Description |
|--------|---------|-------------|
| `Imbalance()` | `double` | (bidDepth−askDepth)/(bidDepth+askDepth) |
| `Microprice()` | `double` | (bid×askDepth + ask×bidDepth) / totalDepth |
| `WeightedAveragePrice(notional, side)` | `double` | Avg fill price walking the book |

### MqtMicrostructureStats

| Method | Returns | Description |
|--------|---------|-------------|
| `ToString()` | `string` | Formatted multi-line report |

---

## Configuration (`Config.mqh`)

### MqtConfig

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `symbol` | `string` | `_Symbol` | Trading symbol |
| `tick_buffer_size` | `int` | 10000 | Tick collector capacity |
| `kyle_regression_window` | `int` | 50 | OLS window for Kyle's lambda |
| `vpin_bucket_count` | `int` | 50 | VPIN volume buckets |
| `active_modules` | `uint` | ALL | Bitmask of ENUM_MQT_MODULE_FLAG |

| Method | Description |
|--------|-------------|
| `SetHighFreq(buf)` | HFT preset: 50K buffer, 20-window Kyle, 50 vol lookback |
| `SetAnalysis(buf)` | Research preset: 10K buffer, 100-window Kyle, 200 vol lookback |

---

## Collectors (`Collectors.mqh`)

### CMqtTickCollector

Circular buffer of MqtTick with automatic direction classification.

| Method | Returns | Description |
|--------|---------|-------------|
| `Init(symbol)` | `bool` | Initialise for symbol |
| `Add(MqlTick&)` | `bool` | Add raw tick, auto-classify |
| `AddFromLastPrice(price, vol, time_msc)` | `bool` | Add synthetic tick |
| `CopyTicksFromRates(rates[], count)` | `int` | Load from MqlRates array |
| `HistoryTicks(from_msc, to_msc)` | `int` | Load historical ticks via CopyTicksRange |
| `GetAt(index, out)` | `bool` | Read element by logical index |
| `GetLast(out)` | `bool` | Read most recent tick |
| `Count()` | `int` | Number of buffered ticks |
| `Clear()` | `void` | Reset buffer |
| `Symbol()` | `string` | Symbol name |

### CMqtQuoteCollector

Circular buffer of MqtQuote.

| Method | Returns | Description |
|--------|---------|-------------|
| `Init(symbol)` | `bool` | Initialise |
| `Add(bid, ask, bidVol, askVol, bidDepth, askDepth, time_msc)` | `bool` | Store quote |
| `AddFromSymbol()` | `bool` | Fetch current quote via SymbolInfoDouble |
| `GetLast(out)` | `bool` | Most recent quote |
| `Count()` | `int` | Buffer count |
| `Clear()` | `void` | Reset |

### CMqtOrderBookCollector

DOM subscription and snapshot collection.

| Method | Returns | Description |
|--------|---------|-------------|
| `Init(symbol)` | `bool` | Calls MarketBookAdd, subscribes to DOM |
| `Snapshot()` | `bool` | Calls MarketBookGet, sorts bids desc / asks asc |
| `GetLast(out)` | `bool` | Most recent snapshot |
| `Count()` | `int` | Snapshot count |
| `IsBookOpen()` | `bool` | DOM subscription active |
| `Clear()` | `void` | Reset |

### CMqtTradeCollector

Circular buffer of MqtTrade with aggressor detection.

| Method | Returns | Description |
|--------|---------|-------------|
| `Init(symbol)` | `bool` | Initialise |
| `AddTrade(price, vol, flags, time_msc)` | `bool` | Add trade from price/volume |
| `AddFromTick(MqlTick&)` | `bool` | Extract trade from tick |
| `GetLast(out)` | `bool` | Most recent trade |
| `Count()` | `int` | Buffer count |

---

## Liquidity Analyzers (`Liquidity.mqh`)

### CMqtSpreadAnalyzer

Quoted, effective, and realised spread calculation.

| Method | Returns | Description |
|--------|---------|-------------|
| `SetCollector(CMqtTickCollector*)` | `void` | Bind to tick source |
| `QuotedSpread()` | `double` | (ask−bid)/mid, 0 if crossed |
| `EffectiveSpread()` | `double` | 2×|trade−mid|/mid, categorised by direction |
| `RealizedSpread(holdTicks)` | `double` | Effective spread after N ticks (adverse selection) |
| `AverageQuotedSpread(lookback)` | `double` | Rolling average quoted spread |
| `AverageEffectiveSpread(lookback)` | `double` | Rolling average effective spread |
| `Reset()` | `void` | Clear buffers |

### CMqtDepthAnalyzer

Order book depth analysis.

| Method | Returns | Description |
|--------|---------|-------------|
| `SetCollector(CMqtOrderBookCollector*)` | `void` | Bind to DOM source |
| `SetDepthLevels(levels)` | `void` | Number of levels to sum |
| `TotalBidDepth()` | `double` | Sum of bid volume at all tracked levels |
| `TotalAskDepth()` | `double` | Sum of ask volume |
| `DepthImbalance()` | `double` | (bid−ask)/(bid+ask) |
| `DepthAtLevel(level, side)` | `double` | Volume at specific level |
| `WeightedAveragePrice(notional)` | `double` | Average fill price for a buy order |
| `MarketImpactCost(notional, side)` | `double` | Relative cost of market order |
| `AverageDepth(lookback)` | `double` | Rolling average total depth |

### CMqtCompositeLiquidity

Weighted combination of spread + depth metrics.

| Method | Returns | Description |
|--------|---------|-------------|
| `SetComponents(spread, depth)` | `void` | Bind analyzers |
| `SetWeights(spreadW, depthW, impactW)` | `void` | Set component weights |
| `Score()` | `double` | 0–1 composite liquidity score |
| `LiquidityRating()` | `double` | 1–5 star rating |

---

## Order Flow (`OrderFlow.mqh`)

### CMqtCumulativeVolumeDelta

| Method | Returns | Description |
|--------|---------|-------------|
| `AddFromTick(tick)` | `bool` | Add buy/sell volume from classified tick |
| `Cumulative()` | `double` | Total net signed volume |
| `Delta(lookback)` | `double` | Net signed volume over window |
| `Volume(lookback)` | `double` | Total absolute volume over window |
| `DeltaRatio(lookback)` | `double` | delta / volume |
| `ZScore(lookback)` | `double` | Recent delta relative to its own distribution |
| `Reset()` | `void` | Clear |

### CMqtOrderFlowImbalance

Bar-level order flow imbalance.

| Method | Returns | Description |
|--------|---------|-------------|
| `AddBar(buyVol, sellVol)` | `bool` | Record a bar |
| `CurrentImbalance()` | `double` | (buy−sell)/(buy+sell) |
| `AverageImbalance(lookback)` | `double` | Rolling mean |
| `ImbalanceStd(lookback)` | `double` | Rolling standard deviation |
| `ExtremeImbalance(lookback)` | `double` | Max |imbalance| in window |

### CMqtVPIN

Volume-synchronised Probability of Informed Trading.

| Method | Returns | Description |
|--------|---------|-------------|
| `Init(bucketVolume)` | `void` | Set fixed bucket size |
| `InitFromAverageVolume(symbol)` | `void` | Compute bucket from D1 avg volume |
| `InitAdaptive(symbol, sampleTicks)` | `void` | Compute bucket from live tick sample |
| `AddTrade(price, volume, direction)` | `bool` | Classify trade into current bucket |
| `CurrentVPIN()` | `double` | VPIN of last completed bucket |
| `AverageVPIN(lookback)` | `double` | Rolling mean VPIN |
| `VPINStd(lookback)` | `double` | Rolling std dev |
| `IsToxic(lookback, threshold)` | `bool` | VPIN z-score > threshold |
| `ToxicityZScore(lookback)` | `double` | Current z-score |

### CMqtFlowToxicity

Combined VPIN + pressure analysis for regime detection.

| Method | Returns | Description |
|--------|---------|-------------|
| `SetVPIN(CMqtVPIN*)` | `void` | Bind VPIN source |
| `ToxicityScore()` | `double` | VPIN + z-score composite |
| `UpdatePressures(buyVol, sellVol)` | `void` | Update cumulative pressure |
| `PressureRatio()` | `double` | (buy−sell)/(buy+sell) |
| `DetectRegime()` | `ENUM_MQT_MARKET_REGIME` | Quiet/Normal/Stressed/FlashCrash |

---

## Price Impact (`PriceImpact.mqh`)

### CMqtKyleLambda

| Method | Returns | Description |
|--------|---------|-------------|
| `SetWindow(window)` | `void` | OLS lookback window |
| `SetThrottle(everyN)` | `void` | Recompute every Nth tick (default 5) |
| `Add(midPrice, signedVolume)` | `bool` | Add observation |
| `AddFromTick(tick)` | `bool` | Extract mid + direction from tick |
| `CurrentLambda()` | `double` | Most recent lambda estimate |
| `AverageLambda(lookback)` | `double` | Rolling average |
| `LambdaStd(lookback)` | `double` | Rolling std dev |
| `MarketImpactCost(orderSize)` | `double` | λ × orderSize |

### CMqtAmihudIlliquidity

| Method | Returns | Description |
|--------|---------|-------------|
| `AddBar(prevPrice, currPrice, volume)` | `bool` | Add bar observation |
| `CurrentIlliquidity()` | `double` | Most recent value |
| `AverageIlliquidity(lookback)` | `double` | Rolling average |
| `MedianIlliquidity(lookback)` | `double` | Rolling median (robust) |

### CMqtHasbrouckImpact

VAR-based impulse response decomposition.

| Method | Returns | Description |
|--------|---------|-------------|
| `SetThrottle(everyN)` | `void` | Recompute every Nth event |
| `Add(priceChange, tradeSign)` | `bool` | Add observation |
| `PermanentImpact()` | `double` | Mean impulse across lags |
| `TemporaryImpact()` | `double` | First-lag deviation from permanent |
| `ImpactAtLag(lag)` | `double` | Impulse at specific lag |
| `CumulativeImpact(lag)` | `double` | Cumulative impulse through lag |
| `InformationShare()` | `double` | Permanenet / (Permanent + Temporary) |

### CMqtAlmgrenChriss

Market impact model for optimal execution.

| Method | Returns | Description |
|--------|---------|-------------|
| `SetParameters(perm, temp, vol)` | `void` | Calibrate coefficients |
| `CalibrateFromKyle(kyle, spread, vol)` | `void` | Auto-calibrate from Kyle lambda |
| `PermanentImpact(orderSize, totalVol)` | `double` | Permament impact cost |
| `TemporaryImpact(orderSize, totalVol)` | `double` | Temporary impact cost |
| `TotalImpact(orderSize, totalVol)` | `double` | Sum of both |
| `OptimalTradingRate(riskAversion, totalVol, horizon)` | `double` | Optimal participation rate |
| `EfficientFrontierCost(orderSize, riskAversion, totalVol, horizon)` | `double` | Total cost at efficient frontier |

---

## Volatility (`Volatility.mqh`)

### CMqtRealizedVolatility

| Method | Returns | Description |
|--------|---------|-------------|
| `SetSamplingFrequency(freq)` | `void` | Tick subsampling (def: 1) |
| `ComputeFromReturns(returns[], n)` | `double` | Classic RV from log returns |
| `ComputeFromPrices(prices[], n)` | `double` | Convert prices → returns → RV |
| `ComputeParkinson(high[], low[], n)` | `double` | Parkinson HL estimator |
| `ComputeGarmanKlass(open, high, low, close, n)` | `double` | GK OHLC estimator |
| `ComputeYangZhang(open, high, low, close, n)` | `double` | YZ estimator (drift-robust) |
| `ComputeFromRates(rates[], n)` | `double` | RV from MqlRates array |
| `Current()` | `double` | Most recent RV |
| `Average(lookback)` | `double` | Rolling average |

### CMqtMicrostructureNoise

Noise variance and signal-to-noise estimation.

| Method | Returns | Description |
|--------|---------|-------------|
| `EstimateFromReturns(returns[], n)` | `double` | Noise = (RV₁ − ½RV₂) / 2 |
| `EstimateFromPrices(prices[], n)` | `double` | Convert to returns, then estimate |
| `CurrentNoiseVariance()` | `double` | Last noise estimate |
| `SignalToNoiseRatio()` | `double` | 1 / avgNoise |
| `NoiseRatio(lookback)` | `double` | noiseVar / signalVar |

### CMqtVolatilitySignature

Signature plot for optimal sampling frequency.

| Method | Returns | Description |
|--------|---------|-------------|
| `Compute(prices[], n)` | `int` | Compute RV at every lag up to maxLag |
| `GetSignature(lag)` | `double` | RV at a specific sampling lag |
| `EstimateNoiseFromSignature()` | `double` | (RV₁² − RV₂²) / 2 |
| `OptimalSamplingFrequency()` | `double` | Lag where RV stabilises |

---

## Trade Classification (`TradeClassification.mqh`)

### CMqtTickRule

Simple tick test.

| Method | Returns | Description |
|--------|---------|-------------|
| `Classify(price, volume)` | `ENUM_MQT_TICK_DIRECTION` | Buy if price > last, sell if < |
| `ClassifyReverse(price, volume)` | `ENUM_MQT_TICK_DIRECTION` | Reversed (sell on up-tick) |
| `ClassifyTick(MqlTick&)` | `ENUM_MQT_TICK_DIRECTION` | From raw tick |

### CMqtLeeReady

Full Lee-Ready algorithm using quote data.

| Method | Returns | Description |
|--------|---------|-------------|
| `Classify(price, volume, bid, ask)` | `ENUM_MQT_TRADE_DIRECTION` | Quote-relative with zero-tick fallback |
| `ClassifyMqlTick(MqlTick&)` | `ENUM_MQT_TRADE_DIRECTION` | From raw tick |
| `LastMid()` | `double` | Last observed mid-price |

### CMqtQuoteClassification

Simpler quote-relative classification.

| Method | Returns | Description |
|--------|---------|-------------|
| `Classify(price, bid, ask)` | `ENUM_MQT_TRADE_DIRECTION` | Buy if price ≥ ask, sell if ≤ bid |
| `TradePositionRelative(price)` | `double` | 0–1 position between bid and ask |
| `IsAtAsk(price)` | `bool` | Price at or above ask |
| `IsAtBid(price)` | `bool` | Price at or below bid |

### CMqtAggressorDetection

Aggression intensity measurement.

| Method | Returns | Description |
|--------|---------|-------------|
| `Detect(MqlTick&)` | `ENUM_MQT_TRADE_DIRECTION` | Flags-first, then quote, then tick rule |
| `AggressionLevel(price, bid, ask)` | `double` | How far into the spread |
| `AggressionIntensity(ticks[], n, bid, ask)` | `double` | Ratio of aggressive buys to sells |

### CMqtBatchClassifier

Multi-method consensus classification.

| Method | Returns | Description |
|--------|---------|-------------|
| `ClassifyWithFlags(flags)` | `ENUM_MQT_TRADE_DIRECTION` | Direct from TICK_FLAG_BUY/SELL |
| `Consensus(price, vol, bid, ask, flags)` | `ENUM_MQT_TRADE_DIRECTION` | Majority vote of 3 methods + flags |
| `ResetAll()` | `void` | Reset all internal classifiers |

---

## Duration Analysis (`DurationAnalysis.mqh`)

### CMqtTradeDuration

| Method | Returns | Description |
|--------|---------|-------------|
| `AddTrade(time_msc)` | `bool` | Record trade time, compute duration |
| `CurrentDuration()` | `double` | Last duration in seconds |
| `AverageDuration(lookback)` | `double` | Rolling mean |
| `MedianDuration(lookback)` | `double` | Rolling median |
| `DurationStd(lookback)` | `double` | Rolling std dev |
| `TradeIntensity(lookback)` | `double` | 1/meanDuration (trades/sec) |
| `DurationAutocorr(lag, lookback)` | `double` | Autocorrelation at lag |
| `OverdispersionRatio(lookback)` | `double` | variance/mean (>1 = overdispersed) |

### CMqtACDModel

Autoregressive Conditional Duration model.

| Method | Returns | Description |
|--------|---------|-------------|
| `SetParameters(omega, alpha, beta)` | `void` | ACD(1,1) coefficients |
| `Estimate(duration)` | `double` | Conditional expected duration |
| `ExpectedDuration()` | `double` | Current psi |
| `Intensity(duration)` | `double` | 1/expectedDuration |
| `ResidualAutocorr(lag, lookback)` | `double` | Diagnostics |
| `EstimateMLE(durations[], n)` | `bool` | Grid-search MLE calibration |

### CMqtIntensityEstimator

| Method | Returns | Description |
|--------|---------|-------------|
| `AddTrade(time_msc)` | `void` | Count trade |
| `EstimateIntensity(intervalSec)` | `double` | trades/second |
| `AverageIntensity(lookback)` | `double` | Rolling mean |
| `IntensityZScore(lookback)` | `double` | Standardised intensity |

### CMqtDiurnalAdjustment

Intraday seasonal pattern in trade durations.

| Method | Returns | Description |
|--------|---------|-------------|
| `EstimateFromDurations(durs[], times[], n)` | `bool` | 1440-minute profile |
| `AdjustDuration(raw, time)` | `double` | Deseasonalise |
| `GetSeasonal(time)` | `double` | Seasonal factor for minute |
| `SetPattern(minute, value)` | `void` | Manual override |
| `SmoothPattern(window)` | `void` | Moving average smoother |

---

## Advanced Models (`MarketModels.mqh`)

### CMqtMarketMakerModel

Spread decomposition into adverse selection, inventory, and order processing components.

| Method | Returns | Description |
|--------|---------|-------------|
| `DecomposeSpread(spread, kyle, lookback)` | `bool` | Compute three components |
| `AdverseSelectionComponent()` | `double` | Informed trading cost |
| `InventoryComponent()` | `double` | Inventory holding cost |
| `OrderProcessingComponent()` | `double` | Fixed order handling cost |
| `ProbabilityOfInformedTrading()` | `double` | AdverseSelection / (adverseSelection + orderProcessing) |

### CMqtMicrostructureScore

Composite quality score (0–1) across liquidity, flow, impact, and efficiency dimensions.

| Method | Returns | Description |
|--------|---------|-------------|
| `Compute(spread, depth, flow, kyle, vol, duration)` | `bool` | Compute all sub-scores |
| `TotalScore()` | `double` | Average of 4 sub-scores |
| `Rating()` | `string` | "Excellent" to "Very Poor" |

### CMqtRegimeDetector

Threshold-based market regime classification.

| Method | Returns | Description |
|--------|---------|-------------|
| `SetThresholds(spreadHigh, spreadLow, volHigh, volLow, vpinHigh, cvdExtreme)` | `void` | Calibrate thresholds |
| `Detect(spread, vol, vpin, cvd, flow)` | `ENUM_MQT_MARKET_REGIME` | Quiet/Normal/Stressed/FlashCrash |
| `IsStressRegime(spread, vol)` | `bool` | Quick stress check |
| `IsQuietRegime(spread, vol)` | `bool` | Quick quiet check |

### CMqtLiquiditySurface

2D (time × volume) liquidity surface.

| Method | Returns | Description |
|--------|---------|-------------|
| `Init(timeBins, volBins)` | `void` | Set resolution |
| `AddObservation(time, volume, metric)` | `bool` | Record liquidity observation |
| `GetLiquidity(time, volume)` | `double` | Lookup interpolated value |

---

## Book Resiliency (`BookResiliency.mqh`)

### CMqtBookResiliency

| Method | Returns | Description |
|--------|---------|-------------|
| `SetBookCollector(CMqtOrderBookCollector*)` | `void` | Bind DOM source |
| `SetBaseline(lookback)` | `bool` | Establish pre-trade depth baseline |
| `OnTrade(time_msc, price, volume)` | `bool` | Mark trade, start recovery timer |
| `OnBookSnapshot(snap)` | `bool` | Check recovery progress, log if complete |
| `CurrentResiliency()` | `double` | Most recent recovery rate |
| `AverageResiliency(lookback)` | `double` | Rolling mean recovery rate |
| `AverageRecoveryTime(lookback)` | `double` | Mean recovery time in ms |
| `DepthElasticity()` | `double` | preTradeDepth / avgRecoveryTime |
| `IsInRecovery()` | `bool` | Currently recovering? |

---

## Volume Profile (`VolumeProfile.mqh`)

### CMqtVolumeProfile

| Method | Returns | Description |
|--------|---------|-------------|
| `Init(bins, minPrice, maxPrice)` | `bool` | Fixed price range |
| `InitAuto(symbol, bins)` | `bool` | Auto-range from current price ±0.5% |
| `AddTrade(price, volume)` | `bool` | Add trade to bin |
| `AddTick(tick)` | `bool` | Extract trade from tick |
| `VWAP()` | `double` | Volume-weighted average price |
| `POCPrice()` | `double` | Point of Control price |
| `POCVolume()` | `double` | Volume at POC |
| `ValueAreaLow(pct)` | `double` | Low end of value area |
| `ValueAreaHigh(pct)` | `double` | High end of value area |
| `Entropy()` | `double` | Normalised distribution entropy |
| `Skew()` | `double` | Volume-weighted skewness |

---

## Information Share (`InfoShare.mqh`)

### CMqtHasbrouckInfoShare

| Method | Returns | Description |
|--------|---------|-------------|
| `SetLags(lags)` | `void` | VAR lag count |
| `Add(priceChange, tradeSign)` | `bool` | Add observation |
| `InformationShare()` | `double` | Permanent / (Permanent + Temporary) |
| `PermanentImpact()` | `double` | Mean impulse across lags |
| `TemporaryImpact()` | `double` | Transient component |
| `InnovationAtLag(lag)` | `double` | Coefficient at specific lag |

---

## Serialization (`Serialization.mqh`)

### CMqtFileSerializer

| Method | Returns | Description |
|--------|---------|-------------|
| `OpenWrite(filename)` | `bool` | Create file, write magic + version |
| `OpenRead(filename)` | `bool` | Open file, verify magic + version |
| `WriteStats(stats)` | `bool` | Serialize MqtMicrostructureStats |
| `ReadStats(stats)` | `bool` | Deserialize |
| `WriteSnapshot(snap)` | `bool` | Serialize MqtOrderBookSnapshot |
| `ReadSnapshot(snap)` | `bool` | Deserialize |
| `Close()` | `void` | Close file handle |
| `IsOpen()` | `bool` | File handle valid? |
| `LastError()` | `int` | Error code |

---

## Backtest (`Backtest.mqh`)

### CMqtHistoryPlayer

| Method | Returns | Description |
|--------|---------|-------------|
| `LoadRange(symbol, from, to, maxTicks)` | `bool` | Load tick range via CopyTicksRange |
| `LoadCount(symbol, from, count)` | `bool` | Load N ticks from timestamp |
| `NextTick(tick)` | `bool` | Iterate to next tick |
| `FeedCollector(collector, n)` | `int` | Feed ticks to CMqtTickCollector |
| `FeedTradeCollector(collector, n)` | `int` | Feed trade-only ticks |
| `Seek(position)` | `bool` | Jump to position |
| `Reset()` | `void` | Rewind to start |
| `Progress()` | `double` | 0.0–1.0 |
| `Position()` | `int` | Current tick index |
| `Total()` | `int` | Total ticks loaded |

### CMqtTickAggregator

| Method | Returns | Description |
|--------|---------|-------------|
| `SetInterval(milliseconds)` | `void` | Bar width in ms |
| `AddTick(tick)` | `bool` | Aggregate tick into current bar |
| `GetBar(index, out)` | `bool` | Read completed bar |
| `Count()` | `int` | Bar count |

---

## Event Coordinator (`EventCoordinator.mqh`)

### MqtOverflowCallback

```cpp
typedef void (*MqtOverflowCallback)(string symbol, int dropped_count, int module_id);
```

### CMqtEventCoordinator

| Method | Returns | Description |
|--------|---------|-------------|
| `Init(config)` | `bool` | Initialise all selected modules |
| `SetExternals(tick, quote, trade, book)` | `void` | Use externally-owned collectors |
| `OnTick(MqlTick&)` | `bool` | Route tick to all modules |
| `OnBookEvent(string&)` | `bool` | Take DOM snapshot, route to depth + resiliency |
| `OnTrade(price, vol, flags, time_msc)` | `bool` | Route trade to resiliency + info share |
| `OnTimer()` | `bool` | Compute intensity, flush flow |
| `SetOverloaded(bool)` | `void` | Enable/disable graceful degradation |
| `SetOverflowCallback(cb)` | `void` | Receive overflow notifications |
| `ComputeStats(stats)` | `bool` | Aggregate all module outputs |
| `Shutdown()` | `void` | Clean up (called in destructor) |
| `DroppedCount()` | `int` | Total overflow drops |
| `Ticks()` | `CMqtTickCollector*` | Access tick collector |
| `Kyle()` | `CMqtKyleLambda*` | Access Kyle lambda |
| `Score()` | `CMqtMicrostructureScore*` | Access composite score |
| *(28 accessors total)* | | One per module |

---

## Error Codes (`Constants.mqh`)

| Code | Value | Meaning |
|------|-------|---------|
| `MQT_ERR_OK` | 0 | Success |
| `MQT_ERR_INIT_FAILED` | −1 | MarketBookAdd or similar failed |
| `MQT_ERR_NULL_POINTER` | −2 | Required argument is NULL |
| `MQT_ERR_INSUFFICIENT_DATA` | −3 | Not enough observations |
| `MQT_ERR_BUFFER_FULL` | −4 | Circular buffer exhausted |
| `MQT_ERR_MARKET_BOOK_UNAVAIL` | −5 | DOM not supported by broker |
| `MQT_ERR_INVALID_PARAM` | −6 | Parameter out of range |
| `MQT_ERR_FILE_IO` | −7 | File read/write failure |
| `MQT_ERR_MEMORY` | −8 | new returned NULL |
| `MQT_ERR_NOT_INITIALIZED` | −9 | Init() not called |
| `MQT_ERR_TIMEOUT` | −10 | Tick history sync timeout |

---

## Module Flags (`Constants.mqh`)

| Flag | Value | Module |
|------|-------|--------|
| `MQT_MODULE_TICK_COLLECTOR` | 1 | CMqtTickCollector |
| `MQT_MODULE_QUOTE_COLLECTOR` | 2 | CMqtQuoteCollector |
| `MQT_MODULE_TRADE_COLLECTOR` | 4 | CMqtTradeCollector |
| `MQT_MODULE_BOOK_COLLECTOR` | 8 | CMqtOrderBookCollector |
| `MQT_MODULE_SPREAD_ANALYZER` | 16 | CMqtSpreadAnalyzer |
| `MQT_MODULE_DEPTH_ANALYZER` | 32 | CMqtDepthAnalyzer |
| `MQT_MODULE_CVD` | 64 | CMqtCumulativeVolumeDelta |
| `MQT_MODULE_VPIN` | 128 | CMqtVPIN |
| `MQT_MODULE_KYLE` | 256 | CMqtKyleLambda |
| `MQT_MODULE_AMIHUD` | 512 | CMqtAmihudIlliquidity |
| `MQT_MODULE_HASBROUCK` | 1024 | CMqtHasbrouckImpact |
| `MQT_MODULE_VOLATILITY` | 2048 | CMqtRealizedVolatility |
| `MQT_MODULE_NOISE` | 4096 | CMqtMicrostructureNoise |
| `MQT_MODULE_DURATION` | 8192 | CMqtTradeDuration |
| `MQT_MODULE_BOOK_RESILIENCY` | 16384 | CMqtBookResiliency |
| `MQT_MODULE_VOLUME_PROFILE` | 32768 | CMqtVolumeProfile |
| `MQT_MODULE_INFO_SHARE` | 65536 | CMqtHasbrouckInfoShare |
| `MQT_MODULE_ALL` | 0x7FFFFFFF | Every module |
