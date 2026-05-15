/** @file PriceImpact.mqh @brief Kyle's lambda, Amihud illiquidity, Hasbrouck impact, and Almgren-Chriss model. */

#include "DataTypes.mqh"

#ifndef MQT_PRICEIMPACT_MQH
#define MQT_PRICEIMPACT_MQH

/** Kyle's lambda — the regression slope of price change on signed order flow. */
class CMqtKyleLambda
{
private:
   double   m_last_output;
   double   m_lambda[];             /*!< Ring buffer of lambda estimates. */
   int      m_capacity;
   int      m_count;
   int      m_head;
   int      m_tail;
   int      m_window;              /*!< OLS regression window. */
   int      m_throttle;            /*!< Recompute only every N ticks. */
   int      m_skip_counter;
   double   m_order_flow_buffer[]; /*!< Rolling buffer of signed volumes. */
   double   m_price_change_buffer[]; /*!< Rolling buffer of log-returns. */
   int      m_buffer_size;
   int      m_buffer_count;
   double   m_prev_mid;

   int NextIndex(int idx) const { return (idx + 1) % m_capacity; }

   MqtRegressionResult RegressOLS(const double &x[], const double &y[], int n)
   {
      MqtRegressionResult result;
      if (n < 3)
         return result;

      double sum_x = 0, sum_y = 0, sum_xy = 0, sum_xx = 0;

      for (int i = 0; i < n; i++)
      {
         sum_x += x[i];
         sum_y += y[i];
         sum_xy += x[i] * y[i];
         sum_xx += x[i] * x[i];
      }

      double mean_x = sum_x / n;
      double mean_y = sum_y / n;

      double ss_xx = sum_xx - n * mean_x * mean_x;
      double ss_xy = sum_xy - n * mean_x * mean_y;

      if (MathAbs(ss_xx) < 1e-15)
         return result;

      result.beta = ss_xy / ss_xx;
      result.alpha = mean_y - result.beta * mean_x;

      double ss_res = 0;
      double ss_tot = 0;
      for (int i = 0; i < n; i++)
      {
         double resid = y[i] - (result.alpha + result.beta * x[i]);
         ss_res += resid * resid;
         double y_diff = y[i] - mean_y;
         ss_tot += y_diff * y_diff;
      }

      result.resid_variance = ss_res / (n - 2);
      result.beta_se = MathSqrt(result.resid_variance / ss_xx);
      result.alpha_se = MathSqrt(result.resid_variance * (1.0 / n + mean_x * mean_x / ss_xx));

      if (ss_tot > 0)
         result.r_squared = 1.0 - ss_res / ss_tot;
      result.observations = n;

      return result;
   }

public:
   /** @param capacity Ring-buffer capacity for lambda estimates (default: 500). */
   CMqtKyleLambda()
   {
      m_capacity = 500;
      m_count = 0;
      m_head = 0;
      m_tail = 0;
      m_window = 50;
      m_throttle = 5;
      m_skip_counter = 0;
      m_prev_mid = 0;
      m_buffer_size = 1000;
      m_buffer_count = 0;
      m_last_output = 0;
      ArrayResize(m_lambda, m_capacity);
      ArrayResize(m_order_flow_buffer, m_buffer_size);
      ArrayResize(m_price_change_buffer, m_buffer_size);
   }

   /** @param window OLS regression window in ticks. */
   void SetWindow(int window)
   {
      m_window = MathMax(10, window);
   }

   /** @param every_n_ticks Recompute lambda only every N ticks. */
   void SetThrottle(int every_n_ticks)
   {
      m_throttle = MathMax(1, every_n_ticks);
   }

