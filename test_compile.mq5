/**
 * Test compilation file for MQT Microstructure Library
 */
#property version   "1.00"
#property description "MQT Microstructure Analysis Library — compilation verification"
#include <Microstructure.mqh>

CMqtEventCoordinator ms;

int OnInit()
{
   MqtConfig cfg;
   cfg.symbol = _Symbol;
   cfg.SetHighFreq(50000);
   cfg.active_modules = MQT_MODULE_ALL;
   return ms.Init(cfg) ? INIT_SUCCEEDED : INIT_FAILED;
}

void OnTick()
{
   MqlTick tick;
   SymbolInfoTick(_Symbol, tick);
   ms.OnTick(tick);
}

void OnDeinit(const int reason)
{
   MqtMicrostructureStats stats;
   ms.ComputeStats(stats);
   Print(stats.ToString());
}
