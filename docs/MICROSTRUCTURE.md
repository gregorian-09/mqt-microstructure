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

$$
S_{\text{quoted}} = P_{\text{ask}} - P_{\text{bid}}
$$

**Relative spread** normalises by the mid-price:

$$
S_{\text{rel}} = \frac{P_{\text{ask}} - P_{\text{bid}}}{P_{\text{mid}}}
$$

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

If trade is a buy (aggressor hits the ask):

$$
S_{\text{eff}} = \frac{2 \times (P_{\text{trade}} - P_{\text{mid}})}{P_{\text{mid}}}
$$

If trade is a sell (aggressor hits the bid):

$$
S_{\text{eff}} = \frac{2 \times (P_{\text{mid}} - P_{\text{trade}})}{P_{\text{mid}}}
$$

The factor of 2 converts a half-spread to a round-trip cost.

**Why it matters:** Effective spread is lower than quoted spread when trades execute inside the spread (price improvement) and higher when liquidity is insufficient and the trade walks the book.

**Implementation:** `CMqtSpreadAnalyzer::EffectiveSpread()` — requires a classified tick (direction known).

### 1.3 Realised Spread

The **realised spread** decomposes the effective spread into the revenue earned by the liquidity provider after accounting for adverse price movement:

$$
S_{\text{realized}} = S_{\text{eff}} - 2 \times (P_{\text{mid}}(t + n) - P_{\text{mid}}(t)) \times \text{direction}
$$

where $n$ is the holding period (typically 5 ticks), $t$ is the trade time, and $\text{direction}$ is +1 for buys, -1 for sells.

**Why it matters:** A large realised spread means the market maker earned a profit on the spread. A small or negative realised spread after adjusting for mid-price movement indicates adverse selection — the market maker got picked off.

**Implementation:** `CMqtSpreadAnalyzer::RealizedSpread(holdTicks)` — defaults to 5 ticks.

### 1.4 Half-Spread Cost per Share

$$
\text{Cost}_{\text{half}} = \frac{\text{Average}(S_{\text{eff}})}{2}
$$

This is the per-share cost of demanding liquidity, used in execution cost analysis.

---

## 2. Order Book & Market Depth

### 2.1 Total Depth

Depth at a given level or cumulated across levels:

$$
\text{Depth}_{\text{bid}} = \sum_{i=0}^{N-1} V_{\text{bid}}[i]
$$

$$
\text{Depth}_{\text{ask}} = \sum_{i=0}^{N-1} V_{\text{ask}}[i]
$$

where `V[i]` is the volume at the i-th level (0 = best price).

**Implementation:** `CMqtDepthAnalyzer::TotalBidDepth()`, `::TotalAskDepth()`.

### 2.2 Depth Imbalance

Signed normalised difference between bid and ask depth:

$$
\text{Imbalance} = \frac{\text{Depth}_{\text{bid}} - \text{Depth}_{\text{ask}}}{\text{Depth}_{\text{bid}} + \text{Depth}_{\text{ask}}}
$$

Range: [-1, +1]. Positive = buying pressure, negative = selling pressure.

**Implementation:** `MqtOrderBookSnapshot::Imbalance()`.

### 2.3 Microprice

Volume-weighted mid-price using depth at the inside:

$$
P_{\text{micro}} = \frac{P_{\text{bid}} \times V_{\text{ask}} + P_{\text{ask}} \times V_{\text{bid}}}{V_{\text{bid}} + V_{\text{ask}}}
$$

The microprice is a more accurate estimate of the "true" price than the mid-price, weighted by the volume available at each side. When the microprice diverges from the mid-price, it signals an imbalance.

**Implementation:** `MqtOrderBookSnapshot::Microprice()`.

### 2.4 Weighted Average Price (WAP)

The average fill price for a market order of size $Q$:

$$
\text{WAP}(Q, \text{side}) = \frac{\sum V_{\text{filled}}[i] \times P[i]}{Q}
$$

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

$$
\text{CVD}(t) = \sum_{i=0}^{t} (V_{\text{buy}}[i] - V_{\text{sell}}[i])
$$

Each trade is classified as buy or sell using the flags-first tick rule (see Section 12).

**Why it matters:** CVD rising while price is flat = hidden accumulation (bullish divergence). CVD falling while price is rising = distribution (bearish divergence). CVD is a leading indicator.