   /** Feed a mid-price and signed volume update.
     *  @return true if a new lambda was computed this call. */
   bool Add(double mid_price, double signed_volume)
   {
      if (m_prev_mid > 0)
      {
         double price_change = MathLog(mid_price / m_prev_mid);

         if (m_buffer_count < m_buffer_size)
         {
            m_order_flow_buffer[m_buffer_count] = signed_volume;
            m_price_change_buffer[m_buffer_count] = price_change;
            m_buffer_count++;
         }
         else
         {
            for (int i = 1; i < m_buffer_size; i++)
            {
               m_order_flow_buffer[i - 1] = m_order_flow_buffer[i];
               m_price_change_buffer[i - 1] = m_price_change_buffer[i];
            }
            m_order_flow_buffer[m_buffer_size - 1] = signed_volume;
            m_price_change_buffer[m_buffer_size - 1] = price_change;
         }
      }

      m_prev_mid = mid_price;

      m_skip_counter++;
      if (m_skip_counter < m_throttle)
         return false;
      m_skip_counter = 0;

      if (m_buffer_count < m_window + 1)
         return false;

      int n = MathMin(m_window, m_buffer_count);
      double x[], y[];
      ArrayResize(x, n);
      ArrayResize(y, n);

      for (int i = 0; i < n; i++)
      {
         int idx = m_buffer_count - n + i;
         x[i] = m_order_flow_buffer[idx];
         y[i] = m_price_change_buffer[idx];
      }

      MqtRegressionResult reg = RegressOLS(x, y, n);

      if (m_count == m_capacity)
      {
         m_head = NextIndex(m_head);
         m_count--;
      }

      m_lambda[m_tail] = reg.beta;
      m_last_output = reg.beta;
      m_tail = NextIndex(m_tail);
      m_count++;

      return true;
   }

   /** Extract signed volume from a classified tick and feed it in.
     *  @return true if a new lambda was computed. */
   bool AddFromTick(const MqtTick &tick)
   {
      double signed_vol = 0;
      if (tick.direction == MQT_TICK_BUY)
         signed_vol = (double)tick.volume;
      else if (tick.direction == MQT_TICK_SELL)
         signed_vol = -(double)tick.volume;
      else
         return false;

      double mid = tick.MidPrice();
      if (mid <= 0)
         return false;

      return Add(mid, signed_vol);
   }

   /** @return Most recent lambda estimate. */
   double CurrentLambda() const
   {
      if (m_count == 0)
         return m_last_output;
      return m_lambda[(m_tail - 1 + m_capacity) % m_capacity];
   }

   /** @param lookback Number of estimates.
     *  @return Mean lambda over lookback. */
   double AverageLambda(int lookback = 50)
   {
      if (m_count == 0)
         return m_last_output;

      int n = MathMin(lookback, m_count);
      double sum = 0;

      for (int i = 0; i < n; i++)
      {
         int idx = (m_tail - 1 - i + m_capacity) % m_capacity;
         sum += m_lambda[idx];
      }

      return sum / n;
   }

   /** @param lookback Number of estimates.
     *  @return Sample standard deviation of lambda over lookback. */
   double LambdaStd(int lookback = 50)
   {
      if (m_count < 2)
         return 0;

      int n = MathMin(lookback, m_count);
      double mean = AverageLambda(n);
      double sum_sq = 0;

      for (int i = 0; i < n; i++)
      {
         int idx = (m_tail - 1 - i + m_capacity) % m_capacity;
         double diff = m_lambda[idx] - mean;
         sum_sq += diff * diff;
      }

      return MathSqrt(sum_sq / (n - 1));
   }

   /** @param order_size Trade size.
     *  @return Estimated market-impact cost = lambda * order_size. */
   double MarketImpactCost(double order_size)
   {
      return CurrentLambda() * order_size;
   }

   int Count() const { return m_count; }

   /** Clear all data. */
   void Reset()
   {
      m_count = 0;
      m_head = 0;
      m_tail = 0;
      m_buffer_count = 0;
      m_prev_mid = 0;
      m_last_output = 0;
      m_skip_counter = 0;
   }
};

/** Amihud illiquidity ratio — |return| / dollar-volume per bar. */
class CMqtAmihudIlliquidity
{
private:
   double   m_illiq[];  /*!< Ring buffer of per-bar Amihud ratios. */
   int      m_capacity;
   int      m_count;
   int      m_head;
   int      m_tail;
   int      m_skip_counter;

   int NextIndex(int idx) const { return (idx + 1) % m_capacity; }

public:
   /** @param capacity Ring-buffer capacity (default: 500). */
   CMqtAmihudIlliquidity()
   {
      m_capacity = 500;
      m_count = 0;
      m_head = 0;
      m_tail = 0;
      m_skip_counter = 0;
      ArrayResize(m_illiq, m_capacity);
   }

