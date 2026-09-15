# BENCHMARK ENGINE — `Benchmarks` (TASK 0017)

Deterministic performance measurement per experiment, stored in `Benchmarks`
(`BenchmarkID`, `ExperimentID` → Experiments, `MetricName`, `MetricValue`,
`MetricUnit`, `CreatedAt`, `idx_bench_exp`).

## 1. Minimum metric set

| Metric | Definition | Unit |
|---|---|---|
| WinRate | share of closed trades with NetProfit > 0 | % |
| ProfitFactor | gross win / |gross loss| | x |
| Expectancy | net profit / closed trades | money |
| AverageTrade | net profit / closed trades | money |
| AverageHoldingTime | mean(ExitTime − EntryTime) | s |
| MaximumDrawdown | max peak-to-trough of the cumulative net curve | money |
| RecoveryFactor | net / MaximumDrawdown | x |
| SharpeRatio | **placeholder** (0.0) | ratio |
| SQN | **placeholder** (0.0) | pts |

## 2. Determinism

`CalculateBenchmark()` reads the closed trades of the experiment's **pinned dataset
version** (`ResearchDatasets ⋈ Trades`, `ExitTime IS NOT NULL`) in a fixed order
(`ExitTime, TradeID`) — the same stored data always yields identical metrics.
Recomputation is rejected once metrics exist (reproducibility guard), and immutable
(completed/cancelled) experiments accept no metrics at all.

## 3. API — `CBenchmarkEngine`

```
bool AddMetric(experiment_id,name,value,unit);   // mutable experiments only
bool CalculateBenchmark(experiment_id);          // full metric set in one pass
bool CompareExperiments(id_a,id_b,string &report);   // any two experiments
bool GenerateBenchmarkReport(experiment_id,string &report);
```

`CompareExperiments` joins both experiments' metrics by name and emits
`metric: A vs B [unit]` lines — comparison is a pure read, never mutates data.
