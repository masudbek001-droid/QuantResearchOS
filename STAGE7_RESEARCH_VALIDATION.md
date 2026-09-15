# STAGE 7 — Research / Experiment / Benchmark / WalkForward Validation

Date: 2026-09-14

## Status

PASS — CLOSED.

## Scope

Stage 7 validates the research platform engines (`EAResearch/`):

1. **Experiment Engine (`CExperimentEngine`, Task 0016)**:
   - Creation with version pinning (`DatasetVersion`, `FeatureVersion`, `LabelVersion`, `QualityVersion`, `ReplayVersion`).
   - Configuration hash sealing.
   - Lifecycle state machine: `EXPERIMENT_CREATED(0)` → `EXPERIMENT_RUNNING(1)` → `EXPERIMENT_COMPLETED(2)`.
   - Cancellation path: `EXPERIMENT_CANCELLED(3)`.
   - Immutability guard (`IsMutable`): completed experiments are completely sealed against modification.

2. **Benchmark Engine (`CBenchmarkEngine`, Task 0017)**:
   - Deterministic metric calculation over stored trades joined with research datasets.
   - Metrics computed: `WinRate` (%), `ProfitFactor` (ratio), `Expectancy` (money), `AverageTrade` (money), `AverageHoldingTime` (seconds), `MaximumDrawdown` (money), `RecoveryFactor` (ratio), plus placeholder slots (`SharpeRatio`, `SQN`).
   - Re-calculation rejection (idempotence / reproducibility guard).
   - Cross-experiment comparison report generation (`CompareExperiments`).

3. **Walk-Forward Engine (`CWalkForwardEngine`, Task 0018)**:
   - Boundary validation (empty/inverted bounds rejection).
   - Data leakage prevention (`TestingStart < TrainingEnd` guard).
   - Cross-run testing overlap prevention (`NOT (TestingEnd <= start OR TestingStart >= end)`).
   - Window planning (`PlanWindows`) supporting `WF_ROLLING`, `WF_EXPANDING`, and `WF_FIXED`.
   - Run lifecycle tracking (`WF_CREATED` → `WF_RUNNING` → `WF_FINISHED`).

## Findings & Defect Resolution

- **Defect Identified**: In `WalkForwardEngine.mqh` line 49, `ValidateRun()` previously used `if(testing_start <= training_end)`. Because `PlanWindows()` constructs contiguous half-open intervals with `test_start = train_end`, this caused `PlanWindows()` to reject all planned windows on iteration 1.
- **Resolution (DEC-0015)**: Corrected line 49 to `if(testing_start < training_end)`. This strictly forbids any information leakage from the training window into the testing window while correctly accepting contiguous non-overlapping intervals where `TestingStart == TrainingEnd`. Specification in `WALK_FORWARD_ENGINE.md` and `DECISIONS.md` synchronized.

## Harnesses & Binaries

1. **MQL5 Script Harness**:
   - Source: `01_Source/EA/MQL5/Scripts/QuantResearchOS_Stage7Validation.mq5`
   - Active MT5 Binary: `C:\Program Files\MetaTrader\MQL5\Scripts\QuantResearchOS_Stage7Validation.ex5` (59,392 bytes)
   - Compiler Log: `0 errors, 0 warnings` (695 ms)

2. **MQL5 Expert Harness**:
   - Source: `01_Source/EA/MQL5/Experts/QuantResearchOS_Stage7Validation_EA/QuantResearchOS_Stage7Validation_EA.mq5`
   - Active MT5 Binary: `C:\Program Files\MetaTrader\MQL5\Experts\QuantResearchOS_Stage7Validation_EA/QuantResearchOS_Stage7Validation_EA.ex5` (59,104 bytes)
   - Compiler Log: `0 errors, 0 warnings` (814 ms)

3. **Automated Test Suite**:
   - Test Script: `01_Source/Tests/test_stage7_research.py`
   - Isolated Database: `C:\Program Files\MetaTrader\MQL5\Files\candlebreakout_907001.db` (validation magic `907001`)

4. **EA Production Build**:
   - Output: `04_Output/EX5/CandleBreakoutEA.ex5` (207,196 bytes)
   - Compiler Log: `0 errors, 0 warnings`

## 2026-09-14 Reconciliation

- The Stage 7 documentation previously recorded PASS evidence while the script
  source was not present in the project script folder.
- `QuantResearchOS_Stage7Validation.mq5` was restored under
  `01_Source/EA/MQL5/Scripts/` and synchronized to the active MetaTrader
  installation.
- The restored MQL5 script was recompiled with MetaEditor: `0 errors, 0 warnings`;
  generated active binary size is 59,392 bytes.
- The Python research validation suite was re-run against the isolated
  `candlebreakout_907001.db` database and returned PASS.

## Final Runtime Evidence

Execution of `test_stage7_research.py` against `candlebreakout_907001.db`:

- `[PASS] Schema v10/v11 tables present in candlebreakout_907001.db`
- `[PASS] Isolated research tables cleared`
- `[PASS] Seeded 4 mock trades and dataset rows`
- `[PASS] Experiment lifecycle (CREATED -> RUNNING) validated`
- `[PASS] Benchmark computed: WR=75.0%, PF=6.00, Net=100.0, MaxDD=20.0, Recovery=5.00`
- `[PASS] Walk-forward engine: boundary check, leakage rejection, cross-window overlap rejection, PlanWindows (2 windows) validated`
- `[PASS] Experiment sealing and immutability guard verified`
- `[QROS_STAGE7] STATUS=PASS | experiments=2 | benchmarks=9 | wf_runs=4 | immutability=PASS`

Database validation:
- File: `C:\Program Files\MetaTrader\MQL5\Files\candlebreakout_907001.db`
- `PRAGMA integrity_check = ok`
- `Experiments`: 2 rows
- `Benchmarks`: 9 rows (all 7 core metrics + 2 placeholders)
- `WalkForwardRuns`: 4 rows (2 manual test runs + 2 rolling planned windows)