   /** Feed a bar's open/close prices and volume.
     *  @param price_prev Previous bar close.
     *  @param price_curr Current bar close.
     *  @param volume     Bar volume.
     *  @param price_adj  Adjustment price (e.g. dividend-adjusted close).
     *  @return true on success. */
   bool AddBar(double price_prev, double price_curr, double volume, double price_adj = 0)
   {
      if (price_prev <= 0 || volume <= 0)
         return false;

      double ret = 0;
      if (price_adj > 0 && price_adj != price_prev)
         ret = MathAbs(MathLog(price_curr / price_adj));
      else
         ret = MathAbs(MathLog(price_curr / price_prev));

      double amihud = ret / volume;

      if (m_count == m_capacity)
      {
         m_head = NextIndex(m_head);
         m_count--;
      }

      m_illiq[m_tail] = amihud;
      m_tail = NextIndex(m_tail);
      m_count++;

      return true;
   }

   /** @return Most recent bar's illiquidity. */
   double CurrentIlliquidity() const
   {
      if (m_count == 0)
         return 0;
      return m_illiq[(m_tail - 1 + m_capacity) % m_capacity];
   }

   /** @param lookback Number of bars.
     *  @return Mean illiquidity over lookback. */
   double AverageIlliquidity(int lookback = 100)
   {
      if (m_count == 0)
         return 0;

      int n = MathMin(lookback, m_count);
      double sum = 0;

      for (int i = 0; i < n; i++)
      {
         int idx = (m_tail - 1 - i + m_capacity) % m_capacity;
         sum += m_illiq[idx];
      }

      return sum / n;
   }

   /** @param lookback Number of bars.
     *  @return Median illiquidity over lookback. */
   double MedianIlliquidity(int lookback = 100)
   {
      if (m_count == 0)
         return 0;

      int n = MathMin(lookback, m_count);
      double temp[];
      ArrayResize(temp, n);

      for (int i = 0; i < n; i++)
      {
         int idx = (m_tail - 1 - i + m_capacity) % m_capacity;
         temp[i] = m_illiq[idx];
      }

      ArraySort(temp);

      if (n % 2 == 1)
         return temp[n / 2];
      else
         return (temp[n / 2 - 1] + temp[n / 2]) * 0.5;
   }

   /** @param lookback Number of bars.
     *  @return Interquartile range of illiquidity over lookback. */
   double IQRSpread(int lookback = 100)
   {
      if (m_count == 0)
         return 0;

      int n = MathMin(lookback, m_count);
      double temp[];
      ArrayResize(temp, n);

      for (int i = 0; i < n; i++)
      {
         int idx = (m_tail - 1 - i + m_capacity) % m_capacity;
         temp[i] = m_illiq[idx];
      }

      ArraySort(temp);

      int q1_idx = n / 4;
      int q3_idx = 3 * n / 4;

      return temp[q3_idx] - temp[q1_idx];
   }

   int Count() const { return m_count; }

   /** Clear all data. */
   void Reset()
   {
      m_count = 0;
      m_head = 0;
      m_tail = 0;
      m_skip_counter = 0;
   }
};

/** Hasbrouck-style impulse response: permanent vs temporary price impact from trade signs. */
class CMqtHasbrouckImpact
{
private:
   double   m_impulse_response[]; /*!< Impact coefficients per lag. */
   double   m_price_innovation[]; /*!< Innovation at each lag. */
   int      m_lags;
   int      m_capacity;
   int      m_count;
   double   m_price_changes[];    /*!< Rolling buffer of log-returns. */
   double   m_trade_signs[];      /*!< Rolling buffer of signed trade indicators. */
   int      m_buffer_size;
   int      m_buffer_pos;
   double   m_permanent_impact;
   double   m_temporary_impact;
   int      m_throttle;
   int      m_skip_counter;

