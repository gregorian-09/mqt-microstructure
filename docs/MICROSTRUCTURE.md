# Market Microstructure — The Complete Reference

This document is a self-contained reference to every concept, formula, and implementation detail in the MQT library.  
It is organised for three audiences:

- **Traders** want intuition and trading implications.
- **Quants** want the formulas and derivations.
- **Developers** want the class and method that implements each formula.

---

## Table of Contents

1. [Bid-Ask Spread](#1-bid-ask-spread)
2. [Order Book & Market Depth](#2-order-book--market-depth)
3. [Cumulative Volume Delta (CVD)](#3-cumulative-volume-delta-cvd)
4. [Volume-Synchronised Probability of Informed Trading (VPIN)](#4-volume-synchronised-probability-of-informed-trading-vpin)
5. [Kyle's Lambda](#5-kyles-lambda)
6. [Amihud Illiquidity](#6-amihud-illiquidity)
7. [Hasbrouck's Impulse Response](#7-hasbroucks-impulse-response)
8. [Almgren-Chriss Market Impact](#8-almgren-chriss-market-impact)
9. [Realised Volatility](#9-realised-volatility)
10. [Microstructure Noise](#10-microstructure-noise)
11. [Volatility Signature Plot](#11-volatility-signature-plot)
12. [Trade Classification](#12-trade-classification)
13. [Trade Duration & ACD Models](#13-trade-duration--acd-models)
14. [Spread Decomposition](#14-spread-decomposition)
15. [Market Regime Detection](#15-market-regime-detection)
16. [Book Resiliency](#16-book-resiliency)
17. [Volume Profile](#17-volume-profile)
18. [Hasbrouck Information Share](#18-hasbrouck-information-share)

---

## 1. Bid-Ask Spread

### 1.1 Quoted Spread

The **quoted spread** is the difference between the best ask (lowest sell order) and the best bid (highest buy order):

```
S_quoted = P_ask - P_bid
```

**Relative spread** normalises by the mid-price:

```
S_rel = (P_ask - P_bid) / P_mid
```

```
    Bid         Ask
  ───●────────────●───>
  P_bid         P_ask
    └── S_quoted ──┘
```

**Why it matters:** The quoted spread is the cost of a round-trip market order (buy at ask, sell at bid). It widens during news events, low liquidity, or market stress. A sudden spread expansion is a reliable early-warning signal.

**Implementation:** `CMqtSpreadAnalyzer::QuotedSpread()` — returns `(ask - bid) / mid`.

### 1.2 Effective Spread

The **effective spread** measures the actual cost paid by a trade, accounting for price improvement or degradation:

```
If trade is a buy (aggressor hits the ask):
  S_eff = 2 × (P_trade - P_mid) / P_mid

If trade is a sell (aggressor hits the bid):
  S_eff = 2 × (P_mid - P_trade) / P_mid
```

The factor of 2 converts a half-spread to a round-trip cost.

**Why it matters:** Effective spread is lower than quoted spread when trades execute inside the spread (price improvement) and higher when liquidity is insufficient and the trade walks the book.

**Implementation:** `CMqtSpreadAnalyzer::EffectiveSpread()` — requires a classified tick (direction known).

### 1.3 Realised Spread

The **realised spread** decomposes the effective spread into the revenue earned by the liquidity provider after accounting for adverse price movement:

```
S_realized = S_eff - 2 × (P_mid(t + n) - P_mid(t)) × direction
```

where `n` is the holding period (typically 5 ticks), `t` is the trade time, and `direction` is +1 for buys, -1 for sells.

**Why it matters:** A large realised spread means the market maker earned a profit on the spread. A small or negative realised spread after adjusting for mid-price movement indicates adverse selection — the market maker got picked off.

**Implementation:** `CMqtSpreadAnalyzer::RealizedSpread(holdTicks)` — defaults to 5 ticks.

### 1.4 Half-Spread Cost per Share

```
Cost_half = Average(S_eff) / 2
```

This is the per-share cost of demanding liquidity, used in execution cost analysis.

---

## 2. Order Book & Market Depth

### 2.1 Total Depth

Depth at a given level or cumulated across levels:

```
Depth_bid = Σ V_bid[i]   for i = 0 .. N-1
Depth_ask = Σ V_ask[i]   for i = 0 .. N-1
```

where `V[i]` is the volume at the i-th level (0 = best price).

**Implementation:** `CMqtDepthAnalyzer::TotalBidDepth()`, `::TotalAskDepth()`.

### 2.2 Depth Imbalance

Signed normalised difference between bid and ask depth:

```
Imbalance = (Depth_bid - Depth_ask) / (Depth_bid + Depth_ask)
```

Range: [-1, +1]. Positive = buying pressure, negative = selling pressure.

**Implementation:** `MqtOrderBookSnapshot::Imbalance()`.

### 2.3 Microprice

Volume-weighted mid-price using depth at the inside:

```
P_micro = (P_bid × V_ask + P_ask × V_bid) / (V_bid + V_ask)
```

The microprice is a more accurate estimate of the "true" price than the mid-price, weighted by the volume available at each side. When the microprice diverges from the mid-price, it signals an imbalance.

**Implementation:** `MqtOrderBookSnapshot::Microprice()`.

### 2.4 Weighted Average Price (WAP)

The average fill price for a market order of size `Q`:

```
WAP(Q, side) = (Σ V_filled[i] × P[i]) / Q
```

The algorithm walks the book level by level until the full order is filled:

```
for level = 0 to N-1:
    fill = min(Q_remaining, V[level])
    cost += fill × P[level]
    Q_remaining -= fill
```

**Implementation:** `MqtOrderBookSnapshot::WeightedAveragePrice(notional, side)`.

---

## 3. Cumulative Volume Delta (CVD)

### 3.1 Definition

CVD tracks the net difference between buy-initiated and sell-initiated volume:

```
CVD(t) = Σ (V_buy[i] - V_sell[i])   for i = 0 .. t
```

Each trade is classified as buy or sell using the flags-first tick rule (see Section 12).

**Why it matters:** CVD rising while price is flat = hidden accumulation (bullish divergence). CVD falling while price is rising = distribution (bearish divergence). CVD is a leading indicator.

**Implementation:** `CMqtCumulativeVolumeDelta::Cumulative()` — total sum. `::Delta(lookback)` — sum over window.

### 3.2 Delta Ratio

```
DeltaRatio = Delta(lookback) / Volume(lookback)
```

Range: [-1, +1]. Sign indicates direction, magnitude indicates conviction.

### 3.3 Z-Score

Standardised recent delta relative to its own distribution:

```
Z = (Δ_current - μ(Δ)) / σ(Δ)
```

where μ and σ are the mean and standard deviation of per-tick deltas over the lookback window. |Z| > 2 is statistically significant.

**Implementation:** `CMqtCumulativeVolumeDelta::ZScore(lookback)`.

---

## 4. Volume-Synchronised Probability of Informed Trading (VPIN)

### 4.1 Concept

VPIN estimates the probability that the current volume bucket contains informed (toxic) order flow. It is based on the Volume-Synchronised Probability of Informed Trading framework by Easley, López de Prado & O'Hara (2012).

### 4.2 Algorithm

1. Divide total volume into equal-sized **buckets** of V_bucket units.
2. Within each bucket, classify each trade as buy or sell.
3. Compute:

```
VPIN(bucket) = |V_buy[bucket] - V_sell[bucket]| / V_bucket
```

4. The reported VPIN is the rolling average over the last `n` buckets:

```
VPIN = (1/n) × Σ VPIN(i)   for i = 0 .. n-1
```

### 4.3 Bucket Sizing

Bucket volume determines sensitivity. If V_bucket is too small, VPIN is noisy. If too large, VPIN is slow.

**Adaptive method** (default): Sample N ticks, compute average tick volume, set:

```
V_bucket = max(avg_tick_vol × buckets × 5, avg_tick_vol × 10)
```

**Historical method**: Use D1 average volume / bucket_count.

**Implementation:**
- `CMqtVPIN::InitAdaptive(symbol, sampleTicks)` — live calibration
- `CMqtVPIN::InitFromAverageVolume(symbol)` — D1 calibration
- `CMqtVPIN::AddTrade(price, volume, direction)` — classify and accumulate
- `CMqtVPIN::CurrentVPIN()` — rolling average of completed buckets

### 4.4 Flow Toxicity

A VPIN z-score > 2 is considered **toxic**:

```
Z_VPIN = (VPIN_current - μ(VPIN)) / σ(VPIN)
```

The original 2012 paper found that the 2010 Flash Crash was preceded by hours of VPIN > 0.7.

**Implementation:** `CMqtVPIN::ToxicityZScore(lookback)`, `::IsToxic(lookback, threshold)`.

---

## 5. Kyle's Lambda

### 5.1 Concept

Kyle's lambda (λ) measures the **price impact per unit of signed order flow**. It is the slope of the regression:

```
ΔP = α + λ × Q_signed + ε
```

where:
- `ΔP = ln(P_t / P_{t-1})` is the log-return
- `Q_signed` is the signed volume (+ for buys, - for sells)
- `λ` is the price impact coefficient (Kyle's lambda)

A high λ means the market is illiquid — a given order causes a large price move.

### 5.2 OLS Estimation

The regression is estimated via ordinary least squares over a rolling window of `n` observations:

```
λ = (Σ (x_i - x̄)(y_i - ȳ)) / (Σ (x_i - x̄)²)

where: x_i = Q_signed[i], y_i = ΔP[i]
```

The R² measures how much of the price variance is explained by order flow:

```
R² = 1 - SS_res / SS_tot
```

### 5.3 Throttling

Since OLS is O(n) per tick and callable at tick frequency, the regression is recomputed only every `k` ticks (default: 5). Between recomputations, the last λ is returned.

**Implementation:**
- `CMqtKyleLambda::Add(mid, signedVolume)` — add observation, trigger OLS every k ticks
- `CMqtKyleLambda::CurrentLambda()` — most recent estimate
- `CMqtKyleLambda::AverageLambda(window)` — smoothed lambda
- `CMqtKyleLambda::SetThrottle(n)` — set recompute frequency

---

## 6. Amihud Illiquidity

### 6.1 Definition

The Amihud illiquidity ratio is a non-parametric measure of price impact:

```
Amihud_i = |R_i| / V_i
```

where `R_i = ln(P_i / P_{i-1})` is the absolute log-return and `V_i` is the dollar volume for bar `i`.

Higher values indicate **lower liquidity** — the same volume moves price more.

### 6.2 Interpretation

| Amihud | Liquidity | Typical for |
|--------|-----------|-------------|
| < 1×10⁻⁷ | Highly liquid | Major FX pairs |
| 1×10⁻⁶ | Liquid | Large-cap equities |
| 1×10⁻⁵ | Moderate | Small-cap equities |
| > 1×10⁻⁴ | Illiquid | Emerging market bonds |

**Implementation:** `CMqtAmihudIlliquidity::AddBar(prevPrice, currPrice, volume)`.

---

## 7. Hasbrouck's Impulse Response

### 7.1 Concept

Hasbrouck (1991) models the joint dynamics of price changes and trade signs using a vector autoregression (VAR):

```
r_t = α_1 × r_{t-1} + β_1 × x_{t-1} + ε_1,t
x_t = α_2 × r_{t-1} + β_2 × x_{t-1} + ε_2,t
```

where `r_t` is the price change (log-return) and `x_t` is the trade sign (+1 buy, -1 sell, 0 neutral).

### 7.2 Impulse Response

The impulse response function traces the effect of a one-unit trade sign shock on future price changes:

```
IRF(k) = ∂E[r_{t+k} | x_t = 1] / ∂x_t
```

The **permanent impact** is the cumulative impulse over all lags:

```
θ_perm = (1/L) × Σ |IRF(k)|   for k = 0 .. L-1
```

The **temporary impact** is the deviation of the first lag from the permanent:

```
θ_temp = |IRF(0) - θ_perm|
```

**Implementation:** `CMqtHasbrouckImpact::Add(priceChange, tradeSign)`, `::PermanentImpact()`, `::TemporaryImpact()`.

---

## 8. Almgren-Chriss Market Impact

### 8.1 Model

The Almgren-Chriss model separates impact into permanent and temporary components:

```
I(Q) = θ_perm × (Q/V)^α + θ_temp × (Q/V)^γ
```

where:
- `Q` is the order size
- `V` is the total volume
- `α ≈ 0.3` is the permanent impact exponent
- `γ ≈ 0.6` is the temporary impact exponent

### 8.2 Optimal Execution

The optimal trading rate that balances impact cost and timing risk:

```
η* = √(λ × σ² / (2 × θ_temp × T))
```

where:
- `λ` is risk aversion
- `σ²` is return variance
- `T` is execution horizon in seconds

**Implementation:** `CMqtAlmgrenChriss::TotalImpact(orderSize, totalVol)`, `::OptimalTradingRate(riskAversion, totalVol, horizon)`.

---

## 9. Realised Volatility

### 9.1 Classic Realised Volatility

```
RV = √(Σ r_i²)
```

where `r_i = ln(P_i / P_{i-1})` are log-returns over the window.

### 9.2 Parkinson Estimator

Uses only high and low prices (efficient when drift is zero):

```
σ_Parkinson = √( (1/(4 × ln2 × N)) × Σ ln(H_i / L_i)² )
```

### 9.3 Garman-Klass Estimator

Uses open, high, low, close (drift-robust):

```
σ_GK = √( (1/N) × Σ [0.5 × ln(H_i/L_i)² - (2×ln2 - 1) × ln(C_i/O_i)²] )
```

### 9.4 Yang-Zhang Estimator

The most robust — handles drift and opening jumps:

```
σ_YZ² = σ_overnight² + k × σ_open_close² + (1-k) × σ_RS²

where:
σ_overnight² = Var(ln(O_i / C_{i-1}))      // overnight returns
σ_open_close² = Var(ln(C_i / O_i))          // intraday returns
σ_RS² = Σ ln(H_i/L_i) × (ln(H_i/L_i) - ln(C_i/O_i))  // Rogers-Satchell
k = 0.34 / (1 + (N+1)/(N-1))
```

**Implementation:**
- `CMqtRealizedVolatility::ComputeFromPrices(prices[], n)` — classic RV
- `::ComputeParkinson(high[], low[], n)` — Parkinson
- `::ComputeGarmanKlass(open, high, low, close, n)` — GK
- `::ComputeYangZhang(open, high, low, close, n)` — YZ

---

## 10. Microstructure Noise

### 10.1 Noise from Overlapping RV

Microstructure noise (bid-ask bounce, tick-size effects) inflates RV at high frequencies. A simple estimator uses the difference between RV at lag 1 and lag 2:

```
σ_noise² = (RV₁ - RV₂ / 2) / 2
```

where `RV_k` is realised vol computed at k-tick sampling.

### 10.2 Signal-to-Noise Ratio

```
SNR = 1 / σ_noise²
```

High SNR means the observed price changes are mostly information, not noise.

**Implementation:** `CMqtMicrostructureNoise::EstimateFromReturns(returns[], n)`.

---

## 11. Volatility Signature Plot

### 11.1 Concept

The volatility signature plot shows RV computed at every sampling lag from 1 to L:

```
Signature(lag) = RV at lags ticks per sample
```

At very high frequencies, RV is inflated by noise. As the lag increases, RV converges to the "true" volatility. The **optimal sampling frequency** is the smallest lag where the RV curve flattens.

### 11.2 Noise from Signature

```
σ_noise² = (Signature(1)² - Signature(2)²) / 2
```

**Implementation:** `CMqtVolatilitySignature::Compute(prices[], n)`, `::OptimalSamplingFrequency()`.

---

## 12. Trade Classification

### 12.1 Flags-First (Direct)

The MQL5 `MqlTick.flags` field contains `TICK_FLAG_BUY` and `TICK_FLAG_SELL` which are set by the exchange when the tick is generated by a buy or sell trade. This is the most accurate method.

```
if (flags & TICK_FLAG_BUY)  → Buy
if (flags & TICK_FLAG_SELL) → Sell
```

**Implementation:**
- `MqtTick::IsBuy()`, `::IsSell()`
- `CMqtAggressorDetection::Detect(MqlTick&)` — checks flags first

### 12.2 Tick Rule

When flags are unavailable, classify by price comparison with the previous tick:

```
if price > prev_price → Buy (up-tick)
if price < prev_price → Sell (down-tick)
if price == prev_price:
    if volume > prev_volume → Buy (volume-uptick)
    else → Sell (volume-downtick)
```

**Implementation:** `CMqtTickRule::Classify(price, volume)`.

### 12.3 Lee-Ready Algorithm

Compare the trade price to the contemporaneous bid and ask:

```
if P_trade > mid(B, A) → Buy   (trade above mid, aggressive)
if P_trade < mid(B, A) → Sell  (trade below mid)

if P_trade == mid(B, A):        (ambiguous — use tick rule)
    classify by price change from previous trade
```

**Why it matters:** Lee-Ready is the standard in academic research. It correctly handles trades inside the spread where price didn't change but the aggressor side is known from the quote.

**Implementation:** `CMqtLeeReady::Classify(price, volume, bid, ask)`.

### 12.4 Quote-Based

Simpler: trade at the ask is a buy, at the bid is a sell:

```
if P_trade >= P_ask → Buy
if P_trade <= P_bid → Sell
else → Neutral
```

**Implementation:** `CMqtQuoteClassification::Classify(price, bid, ask)`.

### 12.5 Consensus Voting

The `CMqtBatchClassifier` combines all methods:

```
vote += (LeeReady == Buy)  ? +1 : (LeeReady == Sell)  ? -1 : 0
vote += (TickRule  == Buy) ? +1 : (TickRule  == Sell) ? -1 : 0
vote += (QuoteBase == Buy) ? +1 : (QuoteBase == Sell) ? -1 : 0
result = (vote > 0) ? Buy : (vote < 0) ? Sell : Neutral
```

Flags always override consensus when available.

**Implementation:** `CMqtBatchClassifier::Consensus(price, vol, bid, ask, flags)`.

---

## 13. Trade Duration & ACD Models

### 13.1 Trade Duration

Duration between consecutive trades:

```
d_i = (t_i - t_{i-1})  in milliseconds, converted to seconds
```

Key statistics:
- **Mean duration:** `μ_d = (1/N) × Σ d_i`
- **Std deviation:** `σ_d = √((1/(N-1)) × Σ (d_i - μ_d)²)`
- **Trade intensity:** `λ = 1 / μ_d` (trades per second)
- **Overdispersion:** `σ_d² / μ_d` — > 1 indicates clustering

**Implementation:** `CMqtTradeDuration::AddTrade(time_msc)`, `::AverageDuration()`, `::TradeIntensity()`, `::OverdispersionRatio()`.

### 13.2 Autoregressive Conditional Duration (ACD)

The ACD(1,1) model captures duration clustering:

```
ψ_i = ω + α × d_{i-1} + β × ψ_{i-1}
```

where `ψ_i` is the conditional expected duration given past durations.

**Standardised residuals:** `ε_i = d_i / ψ_i` should be i.i.d. with mean 1 if the model is correctly specified.

**MLE estimation** uses a grid search over 0 < α, β < 1 with α + β < 1:

```
LL = -Σ (ln(ψ_i) + d_i / ψ_i)
```

**Implementation:**
- `CMqtACDModel::Estimate(duration)` — on-line filtering
- `CMqtACDModel::EstimateMLE(durations[], n)` — grid-search calibration

---

## 14. Spread Decomposition

### 14.1 Huang-Stoll Model

The quoted spread is decomposed into three components:

```
S_quoted = 2 × (AS + IC + OPC)

where:
AS = Adverse Selection component (informed trading cost)
IC = Inventory component (holding cost)
OPC = Order Processing component (fixed per-trade cost)

Effective spread:  S_eff = 2 × (AS + OPC)
Realised spread:   S_rlz = 2 × OPC
```

From these, the components are:

```
AS = (S_eff - S_rlz) / 2
OPC = S_rlz / 2
IC = (S_quoted - 2 × S_eff) / 2   (if positive, else 0)
```

**Probability of Informed Trading (PIN):**

```
PIN = AS / (AS + OPC)
```

### 14.2 Implementation

`CMqtMarketMakerModel::DecomposeSpread(spreadAnalyzer, kyleLambda, lookback)` — computes AS, IC, OPC from quoted/effective/realised spreads.

---

## 15. Market Regime Detection

### 15.1 Threshold Model

Four regimes are detected by comparing current conditions to thresholds:

```
if (spread > TH_spread × 3 AND vol > TH_vol × 3) → Flash Crash
if (spread > TH_spread × 2 AND vol > TH_vol × 2) → Stressed
if (VPIN > TH_vpin AND spread > TH_spread AND vol > TH_vol) → Stressed
if (|CVD_zscore| > TH_cvd) → Stressed
if (spread < TH_spread_low AND vol < TH_vol_low AND VPIN < 0.3) → Quiet
else → Normal
```

### 15.2 Thresholds

| Parameter | Default | Meaning |
|-----------|---------|---------|
| TH_spread | 0.005 (50 bps) | High spread threshold |
| TH_spread_low | 0.0005 (5 bps) | Low spread threshold |
| TH_vol | 0.02 (2%) | High volatility threshold |
| TH_vol_low | 0.005 (0.5%) | Low volatility threshold |
| TH_vpin | 0.6 | High VPIN threshold |
| TH_cvd | 0.8 (stddevs) | Extreme CVD threshold |

**Implementation:** `CMqtRegimeDetector::Detect(spread, vol, vpin, cvd, flow)`.

---

## 16. Book Resiliency

### 16.1 Definition

**Book resiliency** measures how fast the order book recovers after a trade consumes liquidity:

```
R = 1 / T_recovery
```

where `T_recovery` is the time in milliseconds for the book depth to return to 95% of its pre-trade level.

### 16.2 Depth Elasticity

```
Elasticity = Depth_pre_trade / T_recovery (avg)
```

Higher elasticity means the book has more "spring" — it absorbs trades and recovers quickly.

### 16.3 Algorithm

```
1. Record baseline depth D_baseline (average over N pre-trade snapshots)
2. On trade: save timestamp T_trade and pre-trade depth D_pre
3. On each book update:
     recovery = current_depth / D_baseline
     if recovery >= 0.95:
         T_recovery = now - T_trade
         R = 1 / T_recovery
         reset
```

**Implementation:** `CMqtBookResiliency::OnTrade(time_msc, price, volume)`, `::OnBookSnapshot(snap)`, `::AverageResiliency(lookback)`.

---

## 17. Volume Profile

### 17.1 Price Bins

Volume is partitioned into `N` equally-spaced price bins:

```
Bin_k = [P_min + k × ΔP, P_min + (k+1) × ΔP)

where ΔP = (P_max - P_min) / N
```

### 17.2 Point of Control (POC)

The bin with the highest volume:

```
POC = argmax_k V_k
```

### 17.3 Value Area

The price range containing a specified percentage (typically 70%) of total volume. Starting from the POC, bins are added outward until the cumulative volume reaches the threshold:

```
VA_low = P_min + low_bin × ΔP
VA_high = P_min + (high_bin + 1) × ΔP
```

### 17.4 VWAP per Bin

```
VWAP_k = (Σ price_i × volume_i) / V_k   for all trades in bin k
```

### 17.5 Entropy

Normalised entropy measures how evenly volume is distributed across bins:

```
H = -(1 / ln N) × Σ p_k × ln(p_k)

where p_k = V_k / V_total
```

H → 1: volume evenly distributed (liquid market, no single fair price)  
H → 0: all volume at one price (perfect agreement on fair value)

### 17.6 Skew

Volume-weighted skewness measures asymmetry:

```
Skew = (1 / V_total × Σ V_k × (mid_k - VWAP)³) / σ³
```

Positive skew = more volume at higher prices (bullish tail).

**Implementation:** `CMqtVolumeProfile::AddTrade(price, vol)`, `::POCPrice()`, `::ValueAreaLow(0.7)`, `::Entropy()`, `::Skew()`.

---

## 18. Hasbrouck Information Share

### 18.1 Concept

Information share measures the proportion of permanent price variance attributable to a given market or order flow source:

```
IS_perm = θ_perm / (θ_perm + θ_temp)
```

where `θ_perm` is the permanent impact component and `θ_temp` is the temporary component from the VAR impulse response (Section 7).

### 18.2 Interpretation

| IS | Interpretation |
|----|----------------|
| > 0.7 | Order flow is highly informative — trades cause permanent price changes |
| 0.3 — 0.7 | Mixed — some information, some temporary impact |
| < 0.3 | Order flow is mostly noise — prices revert after trades |

**Implementation:** `CMqtHasbrouckInfoShare::InformationShare()`.

---

## References

1. Hasbrouck, J. (1991). "Measuring the Information Content of Stock Trades." *Journal of Finance*, 46(1), 179-207.  
   [https://doi.org/10.2307/2328693](https://doi.org/10.2307/2328693)

2. Easley, D., López de Prado, M., & O'Hara, M. (2012). "Flow Toxicity and Liquidity in a High-Frequency World." *Review of Financial Studies*, 25(5), 1457-1493.  
   [https://doi.org/10.1093/rfs/hhs053](https://doi.org/10.1093/rfs/hhs053)

3. Kyle, A. (1985). "Continuous Auctions and Insider Trading." *Econometrica*, 53(6), 1315-1335.  
   [https://doi.org/10.2307/1913210](https://doi.org/10.2307/1913210)

4. Amihud, Y. (2002). "Illiquidity and Stock Returns." *Journal of Financial Markets*, 5(1), 31-56.  
   [https://doi.org/10.1016/S1386-4181(01)00024-6](https://doi.org/10.1016/S1386-4181(01)00024-6)

5. Almgren, R. & Chriss, N. (2001). "Optimal Execution of Portfolio Transactions." *Journal of Risk*, 3(2), 5-39.  
   [https://doi.org/10.21314/JOR.2001.041](https://doi.org/10.21314/JOR.2001.041)

6. Lee, C. & Ready, M. (1991). "Inferring Trade Direction from Intraday Data." *Journal of Finance*, 46(2), 733-746.  
   [https://doi.org/10.2307/2328847](https://doi.org/10.2307/2328847)

7. Parkinson, M. (1980). "The Extreme Value Method for Estimating the Variance of the Rate of Return." *Journal of Business*, 53(1), 61-65.  
   [https://doi.org/10.1086/296071](https://doi.org/10.1086/296071)

8. Garman, M. & Klass, M. (1980). "On the Estimation of Security Price Volatilities from Historical Data." *Journal of Business*, 53(1), 67-78.  
   [https://doi.org/10.1086/296072](https://doi.org/10.1086/296072)

9. Yang, D. & Zhang, Q. (2000). "Drift-Independent Volatility Estimation Based on High, Low, Open, and Close Prices." *Journal of Business*, 73(3), 477-492.  
   [https://doi.org/10.1086/209650](https://doi.org/10.1086/209650)

10. Engle, R. & Russell, J. (1998). "Autoregressive Conditional Duration: A New Model for Irregularly Spaced Transaction Data." *Econometrica*, 66(5), 1127-1162.  
    [https://doi.org/10.2307/2999632](https://doi.org/10.2307/2999632)
