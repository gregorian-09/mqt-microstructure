/** @file OrderFlow.mqh @brief Cumulative volume delta, order-flow imbalance, VPIN, and flow toxicity. */

#include "DataTypes.mqh"

#ifndef MQT_ORDERFLOW_MQH
#define MQT_ORDERFLOW_MQH

/** Tracks cumulative volume delta (buy volume - sell volume) over a rolling window. */
class CMqtCumulativeVolumeDelta
{
private:
   double   m_cvd[];        /*!< Ring buffer of signed deltas. */
   double   m_cumulative;   /*!< Cumulative sum of all deltas. */
   int      m_capacity;
   int      m_count;
   int      m_head;
   int      m_tail;
   double   m_last_price;

   int NextIndex(int idx) const { return (idx + 1) % m_capacity; }

public:
   /** @param capacity Maximum number of deltas to store (default: 5000). */
   CMqtCumulativeVolumeDelta()
   {
      m_capacity = 5000;
      m_cumulative = 0;
      m_count = 0;
      m_head = 0;
      m_tail = 0;
      m_last_price = 0;
      ArrayResize(m_cvd, m_capacity);
   }

   /** @param capacity Maximum number of deltas to store. */
   CMqtCumulativeVolumeDelta(int capacity)
   {
      m_capacity = (capacity > 0) ? capacity : 5000;
      m_cumulative = 0;
      m_count = 0;
      m_head = 0;
      m_tail = 0;
      m_last_price = 0;
      ArrayResize(m_cvd, m_capacity);
   }

   /** Append a signed volume delta.
     *  @param price     Trade price.
     *  @param volume    Trade volume.
     *  @param direction Buy, sell, or unknown.
     *  @return true */
   bool Add(double price, ulong volume, ENUM_MQT_TICK_DIRECTION direction)
   {
      if (m_count == m_capacity)
      {
         m_cumulative -= m_cvd[m_head];
         m_head = NextIndex(m_head);
         m_count--;
      }

      double delta = 0;
      if (direction == MQT_TICK_BUY)
         delta = (double)volume;
      else if (direction == MQT_TICK_SELL)
         delta = -(double)volume;

      m_cumulative += delta;
      m_cvd[m_tail] = delta;
      m_tail = NextIndex(m_tail);
      m_count++;
      m_last_price = price;

      return true;
   }

   /** Extract delta from a classified MqtTick.
     *  @return true if the tick direction is known. */
   bool AddFromTick(const MqtTick &tick)
   {
      if (tick.direction == MQT_TICK_UNKNOWN || tick.volume == 0)
         return false;
      return Add(tick.last, tick.volume, tick.direction);
   }

   /** @return Cumulative delta since the last reset. */
   double Cumulative() const { return m_cumulative; }

   /** @param lookback Number of recent observations.
     *  @return Sum of deltas over lookback. */
   double Delta(int lookback = 100)
   {
      if (m_count == 0)
         return 0;

      double sum = 0;
      int n = MathMin(lookback, m_count);
      for (int i = 0; i < n; i++)
      {
         int idx = (m_tail - 1 - i + m_capacity) % m_capacity;
         sum += m_cvd[idx];
      }
      return sum;
   }

   /** @param lookback Number of recent observations.
     *  @return Sum of absolute deltas (total volume) over lookback. */
   double Volume(int lookback = 100)
   {
      if (m_count == 0)
         return 0;

      double sum = 0;
      int n = MathMin(lookback, m_count);
      for (int i = 0; i < n; i++)
      {
         int idx = (m_tail - 1 - i + m_capacity) % m_capacity;
         sum += MathAbs(m_cvd[idx]);
      }
      return sum;
   }

   /** @param lookback Number of recent observations.
     *  @return Delta / Volume ratio in [-1, 1]. */
   double DeltaRatio(int lookback = 100)
   {
      double d = Delta(lookback);
      double v = Volume(lookback);
      if (v > 0)
         return d / v;
      return 0;
   }