**Implementation:** `CMqtCumulativeVolumeDelta::Cumulative()` — total sum. `::Delta(lookback)` — sum over window.

### 3.2 Delta Ratio

$$
\text{DeltaRatio} = \frac{\text{Delta}(\text{lookback})}{\text{Volume}(\text{lookback})}
$$

Range: [-1, +1]. Sign indicates direction, magnitude indicates conviction.

### 3.3 Z-Score

Standardised recent delta relative to its own distribution:

$$
Z = \frac{\Delta_{\text{current}} - \mu(\Delta)}{\sigma(\Delta)}
$$

where $\mu$ and $\sigma$ are the mean and standard deviation of per-tick deltas over the lookback window. $|Z| > 2$ is statistically significant.

**Implementation:** `CMqtCumulativeVolumeDelta::ZScore(lookback)`.

---

## 4. Volume-Synchronised Probability of Informed Trading (VPIN)

### 4.1 Concept

VPIN estimates the probability that the current volume bucket contains informed (toxic) order flow. It is based on the Volume-Synchronised Probability of Informed Trading framework by Easley, López de Prado & O'Hara (2012).

### 4.2 Algorithm

1. Divide total volume into equal-sized **buckets** of $V_{\text{bucket}}$ units.
2. Within each bucket, classify each trade as buy or sell.
3. Compute:

$$
\text{VPIN}(\text{bucket}) = \frac{|V_{\text{buy}}[\text{bucket}] - V_{\text{sell}}[\text{bucket}]|}{V_{\text{bucket}}}
$$

4. The reported VPIN is the rolling average over the last $n$ buckets:

$$
\text{VPIN} = \frac{1}{n} \times \sum_{i=0}^{n-1} \text{VPIN}(i)
$$

### 4.3 Bucket Sizing

Bucket volume determines sensitivity. If $V_{\text{bucket}}$ is too small, VPIN is noisy. If too large, VPIN is slow.

**Adaptive method** (default): Sample N ticks, compute average tick volume, set:

$$
V_{\text{bucket}} =
\max\left(
\mathrm{avg\_tick\_vol} \times \mathrm{buckets} \times 5,\;
\mathrm{avg\_tick\_vol} \times 10
\right)
$$

**Historical method**: Use D1 average volume / bucket_count.

**Implementation:**
- `CMqtVPIN::InitAdaptive(symbol, sampleTicks)` — live calibration
- `CMqtVPIN::InitFromAverageVolume(symbol)` — D1 calibration
- `CMqtVPIN::AddTrade(price, volume, direction)` — classify and accumulate
- `CMqtVPIN::CurrentVPIN()` — rolling average of completed buckets

### 4.4 Flow Toxicity

A VPIN z-score > 2 is considered **toxic**:

$$
Z_{\text{VPIN}} = \frac{\text{VPIN}_{\text{current}} - \mu(\text{VPIN})}{\sigma(\text{VPIN})}
$$

The original 2012 paper found that the 2010 Flash Crash was preceded by hours of VPIN > 0.7.

**Implementation:** `CMqtVPIN::ToxicityZScore(lookback)`, `::IsToxic(lookback, threshold)`.

---

## 5. Kyle's Lambda

### 5.1 Concept

Kyle's lambda ($\lambda$) measures the **price impact per unit of signed order flow**. It is the slope of the regression:

$$
\Delta P = \alpha + \lambda \times Q_{\text{signed}} + \varepsilon
$$

