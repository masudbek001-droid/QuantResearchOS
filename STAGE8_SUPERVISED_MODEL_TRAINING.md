# STAGE 8 — Supervised Model Training / Phase D Validation

Date: 2026-09-14

## Status

PASS — supervised baseline models trained, exported to ONNX, checked, and
registered. No live trading behavior was changed.

## Scope

Stage 8 validates the first Sprint 7 / Phase D training pass:

1. Build point-in-time XAUUSD H1 feature vectors from `CBEA_Market.db`.
2. Use the official 22-feature `SFeatureSnapshot` order as the model contract.
3. Train local scikit-learn supervised baseline classifiers.
4. Register trained artifacts, feature-vector contracts, and evaluation metrics
   in `CBEA_Models.db`.

## Source & Artifacts

- Training script: `06_Tools/train_phase_d_models.py`
- Feature vectors: `05_Training/FeatureVectors/feature_vectors_v907100.csv`
- Metrics JSON: `05_Training/Metrics/phase_d_supervised_baseline_v907100.json`
- Logistic Regression model: `05_Training/Models/QROS_LogisticRegression_Baseline_v1.joblib`
- Random Forest model: `05_Training/Models/QROS_RandomForest_Baseline_v1.joblib`
- Logistic Regression ONNX: `05_Training/ONNX/QROS_LogisticRegression_Baseline_v1.onnx`
- Random Forest ONNX: `05_Training/ONNX/QROS_RandomForest_Baseline_v1.onnx`
- Model database: `C:\Program Files\MetaTrader\MQL5\Files\CBEA_Models.db`

## Dataset

- DatasetVersion: 907100
- FeatureVersion: 1
- LabelVersion: 1
- Target horizon: 1 H1 bar
- Total rows: 56,499
- Train rows: 39,549
- Validation rows: 8,475
- Test rows: 8,475
- Date range: 2016-10-23 00:00 to 2026-09-14 11:00

## Feature Vector Contract

The following 22 features are registered in deterministic order for every model:

0. `Spread`
1. `ATR`
2. `ATRRatio`
3. `PreviousRange`
4. `CurrentRange`
5. `BodySize`
6. `BodyPercent`
7. `UpperShadow`
8. `LowerShadow`
9. `UpperShadowRatio`
10. `LowerShadowRatio`
11. `Bullish`
12. `Bearish`
13. `Volatility`
14. `TrendDirection`
15. `TrendStrength`
16. `CurrentHour`
17. `Weekday`
18. `Month`
19. `Quarter`
20. `Session`
21. `BrokerOffset`

## Trained Baseline Models

### `QROS_LogisticRegression_Baseline_v1`

- Artifact: `05_Training/Models/QROS_LogisticRegression_Baseline_v1.joblib`
- Test accuracy: 0.454159
- Test macro F1: 0.359607
- Test log loss: 1.206280

### `QROS_RandomForest_Baseline_v1`

- Artifact: `05_Training/Models/QROS_RandomForest_Baseline_v1.joblib`
- Test accuracy: 0.455693
- Test macro F1: 0.354055
- Test log loss: 1.142387

## Database Validation

`CBEA_Models.db`:

- `PRAGMA integrity_check = ok`
- `ModelsSchemaVersion`: 2
- `ModelArchitectures`: 4
- `ModelRegistry`: 2
- `FeatureVectorContracts`: 44
- `ModelEvaluations`: 6
- ONNX checker: OK for both exported models

## Gate Decision

Stage 8 is closed for supervised baseline training:

- Feature-vector contracts are now materialized.
- Trained local baseline artifacts exist.
- ONNX artifacts exist and pass `onnx.checker.check_model`.
- Models are registered as candidate records in `Models.db`.
- Evaluation rows are stored for train, validation, and test splits.

Next required work:

1. Add walk-forward cross-validation over multiple historical windows.
2. Validate MT5-side ONNX loading/inference contract in a script harness.
3. Only after ONNX + WF validation passes, evaluate EAContextAI integration.
