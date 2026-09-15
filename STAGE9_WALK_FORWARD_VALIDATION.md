# STAGE 9 — Walk-Forward Model Validation

Date: 2026-09-14

## Status

PASS — multi-window walk-forward validation completed for the Stage 8 baseline
models.

## Scope

Stage 9 validates that trained supervised baseline models can be evaluated
across chronological historical windows without lookahead leakage.

## Source & Artifacts

- Walk-forward script: `06_Tools/walk_forward_phase_d.py`
- Input feature vectors: `05_Training/FeatureVectors/feature_vectors_v907100.csv`
- Metrics JSON: `05_Training/Metrics/phase_d_walk_forward_v907100.json`
- Model database: `C:\Program Files\MetaTrader\MQL5\Files\CBEA_Models.db`

## Window Plan

- Models evaluated: 2
- Walk-forward windows per model: 5
- Total WF evaluation rows: 10
- Training expands chronologically.
- Test slices are strictly after each training slice.
- No shuffled or future data is used.

## Results

### `QROS_LogisticRegression_Baseline_v1`

- Windows: 5
- Average accuracy: 0.390130
- Average macro F1: 0.363959
- Average log loss: 1.250595

### `QROS_RandomForest_Baseline_v1`

- Windows: 5
- Average accuracy: 0.418278
- Average macro F1: 0.379430
- Average log loss: 1.176918

## Database Validation

`CBEA_Models.db`:

- `PRAGMA integrity_check = ok`
- `ModelEvaluations`: 16 total rows
- `WF_TEST_*` evaluations: 10 rows

## Gate Decision

Stage 9 is closed:

- Walk-forward evaluation pipeline exists.
- Results are reproducible from Stage 8 feature vectors.
- Evaluation rows are stored in `Models.db`.
- Baseline models remain research-only.

Next required gate: MT5-side ONNX loading/inference contract validation in an
isolated script before any EAContextAI integration.
