//+------------------------------------------------------------------+
//|                             EAData/FeatureRegistry.mqh           |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Feature Registry: official feature catalogue |
//+------------------------------------------------------------------+
#ifndef __EA_DAL_FEATURE_REGISTRY_MQH__
#define __EA_DAL_FEATURE_REGISTRY_MQH__

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EAData\DatabaseTypes.mqh>
#include <CandleBreakoutEA\EAData\DatabaseManager.mqh>
#include <CandleBreakoutEA\EAData\LabelGenerator.mqh>

//--- STEP 4 manifest: sidecar file next to the exported CSV
#define REGISTRY_MANIFEST_DIR "CBEA"

//+------------------------------------------------------------------+
//| One registry row as returned by GetFeature()                     |
//+------------------------------------------------------------------+
struct SFeatureInfo
  {
   long                id;
   string              name;
   int                 version;
   ENUM_FEATURE_CATEGORY category;
   string              description;
   string              owner;
   string              rule;
   ENUM_FEATURE_STATUS status;
  };

//+------------------------------------------------------------------+
//| The official catalogue of every market feature. The registry is  |
//| the only source of truth for feature definitions: name, version, |
//| category, description, owner, validation rule and status.        |
//| Registration is idempotent; trading never reads the registry.    |
//+------------------------------------------------------------------+
class CFeatureRegistry
  {
private:
   const CEASettings  *m_set;
   CLogger            *m_log;
   CDatabaseManager   *m_db;
   datetime            m_last_manifest;

   bool                Exists(const string name,const int version)
     {
      string rows[];
      return(m_db.Select(StringFormat(
                "SELECT COUNT(*) FROM %s WHERE FeatureName='%s' AND FeatureVersion=%d",
                DB_TABLE_FEATURES,name,version),rows)==1 &&
             StringToInteger(rows[0])>0);
     }

public:
                       CFeatureRegistry(void) : m_set(NULL), m_log(NULL), m_db(NULL),
                          m_last_manifest(0) {}

   void                Initialize(const CEASettings &settings,CLogger &logger,CDatabaseManager &db)
     {
      m_set = &settings;
      m_log = &logger;
      m_db  = &db;
      if(m_db!=NULL && m_db.IsOpen())
         SeedStandardFeatures();
      m_log.Info("Feature Registry initialized");
     }

   //--- STEP 5: rule set shared by registration and lookup
   bool                ValidateFeature(const string name,const int version,
                                       const ENUM_FEATURE_CATEGORY category,
                                       const string validation_rule)
     {
      if(StringLen(name)==0)
        { m_log.Warn("Feature rejected | empty name"); return(false); }
      if(version<=0)
        { m_log.Warn(StringFormat("Feature %s rejected | invalid version",name)); return(false); }
      if((int)category<0 || (int)category>=FEATURE_CATEGORIES_TOTAL)
        { m_log.Warn(StringFormat("Feature %s rejected | unknown category",name)); return(false); }
      if(StringLen(validation_rule)==0)
        { m_log.Warn(StringFormat("Feature %s rejected | missing validation rule",name)); return(false); }
      return(true);
     }

   //--- STEP 3: register one feature definition (idempotent per name+version)
   bool                RegisterFeature(const string name,const int version,
                                       const ENUM_FEATURE_CATEGORY category,
                                       const string description,const string owner,
                                       const string validation_rule)
     {
      if(m_db==NULL || !m_db.IsOpen())
         return(false);
      if(!ValidateFeature(name,version,category,validation_rule))
         return(false);
      if(Exists(name,version))
         return(true);   // duplicate name+version: already catalogued, not an error

      const string stamp = TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES);
      const string sql = StringFormat(
         "INSERT INTO %s (FeatureName,FeatureVersion,FeatureCategory,Description,Owner,"
         "ValidationRule,Status,CreatedAt) VALUES ('%s',%d,%d,'%s','%s','%s',%d,'%s')",
         DB_TABLE_FEATURES,name,version,(int)category,description,owner,
         validation_rule,(int)FEATURE_ACTIVE,stamp);
      if(m_db.Insert(sql)!=1)
        {
         m_log.Warn(StringFormat("Feature registration failed | %s v%d",name,version));
         return(false);
        }
      return(true);
     }

   //--- STEP 3: fetch one definition
   bool                GetFeature(const string name,const int version,SFeatureInfo &info)
     {
      if(m_db==NULL || !m_db.IsOpen())
         return(false);
      string rows[];
      if(m_db.Select(StringFormat(
            "SELECT FeatureID,FeatureName,FeatureVersion,FeatureCategory,Description,"
            "Owner,ValidationRule,Status FROM %s WHERE FeatureName='%s' AND FeatureVersion=%d",
            DB_TABLE_FEATURES,name,version),rows)!=1)
         return(false);
      string c[];
      if(StringSplit(rows[0],';',c)!=8)
         return(false);
      info.id          = StringToInteger(c[0]);
      info.name        = c[1];
      info.version     = (int)StringToInteger(c[2]);
      info.category    = (ENUM_FEATURE_CATEGORY)StringToInteger(c[3]);
      info.description = c[4];
      info.owner       = c[5];
      info.rule        = c[6];
      info.status      = (ENUM_FEATURE_STATUS)StringToInteger(c[7]);
      return(true);
     }

   //--- STEP 3: newest non-deprecated version of a feature (0 = unknown)
   int                 GetVersion(const string name)
     {
      if(m_db==NULL || !m_db.IsOpen())
         return(0);
      string rows[];
      if(m_db.Select(StringFormat(
            "SELECT MAX(FeatureVersion) FROM %s WHERE FeatureName='%s' AND Status<>%d",
            DB_TABLE_FEATURES,name,(int)FEATURE_DEPRECATED),rows)!=1)
         return(0);
      return((int)StringToInteger(rows[0]));
     }

   //--- STEP 3: the whole catalogue, ordered for deterministic output
   int                 ListFeatures(string &lines[])
     {
      ArrayResize(lines,0);
      if(m_db==NULL || !m_db.IsOpen())
         return(-1);
      return(m_db.Select(StringFormat(
                "SELECT FeatureName,FeatureVersion,FeatureCategory,Status,ValidationRule "
                "FROM %s ORDER BY FeatureName ASC,FeatureVersion ASC",
                DB_TABLE_FEATURES),lines));
     }

   //--- the official catalogue: every SFeatureSnapshot feature, version 1
   void                SeedStandardFeatures(void)
     {
      const string owner = "CFeatureBuilder";
      RegisterFeature("Spread",1,FEATURE_PRICE,"ask-bid distance in points",owner,">=0, finite");
      RegisterFeature("ATR",1,FEATURE_VOLATILITY,"true range average over 14 completed bars",owner,">=0, finite");
      RegisterFeature("ATRRatio",1,FEATURE_VOLATILITY,"last completed range / ATR",owner,">=0, finite");
      RegisterFeature("PreviousRange",1,FEATURE_PRICE,"high-low of bar[2]",owner,">=0, finite");
      RegisterFeature("CurrentRange",1,FEATURE_PRICE,"high-low of bar[1]",owner,">0, finite");
      RegisterFeature("BodySize",1,FEATURE_PRICE,"|close-open| of bar[1]",owner,">=0, finite");
      RegisterFeature("BodyPercent",1,FEATURE_PRICE,"body/range of bar[1] in percent",owner,"0..100");
      RegisterFeature("UpperShadow",1,FEATURE_PRICE,"upper wick of bar[1]",owner,">=0, finite");
      RegisterFeature("LowerShadow",1,FEATURE_PRICE,"lower wick of bar[1]",owner,">=0, finite");
      RegisterFeature("UpperShadowRatio",1,FEATURE_PRICE,"upper shadow / range",owner,"0..1");
      RegisterFeature("LowerShadowRatio",1,FEATURE_PRICE,"lower shadow / range",owner,"0..1");
      RegisterFeature("Bullish",1,FEATURE_PRICE,"bar[1] closed above its open",owner,"boolean");
      RegisterFeature("Bearish",1,FEATURE_PRICE,"bar[1] closed below its open",owner,"boolean");
      RegisterFeature("Volatility",1,FEATURE_VOLATILITY,"ATR expressed in points",owner,">=0, finite");
      RegisterFeature("TrendDirection",1,FEATURE_TREND,"direction over 10 completed bars",owner,"-1..1");
      RegisterFeature("TrendStrength",1,FEATURE_TREND,"directional bar share in percent",owner,"0..100");
      RegisterFeature("CurrentHour",1,FEATURE_TIME,"server hour at the snapshot",owner,"0..23");
      RegisterFeature("Weekday",1,FEATURE_TIME,"server weekday (0=Sunday)",owner,"0..6");
      RegisterFeature("Month",1,FEATURE_TIME,"server month",owner,"1..12");
      RegisterFeature("Quarter",1,FEATURE_TIME,"server quarter",owner,"1..4");
      RegisterFeature("Session",1,FEATURE_SESSION,"Asia/London/NewYork by server hour",owner,"0..2");
      RegisterFeature("BrokerOffset",1,FEATURE_TIME,"hours between server and GMT",owner,"-12..14");
     }

   //--- STEP 4: version manifest for an exported dataset version.
   //--- Pins FeatureVersion + DatasetVersion + LabelVersion + QualityVersion,
   //--- so no exported dataset can be ambiguous about its inputs.
   bool                WriteDatasetManifest(const int dataset_version)
     {
      if(m_db==NULL || !m_db.IsOpen())
         return(false);

      string rows[];
      long quality_id = 0;
      int  quality_status = (int)QUALITY_UNKNOWN;
      if(m_db.Select(StringFormat(
            "SELECT QualityID,QualityStatus FROM %s WHERE DatasetVersion=%d ORDER BY QualityID DESC LIMIT 1",
            DB_TABLE_QUALITY,dataset_version),rows)==1)
        {
         string c[];
         if(StringSplit(rows[0],';',c)==2)
           {
            quality_id     = StringToInteger(c[0]);
            quality_status = (int)StringToInteger(c[1]);
           }
        }

      long feature_count = 0;
      int  feature_version = 0;
      if(m_db.Select(StringFormat(
            "SELECT COUNT(*),MAX(FeatureVersion) FROM %s WHERE Status<>%d",
            DB_TABLE_FEATURES,(int)FEATURE_DEPRECATED),rows)==1)
        {
         string c[];
         if(StringSplit(rows[0],';',c)==2)
           {
            feature_count   = StringToInteger(c[0]);
            feature_version = (int)StringToInteger(c[1]);
           }
        }

      const string file = StringFormat("%s\\dataset_v%d.manifest.txt",
                                       REGISTRY_MANIFEST_DIR,dataset_version);
      const int handle = FileOpen(file,FILE_WRITE|FILE_TXT|FILE_ANSI);
      if(handle==INVALID_HANDLE)
        {
         m_log.Warn(StringFormat("Manifest write failed | %s",file));
         return(false);
        }
      FileWriteString(handle,StringFormat("DatasetVersion=%d\n",dataset_version));
      FileWriteString(handle,StringFormat("FeatureVersion=%d\n",feature_version));
      FileWriteString(handle,StringFormat("FeatureCount=%d\n",feature_count));
      FileWriteString(handle,StringFormat("LabelVersion=%d\n",LABEL_VERSION));
      FileWriteString(handle,StringFormat("QualityVersion=%d\n",quality_id));
      FileWriteString(handle,StringFormat("QualityStatus=%d\n",quality_status));
      FileWriteString(handle,StringFormat("GeneratedAt=%s\n",
                        TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES)));
      FileClose(handle);
      return(true);
     }

   //--- per-tick entry: refresh the manifest once per completed bar
   void                Update(const int dataset_version)
     {
      if(m_db==NULL || !m_db.IsOpen() || m_set==NULL)
         return;
      const datetime bar = iTime(m_set.symbol_name,m_set.main_timeframe,0);
      if(bar<=0 || bar==m_last_manifest)
         return;
      m_last_manifest = bar;
      WriteDatasetManifest(dataset_version);
     }
  };

#endif // __EA_DAL_FEATURE_REGISTRY_MQH__
//+------------------------------------------------------------------+
