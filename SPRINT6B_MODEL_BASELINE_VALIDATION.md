# SPRINT 6B — Model Platform & Statistical Baseline Validation

Date: 2026-09-14

## Status

PASS — implemented and hardened; ready for Sprint 7 supervised model training.

## Scope

Sprint 6B validates two recovery objectives:

1. `Models.db` architecture platform readiness.
2. Phase C statistical baseline over historical XAUUSD H1 bars.

## Database Validation

### `CBEA_Models.db`

- Path: `C:\Program Files\MetaTrader\MQL5\Files\CBEA_Models.db`
- Integrity: `PRAGMA integrity_check = ok`
- Schema status: `ModelsSchemaVersion = 2`
- Tables present:
  - `ModelArchitectures`
  - `ModelRegistry`
  - `FeatureVectorContracts`
  - `ModelEvaluations`
  - inherited v11 research tables
- Seeded architectures: 4
  - `LogisticRegression`
  - `RandomForestClassifier`
  - `GradientBoostingClassifier`
  - `ONNXDirectionPredictor`
- Registry rows: 0  *(at Sprint 6B snapshot — after Stage 8: 2 registered models)*
- Feature-vector contract rows: 0  *(after Stage 8: 44 rows, 22 per model)*
- Evaluation rows: 0  *(after Stage 9: 16 rows — 6 initial + 10 walk-forward)*

Empty registry/contract/evaluation tables were expected at Sprint 6B time. They remain empty
until Sprint 7 creates trained model artifacts. **Update 2026-09-15:** Post Stage 8/9 the same `CBEA_Models.db` now holds 2 models, 44 contracts, 16 evaluations (see `STAGE8_SUPERVISED_MODEL_TRAINING.md` / `STAGE9_WALK_FORWARD_VALIDATION.md`). This document is retained as the historical 6B baseline snapshot.

### `CBEA_Market.db`

- Path: `C:\Program Files\MetaTrader\MQL5\Files\CBEA_Market.db`
- Integrity: `PRAGMA integrity_check = ok`
- H1 stored bars: 56,529
- H1 analyzed bars after warmup: 56,514
- H1 coverage: 2016-10-05 00:00 to 2026-09-14 11:00

## Source Validation

- Migration script: `01_Source/Database/migrate_models_v2.py`
- Research script: `06_Tools/statistical_baseline_research.py`
- Report JSON: `04_Output/Statistics/statistical_baseline_report.json`
- Report Markdown: `03_Documents/Reports/STATISTICAL_BASELINE_REPORT.md`

The statistical baseline script was hardened against:

- division-by-zero in profit factor calculations;
- empty-sample means;
- stale fixed sample-size wording.

## Statistical Baseline Result

Clean single-sided breakout baseline:

- Events: 40,566
- Win rate: 54.96%
- Profit factor: 1.945
- Expectancy: +0.793 points
- Average MFE: 3.288 points
- Average MAE: 3.222 points
- MFE/MAE ratio: 1.020

Volatility conditioning:

- Low volatility: 15,914 events, 58.87% win rate, +0.972 expectancy
- Normal volatility: 18,322 events, 53.36% win rate, +0.774 expectancy
- High volatility: 6,330 events, 49.79% win rate, +0.400 expectancy

Top expectancy hours:

1. Hour 12: 63.31% win rate, +1.809 points expectancy
2. Hour 01: 63.72% win rate, +1.664 points expectancy
3. Hour 13: 57.93% win rate, +1.515 points expectancy
4. Hour 05: 62.74% win rate, +1.323 points expectancy
5. Hour 14: 55.09% win rate, +1.226 points expectancy

## Gate Decision

Sprint 6B is internally coherent:

- `Models.db` schema v2 is present and reproducible.
- Historical H1 source data is available and integrity-checked.
- Phase C baseline can be regenerated from source.
- Report JSON and Markdown are synchronized.
- No model is promoted and no live trading behavior is changed.

Next gate: Sprint 7 / Phase D — supervised ML training and walk-forward
cross-validation, using the schema contracts established here.

> **Supersession note 2026-09-15:** Sprint 7/8 executed — see Stages 8–11. Models, ONNX, and walk-forward now PASS; `Models.db` is populated. This 6B report remains the pre-training baseline.
