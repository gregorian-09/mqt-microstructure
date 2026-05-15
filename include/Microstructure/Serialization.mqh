/** @file Serialization.mqh @brief Binary file serializer for microstructure stats and order-book snapshots. */

#include "DataTypes.mqh"

#ifndef MQT_SERIALIZATION_MQH
#define MQT_SERIALIZATION_MQH

/** Reads/writes MqtMicrostructureStats and MqtOrderBookSnapshot to/from a binary file with magic-number and version checking. */
class CMqtFileSerializer
{
private:
   int    m_handle;
   string m_filename;
   bool   m_open;
   int    m_error;

   void WriteLong(long val)   { FileWriteLong(m_handle, val); }
   long   ReadLong()          { return FileReadLong(m_handle); }
   void WriteInt(int val)     { FileWriteInteger(m_handle, val); }
   int    ReadInt()           { return (int)FileReadInteger(m_handle); }
   void WriteDbl(double val)  { FileWriteDouble(m_handle, val); }
   double ReadDbl()           { return FileReadDouble(m_handle); }
   void WriteUint(uint val)   { FileWriteInteger(m_handle, (int)val); }

public:
   CMqtFileSerializer()
   {
      m_handle = INVALID_HANDLE;
      m_filename = "";
      m_open = false;
      m_error = MQT_ERR_OK;
   }

   ~CMqtFileSerializer()
   {
      if (m_open)
         Close();
   }

   int LastError() const { return m_error; }

   /** Open a file for writing with magic-number header.
     *  @param filename Path to the file.
     *  @return true on success. */
   bool OpenWrite(string filename)
   {
      m_filename = filename;
      m_handle = FileOpen(m_filename, FILE_WRITE | FILE_BIN | FILE_COMMON);
      if (m_handle == INVALID_HANDLE)
      {
         m_error = MQT_ERR_FILE_IO;
         m_open = false;
         return false;
      }
      m_open = true;
      WriteUint(MQT_FILE_MAGIC);
      WriteInt(MQT_FILE_VERSION);
      return true;
   }

   /** Open a file for reading and verify the header.
     *  @param filename Path to the file.
     *  @return true on success. */
   bool OpenRead(string filename)
   {
      m_filename = filename;
      m_handle = FileOpen(m_filename, FILE_READ | FILE_BIN | FILE_COMMON);
      if (m_handle == INVALID_HANDLE)
      {
         m_error = MQT_ERR_FILE_IO;
         m_open = false;
         return false;
      }
      m_open = true;
      uint magic = (uint)ReadInt();
      if (magic != MQT_FILE_MAGIC)
      {
         Close();
         m_error = MQT_ERR_FILE_IO;
         return false;
      }
      int version = ReadInt();
      if (version != MQT_FILE_VERSION)
      {
         Close();
         m_error = MQT_ERR_FILE_IO;
         return false;
      }
      return true;
   }

   /** Close the file handle. */
   void Close()
   {
      if (m_handle != INVALID_HANDLE)
      {
         FileClose(m_handle);
         m_handle = INVALID_HANDLE;
      }
      m_open = false;
   }

   /** Serialise a MqtMicrostructureStats struct.
     *  @return true on success. */
   bool WriteStats(const MqtMicrostructureStats &stats)
   {
      if (!m_open) { m_error = MQT_ERR_NOT_INITIALIZED; return false; }
      WriteLong(stats.time_start_msc);
      WriteLong(stats.time_end_msc);
      WriteInt(stats.tick_count);
      WriteInt(stats.trade_count);
      WriteInt(stats.quote_count);
      WriteDbl(stats.avg_spread);
      WriteDbl(stats.avg_effective_spread);
      WriteDbl(stats.avg_realized_spread);
      WriteDbl(stats.total_volume);
      WriteDbl(stats.net_order_flow);
      WriteDbl(stats.realized_volatility);
      WriteDbl(stats.kyle_lambda);
      WriteDbl(stats.amihud_illiquidity);
      WriteDbl(stats.avg_bid_depth);
      WriteDbl(stats.avg_ask_depth);
      WriteDbl(stats.vpin);
      WriteDbl(stats.trade_intensity);
      WriteDbl(stats.book_resiliency);
      WriteDbl(stats.info_share);
      WriteDbl(stats.volume_profile_entropy);
      return true;
   }

   /** Deserialise a MqtMicrostructureStats struct.
     *  @return true on success. */
   bool ReadStats(MqtMicrostructureStats &stats)
   {
      if (!m_open) { m_error = MQT_ERR_NOT_INITIALIZED; return false; }
      stats.time_start_msc = ReadLong();
      stats.time_end_msc = ReadLong();
      stats.tick_count = ReadInt();
      stats.trade_count = ReadInt();
      stats.quote_count = ReadInt();
      stats.avg_spread = ReadDbl();
      stats.avg_effective_spread = ReadDbl();
      stats.avg_realized_spread = ReadDbl();
      stats.total_volume = ReadDbl();
      stats.net_order_flow = ReadDbl();
      stats.realized_volatility = ReadDbl();
      stats.kyle_lambda = ReadDbl();
      stats.amihud_illiquidity = ReadDbl();
      stats.avg_bid_depth = ReadDbl();
      stats.avg_ask_depth = ReadDbl();
      stats.vpin = ReadDbl();
      stats.trade_intensity = ReadDbl();
      stats.book_resiliency = ReadDbl();
      stats.info_share = ReadDbl();
      stats.volume_profile_entropy = ReadDbl();
      return true;
   }

   /** Serialise a MqtOrderBookSnapshot.
     *  @return true on success. */
   bool WriteSnapshot(const MqtOrderBookSnapshot &snap)
   {
      if (!m_open) { m_error = MQT_ERR_NOT_INITIALIZED; return false; }
      WriteLong(snap.time_msc);
      WriteInt(snap.bid_count);
      WriteInt(snap.ask_count);
      WriteDbl(snap.bid_depth_total);
      WriteDbl(snap.ask_depth_total);

      for (int i = 0; i < snap.bid_count; i++)
      {
         WriteDbl(snap.bids[i].price);
         WriteLong(snap.bids[i].volume);
         WriteDbl(snap.bids[i].volume_real);
      }
      for (int i = 0; i < snap.ask_count; i++)
      {
         WriteDbl(snap.asks[i].price);
         WriteLong(snap.asks[i].volume);
         WriteDbl(snap.asks[i].volume_real);
      }
      return true;
   }

   /** Deserialise a MqtOrderBookSnapshot.
     *  @return true on success. */
   bool ReadSnapshot(MqtOrderBookSnapshot &snap)
   {
      if (!m_open) { m_error = MQT_ERR_NOT_INITIALIZED; return false; }
      snap.time_msc = ReadLong();
      snap.bid_count = ReadInt();
      snap.ask_count = ReadInt();
      snap.bid_depth_total = ReadDbl();
      snap.ask_depth_total = ReadDbl();

      int max_bids = MathMin(snap.bid_count, MQT_MAX_BOOK_DEPTH);
      for (int i = 0; i < max_bids; i++)
      {
         snap.bids[i].price = ReadDbl();
         snap.bids[i].volume = ReadLong();
         snap.bids[i].volume_real = ReadDbl();
      }
      int max_asks = MathMin(snap.ask_count, MQT_MAX_BOOK_DEPTH);
      for (int i = 0; i < max_asks; i++)
      {
         snap.asks[i].price = ReadDbl();
         snap.asks[i].volume = ReadLong();
         snap.asks[i].volume_real = ReadDbl();
      }
      return true;
   }

   bool IsOpen() const { return m_open; }
};

#endif
