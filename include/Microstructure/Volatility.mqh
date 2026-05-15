/** @file Volatility.mqh @brief Realized volatility, microstructure noise estimation, and volatility signature. */

#include "Collectors.mqh"

#ifndef MQT_VOLATILITY_MQH
#define MQT_VOLATILITY_MQH

/** Realized volatility estimators: close-to-close, Parkinson, Garman-Klass, Yang-Zhang, subsampled. */
class CMqtRealizedVolatility
{
private:
   double   m_rv[];  /*!< Ring buffer of volatility estimates. */
   int      m_capacity;
   int      m_count;
   int      m_head;
   int      m_tail;
   int      m_sampling_freq;

   int NextIndex(int idx) const { return (idx + 1) % m_capacity; }

public:
   /** @param capacity Ring-buffer capacity (default: 500). */
   CMqtRealizedVolatility()
   {
      m_capacity = 500;
      m_count = 0;
      m_head = 0;
      m_tail = 0;
      m_sampling_freq = 1;
      ArrayResize(m_rv, m_capacity);
   }

   /** @param freq Sub-sampling interval (1 = every tick). */
   void SetSamplingFrequency(int freq)
   {
      m_sampling_freq = MathMax(1, freq);
   }

   /** Compute RV from pre-computed log-returns.
     *  @return Standard deviation of returns. */
   double ComputeFromReturns(const double &returns[], int n)
   {
      if (n < 2)
         return 0;

      double sum_sq = 0;
      for (int i = 0; i < n; i += m_sampling_freq)
      {
         sum_sq += returns[i] * returns[i];
      }

      double rv = MathSqrt(sum_sq);

      if (m_count == m_capacity)
      {
         m_head = NextIndex(m_head);
         m_count--;
      }

      m_rv[m_tail] = rv;
      m_tail = NextIndex(m_tail);
      m_count++;

      return rv;
   }

   /** Compute RV from a price series.
     *  @return Standard deviation of log-returns. */
   double ComputeFromPrices(const double &prices[], int n)
   {
      if (n < 2)
         return 0;

      double returns[];
      ArrayResize(returns, n - 1);

      for (int i = 1; i < n; i++)
      {
         if (prices[i - 1] > 0 && prices[i] > 0)
            returns[i - 1] = MathLog(prices[i] / prices[i - 1]);
         else
            returns[i - 1] = 0;
      }

      return ComputeFromReturns(returns, n - 1);
   }

   /** Compute RV from mid-prices in a tick collector.
     *  @return Standard deviation of mid-price returns. */
   double ComputeFromTickCollector(CMqtTickCollector *collector, int n_ticks = 100)
   {
      if (collector == NULL || collector.Count() < 2)
         return 0;

      int n = MathMin(n_ticks, collector.Count());
      double mid_prices[];
      ArrayResize(mid_prices, n);

      for (int i = 0; i < n; i++)
      {
         MqtTick tick;
         if (collector.GetAt(collector.Count() - n + i, tick))
            mid_prices[i] = tick.MidPrice();
         else
            mid_prices[i] = 0;
      }

      return ComputeFromPrices(mid_prices, n);
   }

   /** Compute RV from MqlRates close prices.
     *  @return Standard deviation of close-to-close returns. */
   double ComputeFromRates(const MqlRates &rates[], int n)
   {
      if (n < 2)
         return 0;

      double returns[];
      ArrayResize(returns, n);

      for (int i = 0; i < n; i++)
      {
         if (i == 0)
            returns[i] = 0;
         else if (rates[i - 1].close > 0 && rates[i].close > 0)
            returns[i] = MathLog(rates[i].close / rates[i - 1].close);
         else
            returns[i] = 0;
      }

      return ComputeFromReturns(returns, n);
   }

   /** @return Parkinson (high-low) volatility estimate. */
   double ComputeParkinson(const double &high[], const double &low[], int n)
   {
      if (n < 2)
         return 0;

      double sum = 0;
      int valid = 0;

      for (int i = 0; i < n; i++)
      {
         if (high[i] > 0 && low[i] > 0)
         {
            double hl_ratio = MathLog(high[i] / low[i]);
            sum += hl_ratio * hl_ratio;
            valid++;
         }
      }

      if (valid < 2)
         return 0;

      double rv = MathSqrt(sum / (4.0 * MathLog(2.0) * valid));

      if (m_count == m_capacity)
      {
         m_head = NextIndex(m_head);
         m_count--;
      }

      m_rv[m_tail] = rv;
      m_tail = NextIndex(m_tail);
      m_count++;

      return rv;
   }

