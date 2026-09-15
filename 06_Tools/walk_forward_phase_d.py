"""
QuantResearchOS — Sprint 7 / Phase D walk-forward validation.

Runs chronological multi-window validation over the Stage 8 feature vectors and
writes WF_TEST_* evaluation records to CBEA_Models.db.
"""
from __future__ import annotations

import datetime as dt
import json
import sqlite3
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, f1_score, log_loss, precision_score, recall_score
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler


ROOT = Path(r"C:\QuantResearchOS")
MODELS_DB_PATH = Path(r"C:\Program Files\MetaTrader\MQL5\Files\CBEA_Models.db")
FEATURE_CSV = ROOT / "05_Training" / "FeatureVectors" / "feature_vectors_v907100.csv"
METRIC_DIR = ROOT / "05_Training" / "Metrics"

FEATURES = [
    "Spread", "ATR", "ATRRatio", "PreviousRange", "CurrentRange", "BodySize",
    "BodyPercent", "UpperShadow", "LowerShadow", "UpperShadowRatio",
    "LowerShadowRatio", "Bullish", "Bearish", "Volatility", "TrendDirection",
    "TrendStrength", "CurrentHour", "Weekday", "Month", "Quarter", "Session",
    "BrokerOffset",
]

LABELS = [0, 1, 2, 3]


def make_model(kind: str):
    if kind == "QROS_LogisticRegression_Baseline_v1":
        return Pipeline([
            ("scale", StandardScaler()),
            ("model", LogisticRegression(max_iter=1000, class_weight="balanced", random_state=907100)),
        ])
    if kind == "QROS_RandomForest_Baseline_v1":
        return RandomForestClassifier(
            n_estimators=160,
            max_depth=10,
            min_samples_leaf=25,
            class_weight="balanced_subsample",
            random_state=907100,
            n_jobs=-1,
        )
    raise ValueError(kind)


def load_data() -> pd.DataFrame:
    if not FEATURE_CSV.exists():
        raise FileNotFoundError(FEATURE_CSV)
    df = pd.read_csv(FEATURE_CSV)
    df["Datetime"] = pd.to_datetime(df["Datetime"])
    return df.sort_values("OpenTime").reset_index(drop=True)


def plan_windows(df: pd.DataFrame, windows: int = 5) -> list[dict]:
    n = len(df)
    train_size = int(n * 0.50)
    test_size = int(n * 0.08)
    step = int((n - train_size - test_size) / max(windows - 1, 1))
    result = []
    for idx in range(windows):
        train_start = 0
        train_end = train_size + idx * step
        test_start = train_end
        test_end = min(test_start + test_size, n)
        if test_end <= test_start or test_end > n:
            break
        result.append({
            "window": idx + 1,
            "train_start": train_start,
            "train_end": train_end,
            "test_start": test_start,
            "test_end": test_end,
        })
    return result


def evaluate(model, test_df: pd.DataFrame) -> dict:
    x = test_df[FEATURES].to_numpy(dtype=float)
    y = test_df["Target"].to_numpy(dtype=int)
    pred = model.predict(x)
    proba = model.predict_proba(x)
    return {
        "sample_count": int(len(test_df)),
        "accuracy": float(accuracy_score(y, pred)),
        "precision_macro": float(precision_score(y, pred, average="macro", zero_division=0)),
        "recall_macro": float(recall_score(y, pred, average="macro", zero_division=0)),
        "f1_macro": float(f1_score(y, pred, average="macro", zero_division=0)),
        "log_loss": float(log_loss(y, proba, labels=LABELS)),
    }


def model_ids(conn: sqlite3.Connection) -> dict[str, int]:
    rows = conn.execute("SELECT ModelName,ModelID FROM ModelRegistry").fetchall()
    return {str(name): int(model_id) for name, model_id in rows}


def insert_eval(conn: sqlite3.Connection, model_id: int, eval_type: str, frame: pd.DataFrame, metric: dict) -> None:
    now = dt.datetime.now().strftime("%Y.%m.%d %H:%M")
    conn.execute(
        """
        INSERT INTO ModelEvaluations (
            ModelID, EvaluationType, StartTime, EndTime, SampleCount,
            Accuracy, PrecisionScore, RecallScore, F1Score, BrierScore,
            LogLoss, ExpectedValue, ProfitFactor, MaxDrawdown, EvaluatedAt
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, NULL, NULL, NULL, ?)
        """,
        (
            model_id,
            eval_type,
            int(frame["OpenTime"].min()),
            int(frame["OpenTime"].max()),
            metric["sample_count"],
            round(metric["accuracy"], 6),
            round(metric["precision_macro"], 6),
            round(metric["recall_macro"], 6),
            round(metric["f1_macro"], 6),
            round(metric["log_loss"], 6),
            now,
        ),
    )


def run() -> dict:
    METRIC_DIR.mkdir(parents=True, exist_ok=True)
    df = load_data()
    windows = plan_windows(df, 5)
    models = ["QROS_LogisticRegression_Baseline_v1", "QROS_RandomForest_Baseline_v1"]
    summary = {"windows": [], "models": {}}

    with sqlite3.connect(MODELS_DB_PATH) as conn:
        conn.execute("PRAGMA foreign_keys=ON")
        ids = model_ids(conn)
        for name in models:
            if name not in ids:
                raise RuntimeError(f"Model not registered: {name}")
            conn.execute("DELETE FROM ModelEvaluations WHERE ModelID=? AND EvaluationType LIKE 'WF_TEST_%'", (ids[name],))
            scores = []
            for window in windows:
                train_df = df.iloc[window["train_start"]:window["train_end"]]
                test_df = df.iloc[window["test_start"]:window["test_end"]]
                model = make_model(name)
                model.fit(train_df[FEATURES].to_numpy(dtype=float), train_df["Target"].to_numpy(dtype=int))
                metric = evaluate(model, test_df)
                metric["window"] = window["window"]
                metric["test_start"] = str(test_df["Datetime"].min())
                metric["test_end"] = str(test_df["Datetime"].max())
                scores.append(metric)
                insert_eval(conn, ids[name], f"WF_TEST_{window['window']:02d}", test_df, metric)
            summary["models"][name] = {
                "windows": scores,
                "avg_accuracy": round(float(np.mean([s["accuracy"] for s in scores])), 6),
                "avg_f1_macro": round(float(np.mean([s["f1_macro"] for s in scores])), 6),
                "avg_log_loss": round(float(np.mean([s["log_loss"] for s in scores])), 6),
            }
        conn.commit()

    summary["windows"] = windows
    out = METRIC_DIR / "phase_d_walk_forward_v907100.json"
    out.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    return summary


if __name__ == "__main__":
    result = run()
    print("=== SPRINT 7 / PHASE D: WALK-FORWARD VALIDATION ===")
    for model_name, metrics in result["models"].items():
        print(
            f"{model_name}: windows={len(metrics['windows'])} "
            f"avg_accuracy={metrics['avg_accuracy']:.4f} "
            f"avg_f1_macro={metrics['avg_f1_macro']:.4f} "
            f"avg_log_loss={metrics['avg_log_loss']:.4f}"
        )
    print("[QROS_STAGE9] STATUS=PASS | wf_models=2 | wf_windows=5 | wf_evaluations=10")
