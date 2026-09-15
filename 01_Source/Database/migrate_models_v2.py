"""
Migration to Models.db Schema v2 (Sprint 6B / ADR-0014)
Creates ModelArchitectures, ModelRegistry, FeatureVectorContracts, ModelEvaluations.
"""
import sqlite3
import os
import datetime

MODELS_DB_PATH = r"C:\Program Files\MetaTrader\MQL5\Files\CBEA_Models.db"

def migrate():
    print(f"Migrating {MODELS_DB_PATH} to Schema v2...")
    if not os.path.exists(MODELS_DB_PATH):
        raise FileNotFoundError(f"Database not found at {MODELS_DB_PATH}")
        
    conn = sqlite3.connect(MODELS_DB_PATH)
    cur = conn.cursor()
    
    # Check current version
    cur.execute("CREATE TABLE IF NOT EXISTS ModelsSchemaVersion (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL)")
    versions = [r[0] for r in cur.execute("SELECT version FROM ModelsSchemaVersion").fetchall()]
    print(f"Current versions: {versions}")
    
    if 2 in versions:
        print("Schema v2 already applied.")
        conn.close()
        return
        
    stamp = datetime.datetime.now().strftime("%Y.%m.%d %H:%M")
    
    # 1. ModelArchitectures
    cur.execute("""
    CREATE TABLE IF NOT EXISTS ModelArchitectures (
        ArchitectureID INTEGER PRIMARY KEY AUTOINCREMENT,
        ArchitectureName TEXT NOT NULL UNIQUE,
        Framework TEXT NOT NULL,
        InputDimension INTEGER NOT NULL,
        OutputDimension INTEGER NOT NULL,
        Description TEXT,
        CreatedAt TEXT NOT NULL
    )
    """)
    
    # 2. ModelRegistry
    cur.execute("""
    CREATE TABLE IF NOT EXISTS ModelRegistry (
        ModelID INTEGER PRIMARY KEY AUTOINCREMENT,
        ModelName TEXT NOT NULL UNIQUE,
        ArchitectureID INTEGER NOT NULL REFERENCES ModelArchitectures(ArchitectureID),
        DatasetVersion INTEGER NOT NULL,
        FeatureVersion INTEGER NOT NULL,
        LabelVersion INTEGER NOT NULL,
        TargetHorizonBars INTEGER NOT NULL DEFAULT 3,
        Status INTEGER NOT NULL DEFAULT 0,
        HyperparametersJson TEXT,
        MetricsJson TEXT,
        ONNXFilePath TEXT,
        ONNXChecksum TEXT,
        CreatedAt TEXT NOT NULL
    )
    """)
    cur.execute("CREATE INDEX IF NOT EXISTS idx_model_status ON ModelRegistry(Status)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_model_dataset ON ModelRegistry(DatasetVersion)")
    
    # 3. FeatureVectorContracts
    cur.execute("""
    CREATE TABLE IF NOT EXISTS FeatureVectorContracts (
        ContractID INTEGER PRIMARY KEY AUTOINCREMENT,
        ModelID INTEGER NOT NULL REFERENCES ModelRegistry(ModelID),
        FeatureIndex INTEGER NOT NULL,
        FeatureName TEXT NOT NULL,
        NormalizationType INTEGER NOT NULL DEFAULT 0,
        Mean REAL,
        StdDev REAL,
        MinVal REAL,
        MaxVal REAL,
        UNIQUE(ModelID, FeatureIndex)
    )
    """)
    cur.execute("CREATE INDEX IF NOT EXISTS idx_contract_model ON FeatureVectorContracts(ModelID)")
    
    # 4. ModelEvaluations
    cur.execute("""
    CREATE TABLE IF NOT EXISTS ModelEvaluations (
        EvaluationID INTEGER PRIMARY KEY AUTOINCREMENT,
        ModelID INTEGER NOT NULL REFERENCES ModelRegistry(ModelID),
        EvaluationType TEXT NOT NULL,
        StartTime INTEGER,
        EndTime INTEGER,
        SampleCount INTEGER NOT NULL,
        Accuracy REAL,
        PrecisionScore REAL,
        RecallScore REAL,
        F1Score REAL,
        BrierScore REAL,
        LogLoss REAL,
        ExpectedValue REAL,
        ProfitFactor REAL,
        MaxDrawdown REAL,
        EvaluatedAt TEXT NOT NULL
    )
    """)
    cur.execute("CREATE INDEX IF NOT EXISTS idx_eval_model ON ModelEvaluations(ModelID)")
    
    # Seed standard baseline architectures
    seed_architectures = [
        ("LogisticRegression", "scikit-learn", 22, 4, "L2-regularized multinomial logistic regression baseline", stamp),
        ("RandomForestClassifier", "scikit-learn", 22, 4, "Ensemble of balanced decision trees", stamp),
        ("GradientBoostingClassifier", "scikit-learn", 22, 4, "Gradient boosted tree classifier with early stopping", stamp),
        ("ONNXDirectionPredictor", "onnx", 22, 4, "Exported ONNX runtime model for MT5 EAContextAI", stamp)
    ]
    cur.executemany("""
    INSERT OR IGNORE INTO ModelArchitectures (ArchitectureName, Framework, InputDimension, OutputDimension, Description, CreatedAt)
    VALUES (?, ?, ?, ?, ?, ?)
    """, seed_architectures)
    
    # Record version
    cur.execute("INSERT INTO ModelsSchemaVersion (version, applied_at) VALUES (2, ?)", (stamp,))
    conn.commit()
    conn.close()
    print("Schema v2 successfully applied to Models.db!")

if __name__ == "__main__":
    migrate()
