/** @file MarketModels.mqh @brief Market-maker spread decomposition, microstructure score, regime detection, and liquidity surface. */

#include "DataTypes.mqh"
#include "Liquidity.mqh"
#include "OrderFlow.mqh"
#include "PriceImpact.mqh"
#include "Volatility.mqh"
#include "TradeClassification.mqh"
#include "DurationAnalysis.mqh"

#ifndef MQT_MARKETMODELS_MQH
#define MQT_MARKETMODELS_MQH

/** Spread decomposition into adverse selection, inventory, and order-processing components. */
class CMqtMarketMakerModel
{
private:
   double   m_adverse_selection_cost;
   double   m_inventory_cost;
   double   m_order_processing_cost;
   double   m_spread_decomposition_valid;

public:
   CMqtMarketMakerModel()
   {
      m_adverse_selection_cost = 0;
      m_inventory_cost = 0;
      m_order_processing_cost = 0;
      m_spread_decomposition_valid = false;
   }

   /** Decompose the quoted spread into three components.
     *  @param spread_analyzer Source of spread estimates.
     *  @param kyle_lambda     Source of Kyle's lambda (adverse selection proxy).
     *  @param lookback        Number of observations.
     *  @return true on success. */
   bool DecomposeSpread(CMqtSpreadAnalyzer *spread_analyzer,
                        CMqtKyleLambda *kyle_lambda,
                        int lookback = 100)
   {
      if (spread_analyzer == NULL || kyle_lambda == NULL)
         return false;

      double quoted = spread_analyzer.AverageQuotedSpread(lookback);
      double effective = spread_analyzer.AverageEffectiveSpread(lookback);
      double kyle = kyle_lambda.AverageLambda(lookback);

      if (quoted <= 0 || effective <= 0)
         return false;

      double realized = 2.0 * effective - quoted;
      if (realized < 0)
         realized = 0;

      m_adverse_selection_cost = MathMax(0, effective - realized);
      m_order_processing_cost = realized;
      m_inventory_cost = MathMax(0, quoted - 2.0 * effective);

      m_spread_decomposition_valid = true;
      return true;
   }

   double AdverseSelectionComponent() const { return m_adverse_selection_cost; }
   double InventoryComponent() const { return m_inventory_cost; }
   double OrderProcessingComponent() const { return m_order_processing_cost; }

   /** @return PIN proxy: adverse selection / (adverse selection + order processing). */
   double ProbabilityOfInformedTrading()
   {
      if (!m_spread_decomposition_valid)
         return 0;

      double total = m_adverse_selection_cost + m_order_processing_cost;
      if (total > 0)
         return m_adverse_selection_cost / total;
      return 0;
   }

   /** Clear all computed values. */
   void Reset()
   {
      m_adverse_selection_cost = 0;
      m_inventory_cost = 0;
      m_order_processing_cost = 0;
      m_spread_decomposition_valid = false;
   }
};

/** Aggregates liquidity, flow, impact, and efficiency into a single microstructure quality score. */
class CMqtMicrostructureScore
{
private:
   double   m_liquidity_score;
   double   m_flow_score;
   double   m_impact_score;
   double   m_efficiency_score;
   double   m_total_score;
   bool     m_computed;

public:
   CMqtMicrostructureScore()
   {
      m_liquidity_score = 0;
      m_flow_score = 0;
      m_impact_score = 0;
      m_efficiency_score = 0;
      m_total_score = 0;
      m_computed = false;
   }

   /** Compute all sub-scores from the provided analyzers.
     *  @return true on success. */
   bool Compute(CMqtSpreadAnalyzer *spread,
                CMqtDepthAnalyzer *depth,
                CMqtOrderFlowImbalance *flow,
                CMqtKyleLambda *kyle,
                CMqtRealizedVolatility *vol,
                CMqtTradeDuration *duration)
   {
      if (spread != NULL)
      {
         double qs = spread.AverageQuotedSpread(50);
         m_liquidity_score = 1.0 - MathMin(1.0, qs * 1000);
      }

      if (depth != NULL)
      {
         m_liquidity_score = (m_liquidity_score +
            MathMin(1.0, depth.AverageDepth(10) / 5000.0)) * 0.5;
      }

      if (flow != NULL)
      {
         double imb = MathAbs(flow.AverageImbalance(50));
         m_flow_score = 1.0 - imb;
      }

      if (kyle != NULL)
      {
         double lam = kyle.AverageLambda(50);
         m_impact_score = 1.0 - MathMin(1.0, lam * 100);
      }

      if (vol != NULL)
      {
         double rv = vol.Average(50);
         m_efficiency_score = 1.0 - MathMin(1.0, rv * 10);
      }

      if (duration != NULL)
      {
         double intensity = duration.TradeIntensity(50);
         m_efficiency_score = (m_efficiency_score +
            MathMin(1.0, intensity / 10.0)) * 0.5;
      }

      m_total_score = (m_liquidity_score + m_flow_score +
                       m_impact_score + m_efficiency_score) / 4.0;

      m_computed = true;
      return true;
   }