where:
- $\Delta P = \ln(P_t / P_{t-1})$ is the log-return
- $Q_{\text{signed}}$ is the signed volume (+ for buys, - for sells)
- $\lambda$ is the price impact coefficient (Kyle's lambda)

A high $\lambda$ means the market is illiquid — a given order causes a large price move.

### 5.2 OLS Estimation

The regression is estimated via ordinary least squares over a rolling window of $n$ observations:

$$
\lambda = \frac{\sum (x_i - \bar{x})(y_i - \bar{y})}{\sum (x_i - \bar{x})^2}
$$

where: $x_i = Q_{\text{signed}}[i]$, $y_i = \Delta P[i]$

The $R^2$ measures how much of the price variance is explained by order flow:

$$
R^2 = 1 - \frac{SS_{\text{res}}}{SS_{\text{tot}}}
$$

### 5.3 Throttling

Since OLS is O(n) per tick and callable at tick frequency, the regression is recomputed only every $k$ ticks (default: 5). Between recomputations, the last $\lambda$ is returned.

**Implementation:**
- `CMqtKyleLambda::Add(mid, signedVolume)` — add observation, trigger OLS every k ticks
- `CMqtKyleLambda::CurrentLambda()` — most recent estimate
- `CMqtKyleLambda::AverageLambda(window)` — smoothed lambda
- `CMqtKyleLambda::SetThrottle(n)` — set recompute frequency

---

## 6. Amihud Illiquidity

### 6.1 Definition

The Amihud illiquidity ratio is a non-parametric measure of price impact:

$$
\text{Amihud}_i = \frac{|R_i|}{V_i}
$$

where $R_i = \ln(P_i / P_{i-1})$ is the absolute log-return and $V_i$ is the dollar volume for bar $i$.

Higher values indicate **lower liquidity** — the same volume moves price more.

### 6.2 Interpretation

| Amihud | Liquidity | Typical for |
|--------|-----------|-------------|
| $< 1 \times 10^{-7}$ | Highly liquid | Major FX pairs |
| $1 \times 10^{-6}$ | Liquid | Large-cap equities |
| $1 \times 10^{-5}$ | Moderate | Small-cap equities |
| $> 1 \times 10^{-4}$ | Illiquid | Emerging market bonds |

**Implementation:** `CMqtAmihudIlliquidity::AddBar(prevPrice, currPrice, volume)`.

---

## 7. Hasbrouck's Impulse Response

### 7.1 Concept

Hasbrouck (1991) models the joint dynamics of price changes and trade signs using a vector autoregression (VAR):

$$
r_t = \alpha_1 \times r_{t-1} + \beta_1 \times x_{t-1} + \varepsilon_{1,t}
$$

$$
x_t = \alpha_2 \times r_{t-1} + \beta_2 \times x_{t-1} + \varepsilon_{2,t}
$$

where $r_t$ is the price change (log-return) and $x_t$ is the trade sign (+1 buy, -1 sell, 0 neutral).

### 7.2 Impulse Response

The impulse response function traces the effect of a one-unit trade sign shock on future price changes:

$$
\text{IRF}(k) = \frac{\partial E[r_{t+k} \mid x_t = 1]}{\partial x_t}
$$

The **permanent impact** is the cumulative impulse over all lags:

$$
\theta_{\text{perm}} = \frac{1}{L} \times \sum_{k=0}^{L-1} |\text{IRF}(k)|
$$

The **temporary impact** is the deviation of the first lag from the permanent:

$$
\theta_{\text{temp}} = |\text{IRF}(0) - \theta_{\text{perm}}|
$$

**Implementation:** `CMqtHasbrouckImpact::Add(priceChange, tradeSign)`, `::PermanentImpact()`, `::TemporaryImpact()`.

---

## 8. Almgren-Chriss Market Impact

### 8.1 Model

The Almgren-Chriss model separates impact into permanent and temporary components:

$$
I(Q) = \theta_{\text{perm}} \times \left(\frac{Q}{V}\right)^\alpha + \theta_{\text{temp}} \times \left(\frac{Q}{V}\right)^\gamma
$$

where:
- $Q$ is the order size
- $V$ is the total volume
- $\alpha \approx 0.3$ is the permanent impact exponent
- $\gamma \approx 0.6$ is the temporary impact exponent

### 8.2 Optimal Execution

The optimal trading rate that balances impact cost and timing risk:

$$
\eta^* = \sqrt{\frac{\lambda \times \sigma^2}{2 \times \theta_{\text{temp}} \times T}}
$$

where:
- $\lambda$ is risk aversion
- $\sigma^2$ is return variance
- $T$ is execution horizon in seconds

**Implementation:** `CMqtAlmgrenChriss::TotalImpact(orderSize, totalVol)`, `::OptimalTradingRate(riskAversion, totalVol, horizon)`.

---

## 9. Realised Volatility

### 9.1 Classic Realised Volatility

$$
\text{RV} = \sqrt{\sum r_i^2}
$$

where $r_i = \ln(P_i / P_{i-1})$ are log-returns over the window.

### 9.2 Parkinson Estimator

Uses only high and low prices (efficient when drift is zero):

$$
\sigma_{\text{Parkinson}} = \sqrt{\frac{1}{4 \times \ln 2 \times N} \times \sum \ln\left(\frac{H_i}{L_i}\right)^2}
$$

### 9.3 Garman-Klass Estimator

Uses open, high, low, close (drift-robust):

$$
\sigma_{\text{GK}} = \sqrt{\frac{1}{N} \times \sum \left[0.5 \times \ln\left(\frac{H_i}{L_i}\right)^2 - (2 \times \ln 2 - 1) \times \ln\left(\frac{C_i}{O_i}\right)^2\right]}
$$

### 9.4 Yang-Zhang Estimator

The most robust — handles drift and opening jumps:

$$
\sigma_{\text{YZ}}^2 = \sigma_{\text{overnight}}^2 + k \times \sigma_{\text{open-close}}^2 + (1-k) \times \sigma_{\text{RS}}^2
$$

where:

$$
\sigma_{\text{overnight}}^2 = \mathrm{Var}\left(\ln\left(\frac{O_i}{C_{i-1}}\right)\right)
$$

$$
\sigma_{\text{open-close}}^2 = \mathrm{Var}\left(\ln\left(\frac{C_i}{O_i}\right)\right)
$$

$$
\sigma_{\text{RS}}^2 = \sum \ln\left(\frac{H_i}{L_i}\right) \times \left(\ln\left(\frac{H_i}{L_i}\right) - \ln\left(\frac{C_i}{O_i}\right)\right)
$$

$$
k = \frac{0.34}{1 + \frac{N+1}{N-1}}
$$

**Implementation:**
- `CMqtRealizedVolatility::ComputeFromPrices(prices[], n)` — classic RV
- `::ComputeParkinson(high[], low[], n)` — Parkinson
- `::ComputeGarmanKlass(open, high, low, close, n)` — GK
- `::ComputeYangZhang(open, high, low, close, n)` — YZ

---

## 10. Microstructure Noise

### 10.1 Noise from Overlapping RV

Microstructure noise (bid-ask bounce, tick-size effects) inflates RV at high frequencies. A simple estimator uses the difference between RV at lag 1 and lag 2:

$$
\sigma_{\text{noise}}^2 = \frac{\text{RV}_1 - \frac{\text{RV}_2}{2}}{2}
$$

where $\text{RV}_k$ is realised vol computed at k-tick sampling.

### 10.2 Signal-to-Noise Ratio

$$
\text{SNR} = \frac{1}{\sigma_{\text{noise}}^2}
$$

High SNR means the observed price changes are mostly information, not noise.

**Implementation:** `CMqtMicrostructureNoise::EstimateFromReturns(returns[], n)`.

---

## 11. Volatility Signature Plot

### 11.1 Concept

The volatility signature plot shows RV computed at every sampling lag from 1 to L:

$$
\text{Signature}(\text{lag}) = \text{RV at } \text{lag} \text{ ticks per sample}
$$

At very high frequencies, RV is inflated by noise. As the lag increases, RV converges to the "true" volatility. The **optimal sampling frequency** is the smallest lag where the RV curve flattens.

### 11.2 Noise from Signature

$$
\sigma_{\text{noise}}^2 = \frac{\text{Signature}(1)^2 - \text{Signature}(2)^2}{2}
$$

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

$$
d_i = t_i - t_{i-1}
$$

in milliseconds, converted to seconds.

Key statistics:
- **Mean duration:** $\mu_d = \frac{1}{N} \times \sum d_i$
- **Std deviation:** $\sigma_d = \sqrt{\frac{1}{N-1} \times \sum (d_i - \mu_d)^2}$
- **Trade intensity:** $\lambda = \frac{1}{\mu_d}$ (trades per second)
- **Overdispersion:** $\sigma_d^2 / \mu_d$ — > 1 indicates clustering

**Implementation:** `CMqtTradeDuration::AddTrade(time_msc)`, `::AverageDuration()`, `::TradeIntensity()`, `::OverdispersionRatio()`.

### 13.2 Autoregressive Conditional Duration (ACD)

The ACD(1,1) model captures duration clustering:

$$
\psi_i = \omega + \alpha \times d_{i-1} + \beta \times \psi_{i-1}
$$

where $\psi_i$ is the conditional expected duration given past durations.

**Standardised residuals:** $\varepsilon_i = d_i / \psi_i$ should be i.i.d. with mean 1 if the model is correctly specified.

**MLE estimation** uses a grid search over $0 < \alpha, \beta < 1$ with $\alpha + \beta < 1$:

$$
\text{LL} = -\sum \left(\ln(\psi_i) + \frac{d_i}{\psi_i}\right)
$$

**Implementation:**
- `CMqtACDModel::Estimate(duration)` — on-line filtering
- `CMqtACDModel::EstimateMLE(durations[], n)` — grid-search calibration

---

## 14. Spread Decomposition

### 14.1 Huang-Stoll Model

The quoted spread is decomposed into three components:

$$
S_{\text{quoted}} = 2 \times (\text{AS} + \text{IC} + \text{OPC})
$$

where:
- AS = Adverse Selection component (informed trading cost)
- IC = Inventory component (holding cost)
- OPC = Order Processing component (fixed per-trade cost)

Effective spread:

$$
S_{\text{eff}} = 2 \times (\text{AS} + \text{OPC})
$$

Realised spread:

$$
S_{\text{rlz}} = 2 \times \text{OPC}
$$

From these, the components are:

$$
\text{AS} = \frac{S_{\text{eff}} - S_{\text{rlz}}}{2}
$$

$$
\text{OPC} = \frac{S_{\text{rlz}}}{2}
$$

$$
\text{IC} = \frac{S_{\text{quoted}} - 2 \times S_{\text{eff}}}{2} \quad (\text{if positive, else } 0)
$$

**Probability of Informed Trading (PIN):**

$$
\text{PIN} = \frac{\text{AS}}{\text{AS} + \text{OPC}}
$$

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

$$
R = \frac{1}{T_{\text{recovery}}}
$$

where $T_{\text{recovery}}$ is the time in milliseconds for the book depth to return to 95% of its pre-trade level.

### 16.2 Depth Elasticity

$$
\text{Elasticity} = \frac{\text{Depth}_{\text{pre-trade}}}{T_{\text{recovery}}}
$$

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

Volume is partitioned into $N$ equally-spaced price bins:

$$
\text{Bin}_k = [P_{\min} + k \times \Delta P,\ P_{\min} + (k+1) \times \Delta P)
$$

where $\Delta P = \frac{P_{\max} - P_{\min}}{N}$

### 17.2 Point of Control (POC)

The bin with the highest volume:

$$
\text{POC} = \arg\max_k V_k
$$

### 17.3 Value Area

The price range containing a specified percentage (typically 70%) of total volume. Starting from the POC, bins are added outward until the cumulative volume reaches the threshold:

$$
VA_{\text{low}} = P_{\min} + \mathrm{low\_bin} \times \Delta P
$$

$$
VA_{\text{high}} = P_{\min} + (\mathrm{high\_bin} + 1) \times \Delta P
$$

### 17.4 VWAP per Bin

$$
\text{VWAP}_k = \frac{\sum \text{price}_i \times \text{volume}_i}{V_k}
$$

for all trades in bin $k$.

### 17.5 Entropy

Normalised entropy measures how evenly volume is distributed across bins:

$$
H = -\frac{1}{\ln N} \times \sum p_k \times \ln(p_k)
$$

where $p_k = \frac{V_k}{V_{\text{total}}}$

$H \to 1$: volume evenly distributed (liquid market, no single fair price)  
$H \to 0$: all volume at one price (perfect agreement on fair value)

### 17.6 Skew

Volume-weighted skewness measures asymmetry:

$$
\text{Skew} = \frac{\frac{1}{V_{\text{total}}} \times \sum V_k \times (\text{mid}_k - \text{VWAP})^3}{\sigma^3}
$$

Positive skew = more volume at higher prices (bullish tail).

**Implementation:** `CMqtVolumeProfile::AddTrade(price, vol)`, `::POCPrice()`, `::ValueAreaLow(0.7)`, `::Entropy()`, `::Skew()`.

---

## 18. Hasbrouck Information Share

### 18.1 Concept

Information share measures the proportion of permanent price variance attributable to a given market or order flow source:

$$
\text{IS}_{\text{perm}} = \frac{\theta_{\text{perm}}}{\theta_{\text{perm}} + \theta_{\text{temp}}}
$$

where $\theta_{\text{perm}}$ is the permanent impact component and $\theta_{\text{temp}}$ is the temporary component from the VAR impulse response (Section 7).

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
