/** @file DurationAnalysis.mqh @brief Trade duration, ACD model, intensity estimation, and diurnal adjustment. */

#include "DataTypes.mqh"

#ifndef MQT_DURATION_ANALYSIS_MQH
#define MQT_DURATION_ANALYSIS_MQH

/** Tracks inter-trade durations and provides descriptive statistics. */
class CMqtTradeDuration
{
private:
   long      m_last_trade_msc;
   double    m_durations[]; /*!< Ring buffer of inter-trade durations (seconds). */
   int       m_capacity;
   int       m_count;
   int       m_head;
   int       m_tail;
   double    m_last_duration;

   int NextIndex(int idx) const { return (idx + 1) % m_capacity; }

public:
   /** @param capacity Ring-buffer capacity (default: 10000). */
   CMqtTradeDuration()
   {
      m_last_trade_msc = 0;
      m_capacity = 10000;
      m_count = 0;
      m_head = 0;
      m_tail = 0;
      m_last_duration = 0;
      ArrayResize(m_durations, m_capacity);
   }

   /** Feed a trade timestamp and compute the duration since the last trade.
     *  @return true on success. */
   bool AddTrade(long time_msc)
   {
      if (time_msc == 0)
         return false;

      if (m_last_trade_msc > 0)
      {
         double duration = (double)(time_msc - m_last_trade_msc) / 1000.0;

         if (duration < 0)
         {
            m_last_trade_msc = time_msc;
            return false;
         }

         if (duration == 0)
            duration = 0.001;

         if (m_count == m_capacity)
         {
            m_head = NextIndex(m_head);
            m_count--;
         }

         m_durations[m_tail] = duration;
         m_tail = NextIndex(m_tail);
         m_count++;
         m_last_duration = duration;
      }

      m_last_trade_msc = time_msc;
      return true;
   }

   /** @return Most recent inter-trade duration. */
   double CurrentDuration() const { return m_last_duration; }

   /** @param lookback Number of observations.
     *  @return Mean duration over lookback. */
   double AverageDuration(int lookback = 100)
   {
      if (m_count == 0)
         return 0;

      int n = MathMin(lookback, m_count);
      double sum = 0;

      for (int i = 0; i < n; i++)
      {
         int idx = (m_tail - 1 - i + m_capacity) % m_capacity;
         sum += m_durations[idx];
      }

      return sum / n;
   }

   /** @param lookback Number of observations.
     *  @return Median duration over lookback. */
   double MedianDuration(int lookback = 100)
   {
      if (m_count == 0)
         return 0;

      int n = MathMin(lookback, m_count);
      double temp[];
      ArrayResize(temp, n);

      for (int i = 0; i < n; i++)
      {
         int idx = (m_tail - 1 - i + m_capacity) % m_capacity;
         temp[i] = m_durations[idx];
      }

      ArraySort(temp);

      if (n % 2 == 1)
         return temp[n / 2];
      else
         return (temp[n / 2 - 1] + temp[n / 2]) * 0.5;
   }

   /** @param lookback Number of observations.
     *  @return Sample standard deviation of durations. */
   double DurationStd(int lookback = 100)
   {
      if (m_count < 2)
         return 0;

      int n = MathMin(lookback, m_count);
      double mean = AverageDuration(n);
      double sum_sq = 0;

      for (int i = 0; i < n; i++)
      {
         int idx = (m_tail - 1 - i + m_capacity) % m_capacity;
         double diff = m_durations[idx] - mean;
         sum_sq += diff * diff;
      }

      return MathSqrt(sum_sq / (n - 1));
   }

   /** @param lookback Number of observations.
     *  @return Trade intensity (trades/second). */
   double TradeIntensity(int lookback = 100)
   {
      double avg_dur = AverageDuration(lookback);
      if (avg_dur > 0)
         return 1.0 / avg_dur;
      return 0;
   }

