/** @file InfoShare.mqh @brief Hasbrouck information share — permanent vs. temporary price impact decomposition. */

#include "DataTypes.mqh"

#ifndef MQT_INFO_SHARE_MQH
#define MQT_INFO_SHARE_MQH

/** Implements Hasbrouck's information share: the fraction of price-discovery variance attributable to permanent (vs. temporary) innovations. */
class CMqtHasbrouckInfoShare
{
private:
   double   m_price_changes[]; /*!< Ring buffer of price changes. */
   double   m_innovation[];    /*!< Innovation coefficients per lag. */
   int      m_capacity;
   int      m_count;
   int      m_head;
   int      m_tail;
   int      m_lags;
   double   m_info_share;      /*!< Current information share. */
   double   m_perm_impact;     /*!< Permanent impact estimate. */
   double   m_temp_impact;     /*!< Temporary impact estimate. */
   int      m_error;

   int NextIndex(int idx) const { return (idx + 1) % m_capacity; }

   double ComputeVAR(const double &data[], int n, int lag, double &coeff[], int n_coeff)
   {
      if (n <= lag + n_coeff + 2)
         return 0;

      double x[100], y[100];
      int m = MathMin(n - lag - 1, 100);
      m = MathMin(m, 100);

      for (int i = 0; i < m; i++)
      {
         y[i] = data[lag + i + 1];
         x[i] = data[lag + i];
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
   /** @param capacity Ring-buffer capacity for price changes (default: 5000). */
   CMqtHasbrouckInfoShare()
   {
      m_capacity = 5000;
      m_count = 0;
      m_head = 0;
      m_tail = 0;
      m_lags = 10;
      m_info_share = 0;
      m_perm_impact = 0;
      m_temp_impact = 0;
      m_error = MQT_ERR_OK;
      ArrayResize(m_price_changes, m_capacity);
      ArrayResize(m_innovation, m_lags);
   }

   int LastError() const { return m_error; }

   /** @param lags Number of VAR lags (2–50). */
   void SetLags(int lags)
   {
      m_lags = MathMax(2, MathMin(lags, 50));
      ArrayResize(m_innovation, m_lags);
   }

   /** Feed a price-change / trade-sign pair.
     *  @return true if information share was recomputed. */
   bool Add(double price_change, double trade_sign)
   {
      if (m_count == m_capacity)
      {
         m_head = NextIndex(m_head);
         m_count--;
      }

      m_price_changes[m_tail] = price_change;
      m_tail = NextIndex(m_tail);
      m_count++;

      if (m_count <= m_lags + 5)
         return false;

      double tmp[];
      ArrayResize(tmp, m_count);
      int idx = m_head;
      for (int i = 0; i < m_count; i++)
      {
         tmp[i] = m_price_changes[idx];
         idx = NextIndex(idx);
      }

      double coeff[10];
      for (int lag = 0; lag < m_lags && lag < 10; lag++)
      {
         m_innovation[lag] = ComputeVAR(tmp, m_count, lag, coeff, 1);
      }

      double cum_perm = 0;
      for (int lag = 0; lag < m_lags; lag++)
      {
         double imp = m_innovation[lag];
         cum_perm += MathAbs(imp);
      }

      m_perm_impact = cum_perm / m_lags;
      m_temp_impact = MathAbs(m_innovation[0] - m_perm_impact);

      double total = m_perm_impact + m_temp_impact;
      m_info_share = (total > 0) ? m_perm_impact / total : 0;

      return true;
   }

   /** @return Information share (permanent / total impact). */
   double InformationShare() const { return m_info_share; }
   double PermanentImpact() const { return m_perm_impact; }
   double TemporaryImpact() const { return m_temp_impact; }

   /** @param lag Lag index.
     *  @return Innovation coefficient at that lag. */
   double InnovationAtLag(int lag) const
   {
      if (lag >= 0 && lag < m_lags)
         return m_innovation[lag];
      return 0;
   }

   int Count() const { return m_count; }

   /** Clear all data. */
   void Reset()
   {
      m_count = 0;
      m_head = 0;
      m_tail = 0;
      m_info_share = 0;
      m_perm_impact = 0;
      m_temp_impact = 0;
      ArrayInitialize(m_innovation, 0);
   }
};

#endif
