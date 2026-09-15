"""
QuantResearchOS — Sprint 7 / Phase D supervised baseline training.

Builds point-in-time feature vectors from CBEA_Market.db H1 bars, trains local
scikit-learn baseline classifiers, writes reproducible model artifacts under
05_Training, and registers results in CBEA_Models.db schema v2.
"""
from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
import sqlite3
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
import onnx
from skl2onnx import convert_sklearn
from skl2onnx.common.data_types import FloatTensorType
from sklearn.ensemble import RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    accuracy_score,
    brier_score_loss,
    f1_score,
    log_loss,
    precision_score,
    recall_score,
)
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler


ROOT = Path(r"C:\QuantResearchOS")
MARKET_DB_PATH = Path(r"C:\Program Files\MetaTrader\MQL5\Files\CBEA_Market.db")
MODELS_DB_PATH = Path(r"C:\Program Files\MetaTrader\MQL5\Files\CBEA_Models.db")
MODEL_DIR = ROOT / "05_Training" / "Models"
FEATURE_DIR = ROOT / "05_Training" / "FeatureVectors"
METRIC_DIR = ROOT / "05_Training" / "Metrics"
ONNX_DIR = ROOT / "05_Training" / "ONNX"

DATASET_VERSION = 907100
FEATURE_VERSION = 1
LABEL_VERSION = 1
TARGET_HORIZON_BARS = 1
TIMEFRAME_ID_H1 = 16385

FEATURES = [
    "Spread",
    "ATR",
    "ATRRatio",
    "PreviousRange",
    "CurrentRange",
    "BodySize",
    "BodyPercent",
    "UpperShadow",
    "LowerShadow",
    "UpperShadowRatio",
    "LowerShadowRatio",
    "Bullish",
    "Bearish",
    "Volatility",
    "TrendDirection",
    "TrendStrength",
    "CurrentHour",
    "Weekday",
    "Month",
    "Quarter",
    "Session",
    "BrokerOffset",
]

LABEL_NAMES = {
    0: "RANGE",
    1: "UP",
    2: "DOWN",
    3: "FAKE_BREAKOUT",
}


def ensure_dirs() -> None:
    for folder in [MODEL_DIR, FEATURE_DIR, METRIC_DIR, ONNX_DIR]:
        folder.mkdir(parents=True, exist_ok=True)


def load_h1_bars() -> pd.DataFrame:
    if not MARKET_DB_PATH.exists():
        raise FileNotFoundError(MARKET_DB_PATH)
    with sqlite3.connect(MARKET_DB_PATH) as conn:
        df = pd.read_sql_query(
            """
            SELECT OpenTime, Open, High, Low, Close, TickVolume, Spread
            FROM Bars
            WHERE TimeframeID = ?
            ORDER BY OpenTime ASC
            """,
            conn,
            params=(TIMEFRAME_ID_H1,),
        )
    if df.empty:
        raise RuntimeError("No H1 bars found in CBEA_Market.db")
    df["Datetime"] = pd.to_datetime(df["OpenTime"], unit="s")
    return df


def session_from_hour(hour: int) -> int:
    if 0 <= hour < 8:
        return 0
    if 8 <= hour < 15:
        return 1
    return 2