   double TotalScore() const { return m_total_score; }
   double LiquidityScore() const { return m_liquidity_score; }
   double FlowScore() const { return m_flow_score; }
   double ImpactScore() const { return m_impact_score; }
   double EfficiencyScore() const { return m_efficiency_score; }

   /** @return Categorical rating string. */
   string Rating()
   {
      if (!m_computed)
         return "N/A";

      if (m_total_score >= 0.8)
         return "Excellent";
      else if (m_total_score >= 0.6)
         return "Good";
      else if (m_total_score >= 0.4)
         return "Fair";
      else if (m_total_score >= 0.2)
         return "Poor";

      return "Very Poor";
   }

   bool IsComputed() const { return m_computed; }
};

/** Detects market regimes (flash crash, stressed, normal, quiet) from microstructure signals. */
class CMqtRegimeDetector
{
private:
   double   m_spread_threshold_high;
   double   m_spread_threshold_low;
   double   m_volatility_threshold_high;
   double   m_volatility_threshold_low;
   double   m_vpin_threshold_high;
   double   m_cvd_threshold_extreme;
   double   m_lookback;

public:
   /** Sensible defaults for equity/forex markets. */
   CMqtRegimeDetector()
   {
      m_spread_threshold_high = 0.005;
      m_spread_threshold_low = 0.0005;
      m_volatility_threshold_high = 0.02;
      m_volatility_threshold_low = 0.005;
      m_vpin_threshold_high = 0.6;
      m_cvd_threshold_extreme = 0.8;
      m_lookback = 50;
   }

   /** @param spread_high  Spread threshold for stressed regime.
     *  @param spread_low   Spread threshold for quiet regime.
     *  @param vol_high     Volatility threshold for stressed regime.
     *  @param vol_low      Volatility threshold for quiet regime.
     *  @param vpin_high    VPIN threshold for informed trading.
     *  @param cvd_extreme  CVD Z-score threshold for extreme flow. */
   void SetThresholds(double spread_high, double spread_low,
                      double vol_high, double vol_low,
                      double vpin_high, double cvd_extreme)
   {
      m_spread_threshold_high = spread_high;
      m_spread_threshold_low = spread_low;
      m_volatility_threshold_high = vol_high;
      m_volatility_threshold_low = vol_low;
      m_vpin_threshold_high = vpin_high;
      m_cvd_threshold_extreme = cvd_extreme;
   }

   /** @return Detected regime. */
   ENUM_MQT_MARKET_REGIME Detect(CMqtSpreadAnalyzer *spread,
                                  CMqtRealizedVolatility *vol,
                                  CMqtVPIN *vpin,
                                  CMqtCumulativeVolumeDelta *cvd,
                                  CMqtOrderFlowImbalance *flow)
   {
      if (spread == NULL || vol == NULL)
         return MQT_REGIME_UNKNOWN;

      double qs = spread.AverageQuotedSpread((int)m_lookback);
      double rv = vol.Average((int)m_lookback);

      if (qs >= m_spread_threshold_high * 3 && rv >= m_volatility_threshold_high * 3)
         return MQT_REGIME_FLASH_CRASH;

      if (qs >= m_spread_threshold_high * 2 && rv >= m_volatility_threshold_high * 2)
         return MQT_REGIME_STRESSED;

      double vpin_val = 0;
      double cvd_val = 0;
      double imb_val = 0;

      if (vpin != NULL)
      {
         vpin_val = vpin.CurrentVPIN();
         if (vpin_val > m_vpin_threshold_high &&
             qs > m_spread_threshold_high &&
             rv > m_volatility_threshold_high)
            return MQT_REGIME_STRESSED;
      }

      if (cvd != NULL)
      {
         double cvd_z = MathAbs(cvd.ZScore((int)m_lookback));
         if (cvd_z > m_cvd_threshold_extreme)
            return MQT_REGIME_STRESSED;
      }

      if (flow != NULL)
      {
         imb_val = MathAbs(flow.AverageImbalance((int)m_lookback));
      }

      if (qs <= m_spread_threshold_low && rv <= m_volatility_threshold_low &&
          vpin_val < 0.3 && imb_val < 0.2)
         return MQT_REGIME_QUIET;

      return MQT_REGIME_NORMAL;
   }