   /** @param lookback Number of recent observations.
     *  @return Z-score of the last delta relative to the lookback distribution. */
   double ZScore(int lookback = 100)
   {
      if (m_count < 2)
         return 0;

      int n = MathMin(lookback, m_count);
      double sum = 0;
      double sum_sq = 0;
      int valid = 0;

      for (int i = 0; i < n; i++)
      {
         int idx = (m_tail - 1 - i + m_capacity) % m_capacity;
         sum += m_cvd[idx];
         sum_sq += m_cvd[idx] * m_cvd[idx];
         valid++;
      }

      if (valid < 2)
         return 0;

      double mean = sum / valid;
      double variance = (sum_sq / valid) - (mean * mean);
      if (variance <= 0)
         return 0;

      double std = MathSqrt(variance);
      double last_delta = m_cvd[(m_tail - 1 + m_capacity) % m_capacity];
      return (last_delta - mean) / std;
   }

   /** Clear all stored deltas and reset cumulative. */
   void Reset()
   {
      m_count = 0;
      m_head = 0;
      m_tail = 0;
      m_cumulative = 0;
      m_last_price = 0;
   }
};

/** Tracks cumulative buy/sell volume and per-bar order-flow imbalance. */
class CMqtOrderFlowImbalance
{
private:
   double m_imbalance[];   /*!< Ring buffer of per-bar imbalance values. */
   int    m_capacity;
   int    m_count;
   int    m_head;
   int    m_tail;
   double m_buy_volume;
   double m_sell_volume;

   int NextIndex(int idx) const { return (idx + 1) % m_capacity; }

public:
   /** @param capacity Maximum number of bar imbalances to store (default: 5000). */
   CMqtOrderFlowImbalance()
   {
      m_capacity = 5000;
      m_count = 0;
      m_head = 0;
      m_tail = 0;
      m_buy_volume = 0;
      m_sell_volume = 0;
      ArrayResize(m_imbalance, m_capacity);
   }

   /** Clear all stored data. */
   void Reset()
   {
      m_count = 0;
      m_head = 0;
      m_tail = 0;
      m_buy_volume = 0;
      m_sell_volume = 0;
   }

   /** @return Current imbalance (buy - sell) / (buy + sell). */
   double CurrentImbalance() const
   {
      double total = m_buy_volume + m_sell_volume;
      if (total > 0)
         return (m_buy_volume - m_sell_volume) / total;
      return 0;
   }

   double BuyVolume() const { return m_buy_volume; }
   double SellVolume() const { return m_sell_volume; }

   /** @param volume Additional buy volume to accumulate. */
   void AddBuyVolume(double volume)
   {
      m_buy_volume += volume;
   }

   /** @param volume Additional sell volume to accumulate. */
   void AddSellVolume(double volume)
   {
      m_sell_volume += volume;
   }

   /** Append a bar-level imbalance and update cumulative volumes.
     *  @return true */
   bool AddBar(double buy_vol, double sell_vol)
   {
      if (m_count == m_capacity)
      {
         m_head = NextIndex(m_head);
         m_count--;
      }

      double total = buy_vol + sell_vol;
      double imb = 0;
      if (total > 0)
         imb = (buy_vol - sell_vol) / total;

      m_imbalance[m_tail] = imb;
      m_tail = NextIndex(m_tail);
      m_count++;

      m_buy_volume += buy_vol;
      m_sell_volume += sell_vol;

      return true;
   }

   /** @param lookback Number of bars.
     *  @return Mean imbalance over lookback. */
   double AverageImbalance(int lookback = 100)
   {
      if (m_count == 0)
         return 0;

      int n = MathMin(lookback, m_count);
      double sum = 0;

      for (int i = 0; i < n; i++)
      {
         int idx = (m_tail - 1 - i + m_capacity) % m_capacity;
         sum += m_imbalance[idx];
      }

      return sum / n;
   }