def build_feature_frame(df: pd.DataFrame) -> pd.DataFrame:
    out = df.copy()
    out["Prev_Open"] = out["Open"].shift(1)
    out["Prev_High"] = out["High"].shift(1)
    out["Prev_Low"] = out["Low"].shift(1)
    out["Prev_Close"] = out["Close"].shift(1)
    out["Prev2_High"] = out["High"].shift(2)
    out["Prev2_Low"] = out["Low"].shift(2)

    out["PreviousRange"] = out["Prev2_High"] - out["Prev2_Low"]
    out["CurrentRange"] = out["Prev_High"] - out["Prev_Low"]
    out["BodySize"] = (out["Prev_Close"] - out["Prev_Open"]).abs()
    out["BodyPercent"] = np.where(
        out["CurrentRange"] > 0.0,
        out["BodySize"] / out["CurrentRange"] * 100.0,
        0.0,
    )
    out["UpperShadow"] = out["Prev_High"] - np.maximum(out["Prev_Open"], out["Prev_Close"])
    out["LowerShadow"] = np.minimum(out["Prev_Open"], out["Prev_Close"]) - out["Prev_Low"]
    out["UpperShadowRatio"] = np.where(out["CurrentRange"] > 0.0, out["UpperShadow"] / out["CurrentRange"], 0.0)
    out["LowerShadowRatio"] = np.where(out["CurrentRange"] > 0.0, out["LowerShadow"] / out["CurrentRange"], 0.0)
    out["Bullish"] = (out["Prev_Close"] > out["Prev_Open"]).astype(int)
    out["Bearish"] = (out["Prev_Close"] < out["Prev_Open"]).astype(int)

    tr = np.maximum(
        out["High"] - out["Low"],
        np.maximum((out["High"] - out["Close"].shift(1)).abs(), (out["Low"] - out["Close"].shift(1)).abs()),
    )
    out["ATR"] = tr.rolling(14).mean().shift(1)
    out["ATRRatio"] = np.where(out["ATR"] > 0.0, out["CurrentRange"] / out["ATR"], 1.0)
    out["Volatility"] = out["ATR"]

    trend_delta = out["Close"].shift(1) - out["Close"].shift(11)
    out["TrendDirection"] = np.sign(trend_delta).fillna(0).astype(int)
    up_bars = (out["Close"].shift(1) > out["Open"].shift(1)).rolling(10).sum()
    down_bars = (out["Close"].shift(1) < out["Open"].shift(1)).rolling(10).sum()
    out["TrendStrength"] = np.maximum(up_bars, down_bars) / 10.0 * 100.0

    out["CurrentHour"] = out["Datetime"].dt.hour
    out["Weekday"] = out["Datetime"].dt.weekday
    out["Month"] = out["Datetime"].dt.month
    out["Quarter"] = out["Datetime"].dt.quarter
    out["Session"] = out["CurrentHour"].apply(session_from_hour)
    out["BrokerOffset"] = 0
    out["Spread"] = out["Spread"].fillna(0)

    buy = out["High"] >= out["Prev_High"]
    sell = out["Low"] <= out["Prev_Low"]
    up = buy & ~sell & (out["Close"] > out["Prev_High"])
    down = sell & ~buy & (out["Close"] < out["Prev_Low"])
    fake = buy & sell
    out["Target"] = np.select([up, down, fake], [1, 2, 3], default=0).astype(int)

    clean = out.dropna(subset=FEATURES + ["Target"]).copy()
    clean = clean.iloc[15:].copy()
    return clean


