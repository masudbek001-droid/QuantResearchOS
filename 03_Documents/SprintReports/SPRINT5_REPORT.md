# SPRINT 5 REPORT — Research Platform (Tasks 0016–0018)

## 1. Database version

`DB_SCHEMA_VERSION = 10` (was 9). Chain `1→…→9→10`, single migration
`ApplyMigration("research platform", ddl[5])`: tables `Experiments`, `Benchmarks`,
`WalkForwardRuns` + indexes `idx_bench_exp`, `idx_wf_exp`.

## 2. TASK 0016 — Experiment Engine

* `Experiments`: ExperimentID (PK), ExperimentName, DatasetVersion, FeatureVersion,
  LabelVersion, QualityVersion, ReplayVersion, ConfigurationHash, StartTime, EndTime,
  DurationSeconds, Status, Notes, CreatedAt.
* `ENUM_EXPERIMENT_STATUS`: CREATED(0) / RUNNING(1) / COMPLETED(2) / CANCELLED(3).
* `CExperimentEngine`: `CreateExperiment()` (rejects empty name/hash, non-positive
  pins), `StartExperiment()`, `FinishExperiment()` (stamps EndTime+Duration, **seals
  the row**), `CancelExperiment()`, `GetExperiment()`, `ListExperiments()`;
  `IsMutable()` shared guard → **completed experiments are immutable**.

## 3. TASK 0017 — Benchmark Engine

* `Benchmarks`: BenchmarkID (PK), ExperimentID (FK), MetricName, MetricValue,
  MetricUnit, CreatedAt.
* `CBenchmarkEngine`: `AddMetric()` (mutable experiments only),
  `CalculateBenchmark()` — WinRate, ProfitFactor, Expectancy, AverageTrade,
  AverageHoldingTime, MaximumDrawdown, RecoveryFactor + **SharpeRatio/SQN
  placeholders** — computed from the pinned dataset's closed trades
  (`ORDER BY ExitTime, TradeID`), one-shot (recomputation rejected);
  `CompareExperiments()` (any two experiments), `GenerateBenchmarkReport()`.

## 4. TASK 0018 — Walk-Forward Engine

* `WalkForwardRuns`: RunID (PK), ExperimentID (FK), TrainingStart/End, TestingStart/
  End, WindowNumber, ResultStatus (WF_CREATED/RUNNING/FINISHED/FAILED), CreatedAt.
* `CWalkForwardEngine`: `CreateRun()`, `RunWindow()`, `FinishRun()`, `ValidateRun()`,
  `PlanWindows()` supporting **Rolling / Expanding / Fixed** windows.
* Validation rejects: overlapping testing windows across runs of an experiment, test
  windows overlapping their own training window (leakage), empty/invalid bounds;
  immutable experiments accept no runs.

## 5. Files created

| File | Purpose |
|---|---|
| `MQL5/Include/CandleBreakoutEA/EAResearch/ExperimentEngine.mqh` | Task 0016 |
| `EAResearch/BenchmarkEngine.mqh` | Task 0017 |
| `EAResearch/WalkForwardEngine.mqh` | Task 0018 |
| `EXPERIMENT_ENGINE.md`, `BENCHMARK_ENGINE.md`, `WALK_FORWARD_ENGINE.md` | module docs |
| `docs/adr/ADR-0012-research-platform.md` | decision record |

## 6. Files modified (additive only)

| File | Change |
|---|---|
| `EAData/DatabaseTypes.mqh` | `DB_SCHEMA_VERSION 10`, 3 table constants, experiment/WF enums |
| `EAData/DatabaseSchema.mqh` | `MigrationToV10(ddl[])` |
| `EAData/DatabaseVersion.mqh` | `EnsureVersion` chain `1→…→10` |
| `EATradeManager.mqh` | +3 includes, +3 members, `Initialize` calls in `Init` (dormant APIs) |
| `README.md`, `tools/build_manual.py` (+PDF) | tree (45 headers), counts (8 405 lines), binary size |

Trading, entry/exit engines, Context Layer, Feature Builder, Observation/Label/
Dataset/Quality engines, Replay, Feature Registry: untouched.

## 7. Validation results

* `VERDICT: PASS - 0 errors, 0 warnings` (190 714 B binary).
* Trading behaviour and runtime unchanged; research engines are dormant APIs.
* Replay and dataset pipelines unchanged.
* All experiment data reproducible (version pins + config hash + one-shot metrics).
* Benchmarks deterministic (fixed-order computation over stored rows).
* Walk-forward deterministic (pure datetime arithmetic, overlap/leakage rejection).

## 8. Not implemented (per stop condition)

AI, ONNX, model training, Event Bus, prediction, model registry,
champion/challenger. **Waiting for Sprint 6.**