   /** @return Garman-Klass volatility estimate (OHLC). */
   double ComputeGarmanKlass(const double &open[], const double &high[],
                              const double &low[], const double &close[], int n)
   {
      if (n < 2)
         return 0;

      double sum = 0;
      int valid = 0;

      for (int i = 0; i < n; i++)
      {
         if (open[i] > 0 && high[i] > 0 && low[i] > 0 && close[i] > 0)
         {
            double log_hl = MathLog(high[i] / low[i]);
            double log_co = MathLog(close[i] / open[i]);

            double term = 0.5 * log_hl * log_hl - (2.0 * MathLog(2.0) - 1.0) * log_co * log_co;
            sum += term;
            valid++;
         }
      }

      if (valid < 2)
         return 0;

      double rv = MathSqrt(sum / valid);

      if (m_count == m_capacity)
      {
         m_head = NextIndex(m_head);
         m_count--;
      }

      m_rv[m_tail] = rv;
      m_tail = NextIndex(m_tail);
      m_count++;

      return rv;
   }

   /** @return Yang-Zhang volatility estimate (OHLC with overnight drift). */
   double ComputeYangZhang(const double &open[], const double &high[],
                            const double &low[], const double &close[],
                            int n)
   {
      if (n < 4)
         return 0;

      double sum_overnight = 0;
      double sum_open_close = 0;
      double sum_rogers_satchell = 0;

      for (int i = 1; i < n; i++)
      {
         double overnight_ret = MathLog(open[i] / close[i - 1]);
         sum_overnight += overnight_ret * overnight_ret;

         double open_close_ret = MathLog(close[i] / open[i]);
         sum_open_close += open_close_ret * open_close_ret;

         double log_hl = MathLog(high[i] / low[i]);
         double log_co = MathLog(close[i] / open[i]);
         sum_rogers_satchell += log_hl * (log_hl - log_co);
      }

      double k = 0.34 / (1.0 + (double)(n + 1) / (double)(n - 1));
      double sigma_overnight = sum_overnight / (n - 1);
      double sigma_open_close = sum_open_close / (n - 1);
      double sigma_rs = sum_rogers_satchell / (n - 1);

      double rv = MathSqrt(sigma_overnight + k * sigma_open_close + (1.0 - k) * sigma_rs);

      if (m_count == m_capacity)
      {
         m_head = NextIndex(m_head);
         m_count--;
      }

      m_rv[m_tail] = rv;
      m_tail = NextIndex(m_tail);
      m_count++;

      return rv;
   }

   /** @return Subsampled RV averaged across offset grids (noise-robust). */
   double ComputeSubsampled(const double &prices[], int n, int subsample_step = 5)
   {
      if (n < subsample_step + 2)
         return 0;

      int samples = 0;
      double total_rv = 0;

      for (int offset = 0; offset < subsample_step; offset++)
      {
         double sum_sq = 0;
         int count = 0;

         for (int i = offset + subsample_step; i < n; i += subsample_step)
         {
            if (prices[i - subsample_step] > 0 && prices[i] > 0)
            {
               double ret = MathLog(prices[i] / prices[i - subsample_step]);
               sum_sq += ret * ret;
               count++;
            }
         }

         if (count > 1)
         {
            double rv_sub = sum_sq;
            total_rv += rv_sub;
            samples++;
         }
      }

      if (samples == 0)
         return 0;

      double rv = MathSqrt(total_rv / samples);

      if (m_count == m_capacity)
      {
         m_head = NextIndex(m_head);
         m_count--;
      }

      m_rv[m_tail] = rv;
      m_tail = NextIndex(m_tail);
      m_count++;

      return rv;
   }

   /** @return Most recent RV estimate. */
   double Current() const
   {
      if (m_count == 0)
         return 0;
      return m_rv[(m_tail - 1 + m_capacity) % m_capacity];
   }