   /** @param lookback Number of bars.
     *  @return Sample standard deviation of imbalances over lookback. */
   double ImbalanceStd(int lookback = 100)
   {
      if (m_count < 2)
         return 0;

      int n = MathMin(lookback, m_count);
      double mean = AverageImbalance(n);
      double sum_sq = 0;

      for (int i = 0; i < n; i++)
      {
         int idx = (m_tail - 1 - i + m_capacity) % m_capacity;
         double diff = m_imbalance[idx] - mean;
         sum_sq += diff * diff;
      }

      return MathSqrt(sum_sq / (n - 1));
   }

   /** @param lookback Number of bars.
     *  @return Maximum absolute imbalance observed over lookback. */
   double ExtremeImbalance(int lookback = 100)
   {
      int n = MathMin(lookback, m_count);
      double max_imb = 0;

      for (int i = 0; i < n; i++)
      {
         int idx = (m_tail - 1 - i + m_capacity) % m_capacity;
         double abs_imb = MathAbs(m_imbalance[idx]);
         if (abs_imb > max_imb)
            max_imb = abs_imb;
      }

      return max_imb;
   }
};

/** Volume-synchronized Probability of Informed Trading (VPIN). */
class CMqtVPIN
{
private:
   double   m_vpin[];              /*!< Ring buffer of completed-bucket VPIN values. */
   int      m_capacity;
   int      m_count;
   int      m_head;
   int      m_tail;
   int      m_buckets;            /*!< Number of volume buckets per VPIN calculation. */
   double   m_bucket_volume;      /*!< Fixed volume per bucket. */
   double   m_buy_volume_bucket;  /*!< Buy volume in the current bucket. */
   double   m_sell_volume_bucket; /*!< Sell volume in the current bucket. */
   double   m_current_bucket_buy;
   double   m_current_bucket_sell;
   int      m_buckets_filled;

   int NextIndex(int idx) const { return (idx + 1) % m_capacity; }

public:
   /** @param capacity Maximum number of VPIN values to store (default: 1000). */
   CMqtVPIN()
   {
      m_capacity = 1000;
      m_count = 0;
      m_head = 0;
      m_tail = 0;
      m_buckets = MQT_PIN_BUCKETS;
      m_bucket_volume = 0;
      m_buy_volume_bucket = 0;
      m_sell_volume_bucket = 0;
      m_current_bucket_buy = 0;
      m_current_bucket_sell = 0;
      m_buckets_filled = 0;
      ArrayResize(m_vpin, m_capacity);
   }

   /** Initialise with a fixed bucket volume.
     *  @param bucket_volume Volume per bucket. */
   void Init(double bucket_volume)
   {
      m_bucket_volume = bucket_volume;
      m_current_bucket_buy = 0;
      m_current_bucket_sell = 0;
      m_buckets_filled = 0;
      m_count = 0;
      m_head = 0;
      m_tail = 0;
   }

   /** Derive bucket volume from average daily volume.
     *  @param symbol Instrument name.
     *  @param periods Number of daily bars to average.
     *  @param tf Timeframe for the bars. */
   void InitFromAverageVolume(string symbol, int periods = 20, ENUM_TIMEFRAMES tf = PERIOD_D1)
   {
      MqlRates rates[];
      int got = CopyRates(symbol, tf, 0, periods, rates);
      if (got > 0)
      {
         double avg_vol = 0;
         for (int i = 0; i < got; i++)
            avg_vol += MathAbs((double)rates[i].real_volume);
         avg_vol /= got;
         m_bucket_volume = avg_vol / (double)m_buckets;
      }
      else
      {
         m_bucket_volume = 1000;
      }

      if (m_bucket_volume < 1)
         m_bucket_volume = 1;

      m_current_bucket_buy = 0;
      m_current_bucket_sell = 0;
      m_buckets_filled = 0;
   }