   /** @param lag      Autocorrelation lag.
     *  @param lookback Number of observations.
     *  @return Autocorrelation coefficient at given lag. */
   double DurationAutocorr(int lag = 1, int lookback = 500)
   {
      if (m_count < lag + 5)
         return 0;

      int n = MathMin(lookback, m_count);
      double x[], y[];
      ArrayResize(x, n - lag);
      ArrayResize(y, n - lag);

      int valid = 0;
      for (int i = 0; i < n - lag; i++)
      {
         int idx_i = (m_tail - n + i + m_capacity) % m_capacity;
         int idx_j = (m_tail - n + i + lag + m_capacity) % m_capacity;
         x[valid] = m_durations[idx_i];
         y[valid] = m_durations[idx_j];
         valid++;
      }

      if (valid < 5)
         return 0;

      double mean_x = 0, mean_y = 0;
      for (int i = 0; i < valid; i++)
      {
         mean_x += x[i];
         mean_y += y[i];
      }
      mean_x /= valid;
      mean_y /= valid;

      double cov = 0, var_x = 0, var_y = 0;
      for (int i = 0; i < valid; i++)
      {
         cov += (x[i] - mean_x) * (y[i] - mean_y);
         var_x += (x[i] - mean_x) * (x[i] - mean_x);
         var_y += (y[i] - mean_y) * (y[i] - mean_y);
      }

      double denom = MathSqrt(var_x * var_y);
      if (denom > 0)
         return cov / denom;

      return 0;
   }

   /** @param lookback Number of observations.
     *  @return Overdispersion ratio (variance / mean). */
   double OverdispersionRatio(int lookback = 100)
   {
      double mean = AverageDuration(lookback);
      double variance = DurationStd(lookback);
      variance = variance * variance;

      if (mean > 0)
         return variance / mean;
      return 0;
   }

   int Count() const { return m_count; }

   /** Clear all data. */
   void Reset()
   {
      m_count = 0;
      m_head = 0;
      m_tail = 0;
      m_last_trade_msc = 0;
      m_last_duration = 0;
   }
};

/** Autoregressive Conditional Duration (ACD) model. */
class CMqtACDModel
{
private:
   double   m_omega;
   double   m_alpha;
   double   m_beta;
   double   m_expected_durations[]; /*!< Ring buffer of conditional expected durations. */
   double   m_residuals[];          /*!< Ring buffer of residuals (dur / expected). */
   int      m_capacity;
   int      m_count;
   int      m_head;
   int      m_tail;
   double   m_last_expected;
   bool     m_initialized;

   int NextIndex(int idx) const { return (idx + 1) % m_capacity; }

public:
   /** Default parameters: omega=0.1, alpha=0.2, beta=0.7. */
   CMqtACDModel()
   {
      m_omega = 0.1;
      m_alpha = 0.2;
      m_beta = 0.7;
      m_capacity = 10000;
      m_count = 0;
      m_head = 0;
      m_tail = 0;
      m_last_expected = 1.0;
      m_initialized = false;
      ArrayResize(m_expected_durations, m_capacity);
      ArrayResize(m_residuals, m_capacity);
   }

   /** @param omega Constant term (>0).
     *  @param alpha Lag-duration coefficient (>0).
     *  @param beta  Lag-expected coefficient (>0, alpha+beta < 1). */
   void SetParameters(double omega, double alpha, double beta)
   {
      if (omega > 0 && alpha > 0 && beta > 0 && (alpha + beta) < 1)
      {
         m_omega = omega;
         m_alpha = alpha;
         m_beta = beta;
         m_initialized = false;
      }
   }

   /** Feed a duration and return the conditional expected duration.
     *  @return Expected duration. */
   double Estimate(double duration)
   {
      if (!m_initialized)
      {
         m_last_expected = duration;
         m_initialized = true;
      }
      else
      {
         m_last_expected = m_omega + m_alpha * duration + m_beta * m_last_expected;
      }

      if (m_count == m_capacity)
      {
         m_head = NextIndex(m_head);
         m_count--;
      }

      m_expected_durations[m_tail] = m_last_expected;

      double resid = 0;
      if (m_last_expected > 0)
         resid = duration / m_last_expected;
      m_residuals[m_tail] = resid;

      m_tail = NextIndex(m_tail);
      m_count++;

      return m_last_expected;
   }

   /** @return Latest expected duration. */
   double ExpectedDuration() const { return m_last_expected; }

   /** @param duration Current observed duration.
     *  @return Intensity (1 / expected duration). */
   double Intensity(double duration)
   {
      double exp_dur = ExpectedDuration();
      if (exp_dur > 0)
         return 1.0 / exp_dur;
      return 0;
   }

