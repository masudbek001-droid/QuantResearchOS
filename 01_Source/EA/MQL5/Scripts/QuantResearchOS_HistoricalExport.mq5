//+------------------------------------------------------------------+
//| QuantResearchOS Stage 2 historical-export acceptance harness     |
//| Validation-only script. It does not place or modify trades.     |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EAData\DatabaseManager.mqh>
#include <CandleBreakoutEA\EAHistory\HistoryPlatform.mqh>

input ulong InpAcceptanceMagic = 20260909;
input string InpReportFile = "CBEA\\stage2_historical_export_report.txt";

void WriteReport(const string text)
  {
   const int handle=FileOpen(InpReportFile,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(handle==INVALID_HANDLE)
     {
      Print("[QROS_STAGE2] report open failed | ",GetLastError());
      return;
     }
   FileWriteString(handle,text);
   FileClose(handle);
  }

void OnStart()
  {
   const string probe_file="qros_database_probe.db";
   const int probe=(int)DatabaseOpen(probe_file,DATABASE_OPEN_CREATE|DATABASE_OPEN_READWRITE);
   const string existing_file="candlebreakout_20260909.db";
   const int existing=(int)DatabaseOpen(existing_file,DATABASE_OPEN_CREATE|DATABASE_OPEN_READWRITE);
   string probe_evidence=StringFormat("PROBE_HANDLE=%d; PROBE_EXISTS=%d; DATA_PATH=%s",
                                      probe,(int)FileIsExist(probe_file),
                                      TerminalInfoString(TERMINAL_DATA_PATH));
   PrintFormat("[QROS_STAGE2] EXISTING_HANDLE=%d; EXISTING_FILE=%d",
               existing,(int)FileIsExist(existing_file));
   if(probe>0)
      DatabaseClose(probe);
   if(existing>0)
      DatabaseClose(existing);
   Print("[QROS_STAGE2] ",probe_evidence);

   CEASettings settings;
   settings.Reset();
   settings.symbol_name=_Symbol;
   settings.magic=InpAcceptanceMagic;
   settings.log_level=LOG_DEBUG;

   CLogger logger;
   logger.Enable(true);
   logger.Init(settings.magic,settings.symbol_name,LOG_DEBUG);

   CDatabaseManager research;
   research.Initialize(settings,logger);
   if(!research.Open())
     {
      WriteReport(StringFormat("STAGE=2\nSTATUS=FAIL\nREASON=Research database open failed\n%s\nLAST_ERROR=%d\nTERMINAL_PATH=%s\nDATA_PATH=%s\n",
                               probe_evidence,
                               GetLastError(),TerminalInfoString(TERMINAL_PATH),
                               TerminalInfoString(TERMINAL_DATA_PATH)));
      Print("[QROS_STAGE2] FAIL | research database open");
      return;
     }

   CHistoryPlatform history;
   if(!history.Initialize(settings,logger,research))
     {
      WriteReport("STAGE=2\nSTATUS=FAIL\nREASON=History platform initialization failed\n");
      Print("[QROS_STAGE2] FAIL | history platform initialization");
      research.Close();
      return;
     }

   string export_report="", integrity_report="", statistics_report="";
   const bool export_ok=history.ExportAllHistory(export_report);
   const bool integrity_ok=history.ValidateIntegrity(integrity_report);
   const bool statistics_ok=history.GenerateStatistics(statistics_report);
   const bool pass=(export_ok && integrity_ok && statistics_ok);

   string evidence=StringFormat(
      "STAGE=2\nSTATUS=%s\nEXPORT=%s\nINTEGRITY=%s\nSTATISTICS=%s\n\n%s\n%s\n%s\n",
      (pass ? "PASS" : "FAIL"),
      (export_ok ? "PASS" : "FAIL"),
      (integrity_ok ? "PASS" : "FAIL"),
      (statistics_ok ? "PASS" : "FAIL"),
      export_report,integrity_report,statistics_report);
   WriteReport(evidence);
   Print("[QROS_STAGE2] ",evidence);

   history.Shutdown();
   research.Close();
  }