   double ComputeInnovation(const double &changes[], const double &signs[],
                            int n, int lag)
   {
      if (n < lag + 5)
         return 0;

      double x[100], y[100];
      int m = MathMin(n - lag - 1, 100);

      for (int i = 0; i < m; i++)
      {
         x[i] = signs[lag + i];
         y[i] = changes[lag + i + 1];
      }

      double sum_x = 0, sum_y = 0, sum_xy = 0, sum_xx = 0;
      for (int i = 0; i < m; i++)
      {
         sum_x += x[i];
         sum_y += y[i];
         sum_xy += x[i] * y[i];
         sum_xx += x[i] * x[i];
      }

      double mean_x = sum_x / m;
      double ss_xx = sum_xx - m * mean_x * mean_x;

      if (MathAbs(ss_xx) < 1e-15)
         return 0;

      return (sum_xy - m * mean_x * (sum_y / m)) / ss_xx;
   }

public:
   /** @param lags Number of lags for the impulse response (default: 10). */
   CMqtHasbrouckImpact()
   {
      m_lags = 10;
      m_capacity = 200;
      m_count = 0;
      m_buffer_size = 5000;
      m_buffer_pos = 0;
      m_permanent_impact = 0;
      m_temporary_impact = 0;
      m_throttle = 3;
      m_skip_counter = 0;
      ArrayResize(m_impulse_response, m_lags);
      ArrayResize(m_price_innovation, m_lags);
      ArrayResize(m_price_changes, m_buffer_size);
      ArrayResize(m_trade_signs, m_buffer_size);
   }

   /** @param every_n_events Recompute only every N events. */
   void SetThrottle(int every_n_events)
   {
      m_throttle = MathMax(1, every_n_events);
   }

   /** Feed a price change and matching trade sign.
     *  @return true if impulse response was recomputed. */
   bool Add(double price_change, double trade_sign)
   {
      if (m_buffer_pos < m_buffer_size)
      {
         m_price_changes[m_buffer_pos] = price_change;
         m_trade_signs[m_buffer_pos] = trade_sign;
         m_buffer_pos++;
      }
      else
      {
         for (int i = 1; i < m_buffer_size; i++)
         {
            m_price_changes[i - 1] = m_price_changes[i];
            m_trade_signs[i - 1] = m_trade_signs[i];
         }
         m_price_changes[m_buffer_size - 1] = price_change;
         m_trade_signs[m_buffer_size - 1] = trade_sign;
      }

      if (m_buffer_pos <= m_lags + 10)
         return false;

      m_skip_counter++;
      if (m_skip_counter < m_throttle)
         return false;
      m_skip_counter = 0;

      for (int lag = 0; lag < m_lags; lag++)
      {
         m_price_innovation[lag] = ComputeInnovation(
            m_price_changes, m_trade_signs, m_buffer_pos, lag);
      }

      double cum_impact = 0;
      for (int lag = 0; lag < m_lags; lag++)
      {
         m_impulse_response[lag] = m_price_innovation[lag];
         cum_impact += m_price_innovation[lag];
      }

      m_permanent_impact = cum_impact / m_lags;
      m_temporary_impact = m_price_innovation[0] - m_permanent_impact;
      m_count++;

      return true;
   }

   /** Feed a sequence of mid-prices and trade signs.
     *  @return true if at least one impulse response was computed. */
   bool AddFromMidPrices(const double &mid_prices[], const int &trade_signs[], int n)
   {
      int added = 0;
      for (int i = 1; i < n; i++)
      {
         double ret = MathLog(mid_prices[i] / mid_prices[i - 1]);
         if (Add(ret, (double)trade_signs[i]))
            added++;
      }
      return added > 0;
   }

   double PermanentImpact() const { return m_permanent_impact; }
   double TemporaryImpact() const { return m_temporary_impact; }

   /** @param lag Lag index.
     *  @return Impulse-response coefficient at that lag. */
   double ImpactAtLag(int lag) const
   {
      if (lag >= 0 && lag < m_lags)
         return m_impulse_response[lag];
      return 0;
   }

   /** @param lag Number of lags to cumulate.
     *  @return Cumulative impulse response up to (and including) lag. */
   double CumulativeImpact(int lag) const
   {
      double cum = 0;
      int n = MathMin(lag + 1, m_lags);
      for (int i = 0; i < n; i++)
         cum += m_impulse_response[i];
      return cum;
   }

   /** @return Permanent impact as a fraction of total impact. */
   double InformationShare() const
   {
      double total = MathAbs(m_permanent_impact) + MathAbs(m_temporary_impact);
      return (total > 0) ? MathAbs(m_permanent_impact) / total : 0;
   }