   /** @param lag      Autocorrelation lag.
     *  @param lookback Number of observations.
     *  @return Autocorrelation of model residuals. */
   double ResidualAutocorr(int lag = 1, int lookback = 500)
   {
      if (m_count < lag + 5)
         return 0;

      int n = MathMin(lookback, m_count);
      double x[], y[];
      ArrayResize(x, n - lag);
      ArrayResize(y, n - lag);

      for (int i = 0; i < n - lag; i++)
      {
         int idx_i = (m_tail - n + i + m_capacity) % m_capacity;
         int idx_j = (m_tail - n + i + lag + m_capacity) % m_capacity;
         x[i] = m_residuals[idx_i];
         y[i] = m_residuals[idx_j];
      }

      double mean_x = 0, mean_y = 0;
      for (int i = 0; i < n - lag; i++)
      {
         mean_x += x[i];
         mean_y += y[i];
      }
      mean_x /= (n - lag);
      mean_y /= (n - lag);

      double cov = 0, var_x = 0, var_y = 0;
      for (int i = 0; i < n - lag; i++)
      {
         cov += (x[i] - mean_x) * (y[i] - mean_y);
         var_x += (x[i] - mean_x) * (x[i] - mean_x);
         var_y += (y[i] - mean_y) * (y[i] - mean_y);
      }

      double denom = MathSqrt(var_x * var_y);
      if (denom > 0)
         return cov / denom;

      return 0;
   }

   /** Compute log-likelihood of observed durations under current parameters.
     *  @return Log-likelihood (or -999999 on failure). */
   double LogLikelihood(const double &durations[], int n)
   {
      if (n < 3)
         return -999999;

      CMqtACDModel temp;
      temp.SetParameters(m_omega, m_alpha, m_beta);

      double ll = 0;
      int valid = 0;

      for (int i = 0; i < n; i++)
      {
         if (durations[i] > 0)
         {
            double psi = temp.Estimate(durations[i]);
            if (psi > 0)
            {
               ll += -MathLog(psi) - durations[i] / psi;
               valid++;
            }
         }
      }

      return (valid > 2) ? ll : -999999;
   }

   /** Random-search MLE for ACD parameters.
     *  @return true if estimation completed. */
   bool EstimateMLE(const double &durations[], int n, int max_iter = 100)
   {
      if (n < 10)
         return false;

      double best_ll = -999999;
      double best_omega = 0.1, best_alpha = 0.2, best_beta = 0.7;

      for (int iter = 0; iter < max_iter; iter++)
      {
         double omega = 0.01 + (MathRand() / 32767.0) * 0.5;
         double alpha = 0.01 + (MathRand() / 32767.0) * 0.5;
         double beta  = 0.01 + (MathRand() / 32767.0) * 0.8;

         if (alpha + beta >= 1.0)
            continue;

         SetParameters(omega, alpha, beta);
         double ll = LogLikelihood(durations, n);

         if (ll > best_ll)
         {
            best_ll = ll;
            best_omega = omega;
            best_alpha = alpha;
            best_beta = beta;
         }
      }

      SetParameters(best_omega, best_alpha, best_beta);
      return true;
   }

   int Count() const { return m_count; }

   /** Clear all data. */
   void Reset()
   {
      m_count = 0;
      m_head = 0;
      m_tail = 0;
      m_last_expected = 1.0;
      m_initialized = false;
   }
};

/** Simple trade intensity estimator (trades per time interval). */
class CMqtIntensityEstimator
{
private:
   datetime  m_window_start;
   int       m_trade_count;
   double    m_intensity[]; /*!< Ring buffer of per-interval intensities. */
   int       m_capacity;
   int       m_count;
   int       m_head;
   int       m_tail;

   int NextIndex(int idx) const { return (idx + 1) % m_capacity; }

public:
   /** @param capacity Ring-buffer capacity (default: 500). */
   CMqtIntensityEstimator()
   {
      m_window_start = 0;
      m_trade_count = 0;
      m_capacity = 500;
      m_count = 0;
      m_head = 0;
      m_tail = 0;
      ArrayResize(m_intensity, m_capacity);
   }

   /** Record a trade occurrence. */
   void AddTrade(long time_msc)
   {
      m_trade_count++;
   }

   /** Compute intensity for the completed interval.
     *  @param interval_seconds Length of the observation interval.
     *  @return Trades/second. */
   double EstimateIntensity(int interval_seconds = 60)
   {
      if (interval_seconds <= 0)
         return 0;

      double intensity = (double)m_trade_count / (double)interval_seconds;

      if (m_count == m_capacity)
      {
         m_head = NextIndex(m_head);
         m_count--;
      }

      m_intensity[m_tail] = intensity;
      m_tail = NextIndex(m_tail);
      m_count++;

      m_trade_count = 0;

      return intensity;
   }

   /** @param lookback Number of intervals.
     *  @return Mean intensity over lookback. */
   double AverageIntensity(int lookback = 10)
   {
      if (m_count == 0)
         return 0;

      int n = MathMin(lookback, m_count);
      double sum = 0;

      for (int i = 0; i < n; i++)
      {
         int idx = (m_tail - 1 - i + m_capacity) % m_capacity;
         sum += m_intensity[idx];
      }

      return sum / n;
   }

