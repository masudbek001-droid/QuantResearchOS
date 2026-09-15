# ADR-0012 — Research Platform (schema v10: experiments, benchmarks, walk-forward)

*Status: Accepted (approved by Sprint 5: Tasks 0016–0018).*

## Context
The platform records, labels, assembles, quality-gates and replays data. Research now
needs experiment tracking with reproducible input pins, deterministic performance
benchmarks, and walk-forward windowing.

## Decision
1. Raise `DB_SCHEMA_VERSION` to 10 and add three tables in one migration
   (`ApplyMigration("research platform", ddl[5])`):
   * `Experiments` — lifecycle + pinned versions (dataset/feature/label/quality/replay)
     + `ConfigurationHash`;
   * `Benchmarks` — metric rows per experiment (`idx_bench_exp`);
   * `WalkForwardRuns` — windowed runs per experiment (`idx_wf_exp`).
2. New module `MQL5/Include/CandleBreakoutEA/EAResearch/`:
   * `ExperimentEngine.mqh` (Task 0016): `CExperimentEngine` — create/start/finish/
     cancel/get/list; **completed experiments are immutable** via the shared
     `IsMutable()` guard;
   * `BenchmarkEngine.mqh` (Task 0017): `CBenchmarkEngine` — `AddMetric`,
     `CalculateBenchmark` (WinRate, ProfitFactor, Expectancy, AverageTrade,
     AverageHoldingTime, MaximumDrawdown, RecoveryFactor + SharpeRatio/SQN
     placeholders) computed from the pinned dataset's closed trades in fixed order;
     `CompareExperiments` for any pair; `GenerateBenchmarkReport`;
   * `WalkForwardEngine.mqh` (Task 0018): `CWalkForwardEngine` — `CreateRun`,
     `RunWindow`, `FinishRun`, `ValidateRun`, `PlanWindows` for ROLLING / EXPANDING /
     FIXED modes; overlapping testing windows and train/test leakage are rejected.
3. The trade manager initializes the three engines at init only — dormant research
   APIs, zero per-tick work, trading untouched.

## Consequences
* Every experiment result is reproducible: inputs pinned by version + config hash,
  metrics computed deterministically once, windows planned by pure arithmetic.
* Benchmarks are comparable across any two experiments; walk-forward enforces
  out-of-sample discipline at the data layer.
* No AI/ONNX/training/prediction/model registry — research bookkeeping only.