   /** Derive bucket volume adaptively from recent tick data.
     *  @param symbol       Instrument name.
     *  @param sample_ticks Number of ticks to sample. */
   void InitAdaptive(string symbol, int sample_ticks = 5000)
   {
      MqlTick sample[];
      int got = CopyTicks(symbol, sample, COPY_TICKS_TRADE, 0, sample_ticks);
      if (got > 0)
      {
         double total_vol = 0;
         for (int i = 0; i < got; i++)
            total_vol += (double)sample[i].volume;
         double avg_tick_vol = total_vol / got;
         m_bucket_volume = MathMax(avg_tick_vol * m_buckets * 5, avg_tick_vol * 10);
      }
      else
      {
         m_bucket_volume = 5000;
      }

      m_current_bucket_buy = 0;
      m_current_bucket_sell = 0;
      m_buckets_filled = 0;
   }

   /** Feed a trade into the volume-bucket logic.
     *  @return true. */
   bool AddTrade(double price, ulong volume, ENUM_MQT_TICK_DIRECTION direction)
   {
      if (m_bucket_volume <= 0)
         return false;

      if (direction == MQT_TICK_BUY)
         m_current_bucket_buy += (double)volume;
      else if (direction == MQT_TICK_SELL)
         m_current_bucket_sell += (double)volume;
      else
      {
         double half = (double)volume * 0.5;
         m_current_bucket_buy += half;
         m_current_bucket_sell += half;
      }

      double bucket_total = m_current_bucket_buy + m_current_bucket_sell;
      while (bucket_total >= m_bucket_volume && m_bucket_volume > 0)
      {
         double excess = bucket_total - m_bucket_volume;
         double ratio = (m_bucket_volume - excess) / bucket_total;

         double buy_part = m_current_bucket_buy * ratio;
         double sell_part = m_current_bucket_sell * ratio;

         m_buy_volume_bucket += buy_part;
         m_sell_volume_bucket += sell_part;

         if (m_count == m_capacity)
         {
            m_head = NextIndex(m_head);
            m_count--;
         }

         m_vpin[m_tail] = VPINValue();
         m_tail = NextIndex(m_tail);
         m_count++;

         m_current_bucket_buy -= buy_part;
         m_current_bucket_sell -= sell_part;
         m_buy_volume_bucket = 0;
         m_sell_volume_bucket = 0;
         m_buckets_filled++;

         bucket_total = m_current_bucket_buy + m_current_bucket_sell;
      }

      return true;
   }

   /** @return VPIN of the just-completed bucket. */
   double VPINValue() const
   {
      double total = m_buy_volume_bucket + m_sell_volume_bucket;
      if (total > 0)
         return MathAbs(m_buy_volume_bucket - m_sell_volume_bucket) / total;
      return 0;
   }

   /** @return Most recent completed VPIN, or the partial-bucket VPIN if none. */
   double CurrentVPIN()
   {
      if (m_count == 0)
      {
         double total = m_current_bucket_buy + m_current_bucket_sell;
         if (total > 0)
            return MathAbs(m_current_bucket_buy - m_current_bucket_sell) / total;
         return 0;
      }

      return m_vpin[(m_tail - 1 + m_capacity) % m_capacity];
   }

   /** @param lookback Number of buckets.
     *  @return Mean VPIN over lookback. */
   double AverageVPIN(int lookback = 50)
   {
      if (m_count == 0)
         return 0;

      int n = MathMin(lookback, m_count);
      double sum = 0;

      for (int i = 0; i < n; i++)
      {
         int idx = (m_tail - 1 - i + m_capacity) % m_capacity;
         sum += m_vpin[idx];
      }

      return sum / n;
   }