   /** @param lookback Number of intervals.
     *  @return Z-score of the most recent intensity. */
   double IntensityZScore(int lookback = 10)
   {
      if (m_count < 2)
         return 0;

      int n = MathMin(lookback, m_count);
      double mean = AverageIntensity(n);
      double sum_sq = 0;

      for (int i = 0; i < n; i++)
      {
         int idx = (m_tail - 1 - i + m_capacity) % m_capacity;
         double diff = m_intensity[idx] - mean;
         sum_sq += diff * diff;
      }

      double std = MathSqrt(sum_sq / (n - 1));
      if (std > 0)
      {
         double current = m_intensity[(m_tail - 1 + m_capacity) % m_capacity];
         return (current - mean) / std;
      }

      return 0;
   }

   int Count() const { return m_count; }

   /** Clear all data. */
   void Reset()
   {
      m_count = 0;
      m_head = 0;
      m_tail = 0;
      m_trade_count = 0;
   }
};

/** Diurnal (intraday) pattern estimation and adjustment for trade durations. */
class CMqtDiurnalAdjustment
{
private:
   double   m_pattern[1440]; /*!< Seasonal factor per minute of day. */
   int      m_minute_bars;
   double   m_avg_duration;

public:
   CMqtDiurnalAdjustment()
   {
      m_minute_bars = 1440;
      m_avg_duration = 1;
      ArrayInitialize(m_pattern, 1.0);
   }

   /** Estimate the diurnal pattern from duration/time pairs.
     *  @return true if enough data was available. */
   bool EstimateFromDurations(double &durs[], datetime &times[], int n)
   {
      if (n < 100)
         return false;

      double minute_sum[1440];
      int minute_count[1440];
      ArrayInitialize(minute_sum, 0);
      ArrayInitialize(minute_count, 0);

      double total_dur_sum = 0;
      int total_dur_count = 0;

      for (int i = 0; i < n; i++)
      {
         if (durs[i] > 0)
         {
            MqlDateTime dt;
            TimeToStruct(times[i], dt);
            int minute_of_day = dt.hour * 60 + dt.min;

            if (minute_of_day >= 0 && minute_of_day < 1440)
            {
               minute_sum[minute_of_day] += durs[i];
               minute_count[minute_of_day]++;
            }

            total_dur_sum += durs[i];
            total_dur_count++;
         }
      }

      if (total_dur_count < 50)
         return false;

      m_avg_duration = total_dur_sum / total_dur_count;

      for (int i = 0; i < 1440; i++)
      {
         if (minute_count[i] > 0)
            m_pattern[i] = minute_sum[i] / minute_count[i] / m_avg_duration;
         else
            m_pattern[i] = 1.0;
      }

      SmoothPattern(5);
      return true;
   }

   /** Adjust a raw duration by the seasonal factor.
     *  @return Diurnally-adjusted duration. */
   double AdjustDuration(double raw_duration, datetime time)
   {
      MqlDateTime dt;
      TimeToStruct(time, dt);

      int minute_of_day = dt.hour * 60 + dt.min;

      if (minute_of_day < 0 || minute_of_day >= 1440)
         return raw_duration;

      double seasonal = m_pattern[minute_of_day];
      if (seasonal > 0)
         return raw_duration / seasonal;

      return raw_duration;
   }

   /** @return Seasonal factor for the given time. */
   double GetSeasonal(datetime time) const
   {
      MqlDateTime dt;
      TimeToStruct(time, dt);

      int minute_of_day = dt.hour * 60 + dt.min;
      if (minute_of_day >= 0 && minute_of_day < 1440)
         return m_pattern[minute_of_day];

      return 1.0;
   }

   /** Manually set the pattern for a specific minute. */
   void SetPattern(int minute, double value)
   {
      if (minute >= 0 && minute < 1440)
         m_pattern[minute] = MathMax(0.001, value);
   }

   /** Apply a moving-average smooth to the seasonal pattern. */
   void SmoothPattern(int window = 5)
   {
      double smoothed[1440];
      ArrayCopy(smoothed, m_pattern);

      for (int i = window; i < 1440 - window; i++)
      {
         double sum = 0;
         for (int j = -window; j <= window; j++)
            sum += m_pattern[i + j];
         smoothed[i] = sum / (2 * window + 1);
      }

      ArrayCopy(m_pattern, smoothed);
   }
};

#endif