   /** @param lookback Number of estimates.
     *  @return Mean RV over lookback. */
   double Average(int lookback = 50)
   {
      if (m_count == 0)
         return 0;

      int n = MathMin(lookback, m_count);
      double sum = 0;

      for (int i = 0; i < n; i++)
      {
         int idx = (m_tail - 1 - i + m_capacity) % m_capacity;
         sum += m_rv[idx];
      }

      return sum / n;
   }

   int Count() const { return m_count; }

   /** Clear all data. */
   void Reset()
   {
      m_count = 0;
      m_head = 0;
      m_tail = 0;
   }
};

/** Microstructure-noise variance estimation using the two-scale approach. */
class CMqtMicrostructureNoise
{
private:
   double m_noise_variance[];  /*!< Ring buffer of noise variance estimates. */
   double m_signal_variance[]; /*!< Ring buffer of signal variance estimates. */
   int    m_capacity;
   int    m_count;
   int    m_head;
   int    m_tail;

   int NextIndex(int idx) const { return (idx + 1) % m_capacity; }

public:
   /** @param capacity Ring-buffer capacity (default: 500). */
   CMqtMicrostructureNoise()
   {
      m_capacity = 500;
      m_count = 0;
      m_head = 0;
      m_tail = 0;
      ArrayResize(m_noise_variance, m_capacity);
      ArrayResize(m_signal_variance, m_capacity);
   }

   /** Estimate noise variance from log-returns using the two-scale method.
     *  @return Estimated noise variance. */
   double EstimateFromReturns(const double &returns[], int n)
   {
      if (n < 4)
         return 0;

      double rv_1 = 0;
      double rv_2 = 0;

      for (int i = 1; i < n; i++)
      {
         rv_1 += returns[i] * returns[i];
      }

      for (int i = 2; i < n; i++)
      {
         rv_2 += (returns[i] + returns[i - 1]) * (returns[i] + returns[i - 1]);
      }

      rv_1 /= (n - 1);
      rv_2 /= (n - 2);

      double noise_var = (rv_1 - rv_2 * 0.5) * 0.5;

      if (noise_var < 0)
         noise_var = 0;

      if (m_count == m_capacity)
      {
         m_head = NextIndex(m_head);
         m_count--;
      }

      m_noise_variance[m_tail] = noise_var;
      m_tail = NextIndex(m_tail);
      m_count++;

      return noise_var;
   }

   /** Estimate noise variance from a price series.
     *  @return Estimated noise variance. */
   double EstimateFromPrices(const double &prices[], int n)
   {
      if (n < 4)
         return 0;

      double returns[];
      ArrayResize(returns, n);

      for (int i = 1; i < n; i++)
      {
         if (prices[i - 1] > 0 && prices[i] > 0)
            returns[i] = MathLog(prices[i] / prices[i - 1]);
         else
            returns[i] = 0;
      }

      return EstimateFromReturns(returns, n);
   }

   /** Estimate noise variance from a quote series (mid-prices).
     *  @return Estimated noise variance. */
   double EstimateFromQuotes(const MqtQuote &quotes[], int n)
   {
      if (n < 4)
         return 0;

      double mid_returns[];
      ArrayResize(mid_returns, n);

      for (int i = 0; i < n; i++)
      {
         double mid = (quotes[i].bid + quotes[i].ask) * 0.5;
         if (i > 0)
         {
            double prev_mid = (quotes[i - 1].bid + quotes[i - 1].ask) * 0.5;
            if (prev_mid > 0 && mid > 0)
               mid_returns[i] = MathLog(mid / prev_mid);
            else
               mid_returns[i] = 0;
         }
         else
         {
            mid_returns[i] = 0;
         }
      }

      return EstimateFromReturns(mid_returns, n);
   }

   /** @return Most recent noise variance estimate. */
   double CurrentNoiseVariance() const
   {
      if (m_count == 0)
         return 0;
      return m_noise_variance[(m_tail - 1 + m_capacity) % m_capacity];
   }

   /** @return Signal-to-noise ratio based on average noise variance. */
   double SignalToNoiseRatio()
   {
      if (m_count == 0)
         return 0;

      double noise = CurrentNoiseVariance();
      if (noise <= 0)
         return 999.0;

      double total = 0;
      int lookback = MathMin(50, m_count);

      for (int i = 0; i < lookback; i++)
      {
         int idx = (m_tail - 1 - i + m_capacity) % m_capacity;
         total += m_noise_variance[idx];
      }

      double avg_noise = total / lookback;

      if (avg_noise <= 0)
         return 999.0;

      return 1.0 / avg_noise;
   }