   int Count() const { return m_count; }

   /** Clear all data. */
   void Reset()
   {
      m_count = 0;
      m_buffer_pos = 0;
      m_permanent_impact = 0;
      m_temporary_impact = 0;
      m_skip_counter = 0;
      ArrayInitialize(m_impulse_response, 0);
      ArrayInitialize(m_price_innovation, 0);
   }
};

/** Almgren-Chriss market-impact model with optimal execution. */
class CMqtAlmgrenChriss
{
private:
   double   m_permanent_impact_coeff;
   double   m_temporary_impact_coeff;
   double   m_volatility;
   double   m_alpha;   /*!< Shape parameter for permanent impact. */
   double   m_gamma;   /*!< Shape parameter for temporary impact. */

public:
   /** Default coefficients (can be calibrated via CalibrateFromKyle). */
   CMqtAlmgrenChriss()
   {
      m_permanent_impact_coeff = 0.01;
      m_temporary_impact_coeff = 0.005;
      m_volatility = 0.02;
      m_alpha = 0.3;
      m_gamma = 0.6;
   }

   /** @param perm_coeff Permanent impact coefficient.
     *  @param temp_coeff Temporary impact coefficient.
     *  @param vol        Annualised volatility.
     *  @param alpha      Permanent-impact curvature.
     *  @param gamma      Temporary-impact curvature. */
   void SetParameters(double perm_coeff, double temp_coeff, double vol,
                      double alpha = 0.3, double gamma = 0.6)
   {
      m_permanent_impact_coeff = perm_coeff;
      m_temporary_impact_coeff = temp_coeff;
      m_volatility = vol;
      m_alpha = alpha;
      m_gamma = gamma;
   }

   /** Calibrate permanent/temporary coefficients from a Kyle lambda estimate.
     *  @param kyle  Kyle's lambda instance.
     *  @param spread Average quoted spread.
     *  @param vol    Volatility estimate. */
   void CalibrateFromKyle(CMqtKyleLambda *kyle, double spread, double vol)
   {
      double lam = kyle.AverageLambda(100);
      m_permanent_impact_coeff = lam * 0.5;
      m_temporary_impact_coeff = spread * 0.25;
      m_volatility = vol;
   }

   /** @return Permanent price impact as a fraction of price. */
   double PermanentImpact(double order_size, double total_volume)
   {
      return m_permanent_impact_coeff * MathPow(order_size / total_volume, m_alpha);
   }

   /** @return Temporary price impact as a fraction of price. */
   double TemporaryImpact(double order_size, double total_volume)
   {
      return m_temporary_impact_coeff * MathPow(order_size / total_volume, m_gamma);
   }

   /** @return Permanent + temporary impact. */
   double TotalImpact(double order_size, double total_volume)
   {
      return PermanentImpact(order_size, total_volume) +
             TemporaryImpact(order_size, total_volume);
   }

   /** @return Optimal trading rate (shares per unit time) given risk aversion. */
   double OptimalTradingRate(double risk_aversion, double total_volume, double time_horizon)
   {
      double eta = m_temporary_impact_coeff;
      double sigma = m_volatility;
      double t = time_horizon;

      if (eta <= 0 || sigma <= 0 || t <= 0)
         return 1.0 / t;

      double lambda = risk_aversion;
      double numerator = MathSqrt(lambda * sigma * sigma / (2.0 * eta));
      double denominator = MathSqrt(t);

      return numerator / denominator;
   }

   /** @return Total cost (trading + risk) for an efficient-frontier execution. */
   double EfficientFrontierCost(double order_size, double risk_aversion,
                                 double total_volume, double time_horizon)
   {
      double perm = PermanentImpact(order_size, total_volume);
      double temp = TemporaryImpact(order_size, total_volume);
      double rate = OptimalTradingRate(risk_aversion, total_volume, time_horizon);

      double trading_cost = perm * order_size + temp * order_size * rate * time_horizon;
      double risk_cost = risk_aversion * m_volatility * m_volatility * order_size * order_size / (2.0 * time_horizon);

      return trading_cost + risk_cost;
   }
};

#endif
