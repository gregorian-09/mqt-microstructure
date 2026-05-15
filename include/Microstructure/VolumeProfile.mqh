/** @file VolumeProfile.mqh @brief Volume profile — price-bin accumulation, VWAP, POC, value area, and entropy. */

#include "DataTypes.mqh"

#ifndef MQT_VOLUME_PROFILE_MQH
#define MQT_VOLUME_PROFILE_MQH

/** Accumulates volume into price bins and computes volume-profile statistics (POC, value area, VWAP, entropy). */
class CMqtVolumeProfile
{
private:
   int      m_bins;                /*!< Number of price bins. */
   double   m_min_price;
   double   m_max_price;
   double   m_bin_size;
   double   m_volume_by_bin[];     /*!< Volume per bin. */
   long     m_trade_count_by_bin[];
   double   m_vwap_by_bin[];       /*!< Price*volume accumulator per bin. */
   double   m_total_volume;
   long     m_total_trades;
   double   m_vwap_total;
   double   m_poc_price;           /*!< Price at the point of control. */
   double   m_poc_volume;          /*!< Volume at the point of control. */
   int      m_poc_bin;             /*!< Bin index of the point of control. */
   bool     m_initialized;

public:
   CMqtVolumeProfile()
   {
      m_bins = 24;
      m_min_price = 0;
      m_max_price = 0;
      m_bin_size = 0;
      m_total_volume = 0;
      m_total_trades = 0;
      m_vwap_total = 0;
      m_poc_price = 0;
      m_poc_volume = 0;
      m_poc_bin = 0;
      m_initialized = false;
   }

   int LastError() const { return MQT_ERR_OK; }

   /** Initialise the profile with explicit price bounds.
     *  @param bins     Number of price bins.
     *  @param min_price Lower bound.
     *  @param max_price Upper bound.
     *  @return true on success. */
   bool Init(int bins, double min_price, double max_price)
   {
      if (bins < 2 || max_price <= min_price)
      {
         return false;
      }

      m_bins = bins;
      m_min_price = min_price;
      m_max_price = max_price;
      m_bin_size = (max_price - min_price) / bins;

      ArrayResize(m_volume_by_bin, m_bins);
      ArrayResize(m_trade_count_by_bin, m_bins);
      ArrayResize(m_vwap_by_bin, m_bins);
      ArrayInitialize(m_volume_by_bin, 0);
      ArrayInitialize(m_trade_count_by_bin, 0);
      ArrayInitialize(m_vwap_by_bin, 0);

      m_total_volume = 0;
      m_total_trades = 0;
      m_vwap_total = 0;
      m_initialized = true;

      return true;
   }

   /** Initialise with automatic bounds from current market price.
     *  @param symbol Instrument name.
     *  @param bins   Number of price bins.
     *  @return true on success. */
   bool InitAuto(string symbol, int bins = 24)
   {
      double min_price = SymbolInfoDouble(symbol, SYMBOL_BID) * 0.995;
      double max_price = SymbolInfoDouble(symbol, SYMBOL_ASK) * 1.005;

      if (max_price <= min_price)
      {
         MqlTick tick;
         SymbolInfoTick(symbol, tick);
         if (tick.last > 0)
         {
            min_price = tick.last * 0.995;
            max_price = tick.last * 1.005;
         }
         else
         {
            min_price = 1.0;
            max_price = 2.0;
         }
      }

      return Init(bins, min_price, max_price);
   }

   /** Record a trade into the appropriate bin.
     *  @return true on success. */
   bool AddTrade(double price, ulong volume)
   {
      if (!m_initialized || volume == 0)
         return false;

      int bin = (int)((price - m_min_price) / m_bin_size);
      if (bin < 0) bin = 0;
      if (bin >= m_bins) bin = m_bins - 1;

      double vol = (double)volume;
      m_volume_by_bin[bin] += vol;
      m_trade_count_by_bin[bin]++;
      m_vwap_by_bin[bin] += price * vol;
      m_total_volume += vol;
      m_total_trades++;
      m_vwap_total += price * vol;

      if (m_volume_by_bin[bin] > m_poc_volume)
      {
         m_poc_volume = m_volume_by_bin[bin];
         m_poc_bin = bin;
         m_poc_price = m_min_price + (bin + 0.5) * m_bin_size;
      }

      return true;
   }

   /** Record a trade from an MqtTick.
     *  @return true if the tick contains a trade. */
   bool AddTick(const MqtTick &tick)
   {
      if (tick.HasTrade())
         return AddTrade(tick.last, tick.volume);
      return false;
   }

   /** @param bin Bin index.
     *  @return Volume in that bin. */
   double VolumeAtBin(int bin) const
   {
      if (!m_initialized || bin < 0 || bin >= m_bins)
         return 0;
      return m_volume_by_bin[bin];
   }