   /** @return true if the market appears stressed. */
   bool IsStressRegime(CMqtSpreadAnalyzer *spread,
                        CMqtRealizedVolatility *vol)
   {
      if (spread == NULL || vol == NULL)
         return false;

      double qs = spread.AverageQuotedSpread((int)m_lookback);
      double rv = vol.Average((int)m_lookback);

      return (qs > m_spread_threshold_high && rv > m_volatility_threshold_high);
   }

   /** @return true if the market appears quiet. */
   bool IsQuietRegime(CMqtSpreadAnalyzer *spread,
                       CMqtRealizedVolatility *vol)
   {
      if (spread == NULL || vol == NULL)
         return false;

      double qs = spread.AverageQuotedSpread((int)m_lookback);
      double rv = vol.Average((int)m_lookback);

      return (qs < m_spread_threshold_low && rv < m_volatility_threshold_low);
   }
};

/** 2D liquidity surface keyed by time-of-day and trade volume. */
class CMqtLiquiditySurface
{
private:
   double   m_surface[10][10]; /*!< Liquidity values by [time_bucket][volume_bucket]. */
   int      m_time_buckets;
   int      m_volume_buckets;
   bool     m_initialized;

public:
   CMqtLiquiditySurface()
   {
      m_time_buckets = 10;
      m_volume_buckets = 10;
      m_initialized = false;
      ArrayInitialize(m_surface, 0);
   }

   /** @param time_buckets Number of intraday time divisions (2-10).
     *  @param vol_buckets  Number of volume tiers (2-10). */
   void Init(int time_buckets, int vol_buckets)
   {
      m_time_buckets = MathMax(2, MathMin(time_buckets, 10));
      m_volume_buckets = MathMax(2, MathMin(vol_buckets, 10));
      ArrayInitialize(m_surface, 0);
      m_initialized = true;
   }

   /** Record a liquidity observation into the surface.
     *  @return true if initialized. */
   bool AddObservation(datetime time, double volume, double liquidity_metric)
   {
      if (!m_initialized)
         return false;

      MqlDateTime dt;
      TimeToStruct(time, dt);

      double minute_of_day = (double)(dt.hour * 60 + dt.min);
      double total_minutes = 24.0 * 60.0;

      int t_idx = (int)(minute_of_day / total_minutes * m_time_buckets);
      t_idx = MathMax(0, MathMin(t_idx, m_time_buckets - 1));

      double log_vol = (volume > 0) ? MathLog(volume) : 0;
      double max_log_vol = MathLog(1000000);
      int v_idx = (int)((log_vol / max_log_vol) * m_volume_buckets);
      v_idx = MathMax(0, MathMin(v_idx, m_volume_buckets - 1));

      m_surface[t_idx][v_idx] = (m_surface[t_idx][v_idx] + liquidity_metric) * 0.5;

      return true;
   }

   /** @return Liquidity value for the given time and volume. */
   double GetLiquidity(datetime time, double volume)
   {
      if (!m_initialized)
         return 0;

      MqlDateTime dt;
      TimeToStruct(time, dt);

      double minute_of_day = (double)(dt.hour * 60 + dt.min);
      double total_minutes = 24.0 * 60.0;

      int t_idx = (int)(minute_of_day / total_minutes * m_time_buckets);
      t_idx = MathMax(0, MathMin(t_idx, m_time_buckets - 1));

      double log_vol = (volume > 0) ? MathLog(volume) : 0;
      double max_log_vol = MathLog(1000000);
      int v_idx = (int)((log_vol / max_log_vol) * m_volume_buckets);
      v_idx = MathMax(0, MathMin(v_idx, m_volume_buckets - 1));

      return m_surface[t_idx][v_idx];
   }

   /** @return Mean of all populated surface cells. */
   double AverageLiquidity() const
   {
      double sum = 0;
      int count = 0;

      for (int i = 0; i < m_time_buckets; i++)
      {
         for (int j = 0; j < m_volume_buckets; j++)
         {
            if (m_surface[i][j] > 0)
            {
               sum += m_surface[i][j];
               count++;
            }
         }
      }

      return (count > 0) ? sum / count : 0;
   }

   /** Copy the surface into a caller-supplied array.
     *  @return true. */
   bool ExportSurface(double &out[][10], int &rows, int &cols) const
   {
      rows = m_time_buckets;
      cols = m_volume_buckets;

      for (int i = 0; i < rows; i++)
         for (int j = 0; j < cols; j++)
            out[i][j] = m_surface[i][j];

      return true;
   }
};

#endif