   /** @param lookback Number of estimates.
     *  @return Noise variance / signal variance ratio. */
   double NoiseRatio(int lookback = 50)
   {
      if (m_count == 0)
         return 0;

      double noise_sum = 0;
      double sig_sum = 0;
      int n = MathMin(lookback, m_count);
      int valid = 0;

      for (int i = 0; i < n; i++)
      {
         int idx = (m_tail - 1 - i + m_capacity) % m_capacity;
         noise_sum += m_noise_variance[idx];
         sig_sum += m_signal_variance[idx];
         valid++;
      }

      if (valid > 0 && sig_sum > 0)
         return noise_sum / sig_sum;

      return 0;
   }

   int Count() const { return m_count; }

   /** Clear all data. */
   void Reset()
   {
      m_count = 0;
      m_head = 0;
      m_tail = 0;
   }
};

/** Volatility signature plot: RV computed at multiple sampling intervals. */
class CMqtVolatilitySignature
{
private:
   double   m_sig_vals[MQT_SIGNATURE_LAGS]; /*!< Volatility at each lag. */
   double   m_sig_lags[MQT_SIGNATURE_LAGS]; /*!< Lag values (sampling intervals). */
   int      m_max_lag;
   int      m_count;

public:
   CMqtVolatilitySignature()
   {
      m_max_lag = MQT_SIGNATURE_LAGS;
      m_count = 0;
      ArrayInitialize(m_sig_vals, 0);
      ArrayInitialize(m_sig_lags, 0);
   }

   /** Compute the signature plot from a price series.
     *  @return Number of lags computed. */
   int Compute(const double &prices[], int n)
   {
      if (n < 10)
         return 0;

      m_count = MathMin(m_max_lag, n / 2);

      for (int lag = 1; lag <= m_count; lag++)
      {
         double sum_sq = 0;
         int k = 0;

         for (int i = lag; i < n; i++)
         {
            double ret = MathLog(prices[i] / prices[i - lag]);
            sum_sq += ret * ret;
            k++;
         }

         if (k > 0)
         {
            m_sig_vals[lag - 1] = MathSqrt(sum_sq / k);
            m_sig_lags[lag - 1] = (double)lag;
         }
      }

      return m_count;
   }

   /** @param lag Sampling interval.
     *  @return Volatility at that lag. */
   double GetSignature(int lag) const
   {
      if (lag >= 1 && lag <= m_count)
         return m_sig_vals[lag - 1];
      return 0;
   }

   /** @param index Position in the signature array.
     *  @return Lag value at that position. */
   double GetLag(int index) const
   {
      if (index >= 0 && index < m_count)
         return m_sig_lags[index];
      return 0;
   }

   int Count() const { return m_count; }

   /** Estimate microstructure noise from the first two signature points.
     *  @return Noise variance estimate. */
   double EstimateNoiseFromSignature()
   {
      if (m_count < 3)
         return 0;

      double sig_1 = m_sig_vals[0];
      double sig_2 = m_sig_vals[1];

      if (sig_1 > 0 && sig_2 > 0)
      {
         double noise = (sig_1 * sig_1 - sig_2 * sig_2) * 0.5;
         return MathMax(0, noise);
      }

      return 0;
   }

   /** @return Lag where the signature curve flattens. */
   double OptimalSamplingFrequency()
   {
      if (m_count < 5)
         return 1;

      double prev_diff = MathAbs(m_sig_vals[0] - m_sig_vals[1]);

      for (int i = 2; i < m_count; i++)
      {
         double diff = MathAbs(m_sig_vals[i] - m_sig_vals[i - 1]);
         double ratio = diff / prev_diff;

         if (ratio < 0.1 && prev_diff > 0)
            return m_sig_lags[i];

         prev_diff = diff;
      }

      return m_sig_lags[m_count - 1];
   }

   /** Clear all data. */
   void Reset()
   {
      m_count = 0;
      ArrayInitialize(m_sig_vals, 0);
      ArrayInitialize(m_sig_lags, 0);
   }
};

#endif