   /** @return VWAP for a specific bin. */
   double VWAPAtBin(int bin) const
   {
      if (!m_initialized || bin < 0 || bin >= m_bins || m_volume_by_bin[bin] <= 0)
         return 0;
      return m_vwap_by_bin[bin] / m_volume_by_bin[bin];
   }

   double TotalVolume() const { return m_total_volume; }
   double VWAP() const { return (m_total_volume > 0) ? m_vwap_total / m_total_volume : 0; }
   double POCPrice() const { return m_poc_price; }
   double POCVolume() const { return m_poc_volume; }
   int POCBin() const { return m_poc_bin; }
   int BinCount() const { return m_bins; }
   double BinSize() const { return m_bin_size; }

   /** @param volume_percent Fraction of total volume to cover.
     *  @return Lower bound of the value area. */
   double ValueAreaLow(double volume_percent = 0.70)
   {
      if (!m_initialized || m_total_volume <= 0)
         return m_min_price;

      double target = m_total_volume * volume_percent;
      double cum = m_poc_volume;
      int low_bin = m_poc_bin, high_bin = m_poc_bin;

      while (cum < target)
      {
         double left_vol = (low_bin > 0) ? m_volume_by_bin[low_bin - 1] : -1;
         double right_vol = (high_bin < m_bins - 1) ? m_volume_by_bin[high_bin + 1] : -1;

         if (left_vol >= right_vol && left_vol >= 0)
         {
            low_bin--;
            cum += left_vol;
         }
         else if (right_vol >= 0)
         {
            high_bin++;
            cum += right_vol;
         }
         else
         {
            break;
         }
      }

      return m_min_price + low_bin * m_bin_size;
   }

   /** @param volume_percent Fraction of total volume to cover.
     *  @return Upper bound of the value area. */
   double ValueAreaHigh(double volume_percent = 0.70)
   {
      if (!m_initialized || m_total_volume <= 0)
         return m_max_price;

      double target = m_total_volume * volume_percent;
      double cum = m_poc_volume;
      int low_bin = m_poc_bin, high_bin = m_poc_bin;

      while (cum < target)
      {
         double left_vol = (low_bin > 0) ? m_volume_by_bin[low_bin - 1] : -1;
         double right_vol = (high_bin < m_bins - 1) ? m_volume_by_bin[high_bin + 1] : -1;

         if (left_vol >= right_vol && left_vol >= 0)
         {
            low_bin--;
            cum += left_vol;
         }
         else if (right_vol >= 0)
         {
            high_bin++;
            cum += right_vol;
         }
         else
         {
            break;
         }
      }

      return m_min_price + (high_bin + 1) * m_bin_size;
   }

   /** @return Normalised entropy of the volume distribution (0 = concentrated, 1 = uniform). */
   double Entropy() const
   {
      if (!m_initialized || m_total_volume <= 0)
         return 0;

      double entropy = 0;
      for (int i = 0; i < m_bins; i++)
      {
         if (m_volume_by_bin[i] > 0)
         {
            double p = m_volume_by_bin[i] / m_total_volume;
            entropy -= p * MathLog(p);
         }
      }

      double max_entropy = MathLog((double)m_bins);
      return (max_entropy > 0) ? entropy / max_entropy : 0;
   }

   /** @return Volume-weighted skew of the price distribution. */
   double Skew() const
   {
      if (!m_initialized || m_total_volume <= 0)
         return 0;

      double mean = VWAP();
      double weighted_sum = 0;
      double vol_sum = 0;

      for (int i = 0; i < m_bins; i++)
      {
         double bin_mid = m_min_price + (i + 0.5) * m_bin_size;
         double dev = bin_mid - mean;
         weighted_sum += m_volume_by_bin[i] * dev * dev * dev;
         vol_sum += m_volume_by_bin[i];
      }

      double variance = 0;
      for (int i = 0; i < m_bins; i++)
      {
         double bin_mid = m_min_price + (i + 0.5) * m_bin_size;
         double dev = bin_mid - mean;
         variance += m_volume_by_bin[i] * dev * dev;
      }
      variance /= vol_sum;

      if (variance <= 0)
         return 0;

      double std = MathSqrt(variance);
      return (weighted_sum / vol_sum) / (std * std * std);
   }

   /** Clear all data without deinitialising bin structure. */
   void Reset()
   {
      if (m_initialized)
      {
         ArrayInitialize(m_volume_by_bin, 0);
         ArrayInitialize(m_trade_count_by_bin, 0);
         ArrayInitialize(m_vwap_by_bin, 0);
      }
      m_total_volume = 0;
      m_total_trades = 0;
      m_vwap_total = 0;
      m_poc_volume = 0;
      m_poc_price = 0;
      m_poc_bin = 0;
   }
};

#endif