   /** @param lookback Number of buckets.
     *  @return Sample standard deviation of VPIN over lookback. */
   double VPINStd(int lookback = 50)
   {
      if (m_count < 2)
         return 0;

      int n = MathMin(lookback, m_count);
      double mean = AverageVPIN(n);
      double sum_sq = 0;

      for (int i = 0; i < n; i++)
      {
         int idx = (m_tail - 1 - i + m_capacity) % m_capacity;
         double diff = m_vpin[idx] - mean;
         sum_sq += diff * diff;
      }

      return MathSqrt(sum_sq / (n - 1));
   }

   /** @param lookback  Number of buckets for baseline.
     *  @param threshold Number of standard-deviation thresholds.
     *  @return true if current VPIN exceeds avg + threshold * std. */
   bool IsToxic(int lookback = 50, double threshold = 2.0)
   {
      double current = CurrentVPIN();
      double avg = AverageVPIN(lookback);
      double std = VPINStd(lookback);

      if (std > 0)
         return (current - avg) / std > threshold;
      return false;
   }

   /** @param lookback Number of buckets.
     *  @return Z-score of current VPIN vs lookback distribution. */
   double ToxicityZScore(int lookback = 50)
   {
      double current = CurrentVPIN();
      double avg = AverageVPIN(lookback);
      double std = VPINStd(lookback);

      if (std > 0)
         return (current - avg) / std;
      return 0;
   }

   int BucketsFilled() const { return m_buckets_filled; }
   int Count() const { return m_count; }
   double GetBucketVolume() const { return m_bucket_volume; }
};

/** Combines VPIN with buy/sell pressure to quantify flow toxicity and detect regimes. */
class CMqtFlowToxicity
{
private:
   CMqtVPIN *m_vpin;
   double    m_buy_pressure;
   double    m_sell_pressure;
   int       m_window;

public:
   CMqtFlowToxicity()
   {
      m_vpin = NULL;
      m_buy_pressure = 0;
      m_sell_pressure = 0;
      m_window = 50;
   }

   /** @param vpin   VPIN instance.
    *  @param window Lookback window for toxicity calculations. */
   CMqtFlowToxicity(CMqtVPIN *vpin, int window = 50)
   {
      m_vpin = vpin;
      m_buy_pressure = 0;
      m_sell_pressure = 0;
      m_window = window;
   }

   void SetVPIN(CMqtVPIN *vpin) { m_vpin = vpin; }

   /** @return Combined toxicity score based on VPIN and its Z-score. */
   double ToxicityScore()
   {
      if (m_vpin == NULL)
         return 0;

      double vpin_val = m_vpin.CurrentVPIN();
      double z = m_vpin.ToxicityZScore(m_window);

      return (vpin_val + MathAbs(z) * 0.1) * 0.5;
   }

   /** @param buy_vol  Additional buy volume.
     *  @param sell_vol Additional sell volume. */
   void UpdatePressures(double buy_vol, double sell_vol)
   {
      m_buy_pressure += buy_vol;
      m_sell_pressure += sell_vol;
   }

   /** @return Signed buy/sell pressure ratio in [-1, 1]. */
   double PressureRatio()
   {
      double total = m_buy_pressure + m_sell_pressure;
      if (total > 0)
         return (m_buy_pressure - m_sell_pressure) / total;
      return 0;
   }

   /** @return Estimated market regime based on toxicity and pressure. */
   ENUM_MQT_MARKET_REGIME DetectRegime()
   {
      double toxicity = ToxicityScore();
      double pressure = MathAbs(PressureRatio());

      if (toxicity > 0.8 && pressure > 0.7)
         return MQT_REGIME_FLASH_CRASH;
      if (toxicity > 0.6 && pressure > 0.5)
         return MQT_REGIME_STRESSED;
      if (toxicity > 0.3)
         return MQT_REGIME_NORMAL;

      return MQT_REGIME_QUIET;
   }

   /** Reset pressure accumulators. */
   void Reset()
   {
      m_buy_pressure = 0;
      m_sell_pressure = 0;
   }
};

#endif