def time_split(data: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    n = len(data)
    train_end = int(n * 0.70)
    valid_end = int(n * 0.85)
    return data.iloc[:train_end].copy(), data.iloc[train_end:valid_end].copy(), data.iloc[valid_end:].copy()


def multiclass_brier(y_true: np.ndarray, proba: np.ndarray, classes: np.ndarray) -> float:
    values = []
    for idx, cls in enumerate(classes):
        values.append(brier_score_loss((y_true == cls).astype(int), proba[:, idx]))
    return float(np.mean(values)) if values else 0.0


def evaluate_model(model, data: pd.DataFrame, split_name: str) -> dict:
    x = data[FEATURES].to_numpy(dtype=float)
    y = data["Target"].to_numpy(dtype=int)
    pred = model.predict(x)
    proba = model.predict_proba(x)
    labels = sorted(LABEL_NAMES.keys())
    return {
        "split": split_name,
        "sample_count": int(len(data)),
        "accuracy": round(float(accuracy_score(y, pred)), 6),
        "precision_macro": round(float(precision_score(y, pred, average="macro", zero_division=0)), 6),
        "recall_macro": round(float(recall_score(y, pred, average="macro", zero_division=0)), 6),
        "f1_macro": round(float(f1_score(y, pred, average="macro", zero_division=0)), 6),
        "brier": round(multiclass_brier(y, proba, model.classes_), 6),
        "log_loss": round(float(log_loss(y, proba, labels=labels)), 6),
        "class_distribution": {LABEL_NAMES[int(k)]: int(v) for k, v in data["Target"].value_counts().sort_index().items()},
    }


def file_sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def architecture_id(conn: sqlite3.Connection, name: str) -> int:
    row = conn.execute("SELECT ArchitectureID FROM ModelArchitectures WHERE ArchitectureName=?", (name,)).fetchone()
    if not row:
        raise RuntimeError(f"Missing model architecture: {name}")
    return int(row[0])


def upsert_model_registry(conn: sqlite3.Connection, name: str, arch_name: str, hyper: dict, metrics: dict, model_path: Path) -> int:
    now = dt.datetime.now().strftime("%Y.%m.%d %H:%M")
    checksum = file_sha256(model_path)
    arch_id = architecture_id(conn, arch_name)
    conn.execute(
        "DELETE FROM FeatureVectorContracts WHERE ModelID IN (SELECT ModelID FROM ModelRegistry WHERE ModelName=?)",
        (name,),
    )
    conn.execute("DELETE FROM ModelEvaluations WHERE ModelID IN (SELECT ModelID FROM ModelRegistry WHERE ModelName=?)", (name,))
    conn.execute("DELETE FROM ModelRegistry WHERE ModelName=?", (name,))
    cur = conn.execute(
        """
        INSERT INTO ModelRegistry (
            ModelName, ArchitectureID, DatasetVersion, FeatureVersion, LabelVersion,
            TargetHorizonBars, Status, HyperparametersJson, MetricsJson,
            ONNXFilePath, ONNXChecksum, CreatedAt
        ) VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?, ?)
        """,
        (
            name,
            arch_id,
            DATASET_VERSION,
            FEATURE_VERSION,
            LABEL_VERSION,
            TARGET_HORIZON_BARS,
            json.dumps(hyper, sort_keys=True),
            json.dumps(metrics, sort_keys=True),
            str(model_path),
            checksum,
            now,
        ),
    )
    model_id = int(cur.lastrowid)
    for index, feature in enumerate(FEATURES):
        conn.execute(
            """
            INSERT INTO FeatureVectorContracts (
                ModelID, FeatureIndex, FeatureName, NormalizationType,
                Mean, StdDev, MinVal, MaxVal
            ) VALUES (?, ?, ?, ?, NULL, NULL, NULL, NULL)
            """,
            (model_id, index, feature, 1 if arch_name == "LogisticRegression" else 0),
        )
    return model_id


def insert_evaluations(conn: sqlite3.Connection, model_id: int, data: pd.DataFrame, metrics: list[dict]) -> None:
    now = dt.datetime.now().strftime("%Y.%m.%d %H:%M")
    for metric in metrics:
        split_data = data[metric["split_name"]]
        conn.execute(
            """
            INSERT INTO ModelEvaluations (
                ModelID, EvaluationType, StartTime, EndTime, SampleCount,
                Accuracy, PrecisionScore, RecallScore, F1Score, BrierScore,
                LogLoss, ExpectedValue, ProfitFactor, MaxDrawdown, EvaluatedAt
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL, ?)
            """,
            (
                model_id,
                metric["split"],
                int(split_data["OpenTime"].min()),
                int(split_data["OpenTime"].max()),
                metric["sample_count"],
                metric["accuracy"],
                metric["precision_macro"],
                metric["recall_macro"],
                metric["f1_macro"],
                metric["brier"],
                metric["log_loss"],
                now,
            ),
        )


def train() -> dict:
    ensure_dirs()
    bars = load_h1_bars()
    dataset = build_feature_frame(bars)
    train_df, valid_df, test_df = time_split(dataset)
    feature_csv = FEATURE_DIR / f"feature_vectors_v{DATASET_VERSION}.csv"
    dataset[["OpenTime", "Datetime", "Target"] + FEATURES].to_csv(feature_csv, index=False)

    candidates = [
        (
            "QROS_LogisticRegression_Baseline_v1",
            "LogisticRegression",
            Pipeline(
                [
                    ("scale", StandardScaler()),
                    ("model", LogisticRegression(max_iter=1000, class_weight="balanced", random_state=907100)),
                ]
            ),
            {"max_iter": 1000, "class_weight": "balanced", "random_state": 907100},
        ),
        (
            "QROS_RandomForest_Baseline_v1",
            "RandomForestClassifier",
            RandomForestClassifier(
                n_estimators=160,
                max_depth=10,
                min_samples_leaf=25,
                class_weight="balanced_subsample",
                random_state=907100,
                n_jobs=-1,
            ),
            {
                "n_estimators": 160,
                "max_depth": 10,
                "min_samples_leaf": 25,
                "class_weight": "balanced_subsample",
                "random_state": 907100,
            },
        ),
    ]

    summary = {
        "dataset_version": DATASET_VERSION,
        "feature_version": FEATURE_VERSION,
        "label_version": LABEL_VERSION,
        "target_horizon_bars": TARGET_HORIZON_BARS,
        "feature_count": len(FEATURES),
        "features": FEATURES,
        "label_names": LABEL_NAMES,
        "rows": {
            "total": int(len(dataset)),
            "train": int(len(train_df)),
            "validation": int(len(valid_df)),
            "test": int(len(test_df)),
        },
        "date_range": {
            "start": str(dataset["Datetime"].min()),
            "end": str(dataset["Datetime"].max()),
        },
        "models": [],
        "onnx_export": "PASS",
    }

    split_map = {"TRAIN": train_df, "VALIDATION": valid_df, "TEST": test_df}
    x_train = train_df[FEATURES].to_numpy(dtype=float)
    y_train = train_df["Target"].to_numpy(dtype=int)

    with sqlite3.connect(MODELS_DB_PATH) as conn:
        conn.execute("PRAGMA foreign_keys=ON")
        for model_name, arch_name, model, hyper in candidates:
            model.fit(x_train, y_train)
            model_path = MODEL_DIR / f"{model_name}.joblib"
            joblib.dump({"model": model, "features": FEATURES, "labels": LABEL_NAMES}, model_path)
            onnx_path = ONNX_DIR / f"{model_name}.onnx"
            initial_types = [("float_input", FloatTensorType([None, len(FEATURES)]))]
            onnx_model = convert_sklearn(
                model,
                initial_types=initial_types,
                target_opset=12,
                options={id(model): {"zipmap": False}},
            )
            onnx.save_model(onnx_model, onnx_path)

            evals = [
                {"split": "TRAIN", "split_name": "TRAIN", **evaluate_model(model, train_df, "TRAIN")},
                {"split": "VALIDATION", "split_name": "VALIDATION", **evaluate_model(model, valid_df, "VALIDATION")},
                {"split": "TEST", "split_name": "TEST", **evaluate_model(model, test_df, "TEST")},
            ]
            compact_evals = [{k: v for k, v in item.items() if k != "split_name"} for item in evals]
            model_record = {
                "model_name": model_name,
                "architecture": arch_name,
                "artifact": str(model_path),
                "onnx_artifact": str(onnx_path),
                "sha256": file_sha256(model_path),
                "onnx_sha256": file_sha256(onnx_path),
                "hyperparameters": hyper,
                "evaluations": compact_evals,
            }
            model_id = upsert_model_registry(conn, model_name, arch_name, hyper, model_record, onnx_path)
            insert_evaluations(conn, model_id, split_map, evals)
            summary["models"].append({"model_id": model_id, **model_record})
        conn.commit()

    metrics_path = METRIC_DIR / f"phase_d_supervised_baseline_v{DATASET_VERSION}.json"
    metrics_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    return summary


if __name__ == "__main__":
    result = train()
    print("=== SPRINT 7 / PHASE D: SUPERVISED BASELINE TRAINING ===")
    print(f"Rows: total={result['rows']['total']:,} train={result['rows']['train']:,} validation={result['rows']['validation']:,} test={result['rows']['test']:,}")
    print(f"Date range: {result['date_range']['start']} .. {result['date_range']['end']}")
    for model in result["models"]:
        test = next(e for e in model["evaluations"] if e["split"] == "TEST")
        print(f"{model['model_name']}: TEST accuracy={test['accuracy']:.4f} f1_macro={test['f1_macro']:.4f} log_loss={test['log_loss']:.4f}")
    print("[QROS_STAGE8] STATUS=PASS | supervised_baselines=2 | feature_contracts=44 | evaluations=6 | onnx=PASS")
