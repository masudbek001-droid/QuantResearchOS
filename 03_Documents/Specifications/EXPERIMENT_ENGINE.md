# EXPERIMENT ENGINE — `Experiments` (schema v10, TASK 0016)

Part of Sprint 5 under ADR-0012. The Experiment Engine tracks research experiments and
**pins every input version**, so any result can be reproduced exactly.

## 1. Schema

### `Experiments`

`ExperimentID` (PK autoinc) · `ExperimentName` · `DatasetVersion` · `FeatureVersion` ·
`LabelVersion` · `QualityVersion` · `ReplayVersion` · `ConfigurationHash` ·
`StartTime` · `EndTime` · `DurationSeconds` · `Status` (`ENUM_EXPERIMENT_STATUS`) ·
`Notes` · `CreatedAt`

`ReplayVersion` is pinned to the schema version at creation (`DB_SCHEMA_VERSION`).
`QualityVersion` is meant to carry the `DatasetQuality.QualityID` the dataset passed
under; `FeatureVersion`/`LabelVersion` come from the registry/label contract.

## 2. Lifecycle

`EXPERIMENT_CREATED(0)` → `EXPERIMENT_RUNNING(1)` → `EXPERIMENT_COMPLETED(2)`
(or `EXPERIMENT_CANCELLED(3)` from CREATED/RUNNING).

**Immutability:** `FinishExperiment()` seals the row — after completion no engine
(experiments, benchmarks, walk-forward) accepts any modification for that experiment
(`IsMutable()` guard shared by all three).

## 3. API — `CExperimentEngine`

```
long CreateExperiment(name,dataset_version,feature_version,label_version,
                      quality_version,config_hash,notes);
bool StartExperiment(id);     // CREATED -> RUNNING, stamps StartTime
bool FinishExperiment(id);    // RUNNING -> COMPLETED, stamps EndTime + Duration
bool CancelExperiment(id);    // CREATED/RUNNING -> CANCELLED
bool GetExperiment(id,SExperimentInfo&);
int  ListExperiments(string &lines[]);
bool IsMutable(id);           // shared guard for the other engines
```

Validation: empty name/hash rejected, non-positive version pins rejected, illegal
transitions rejected (each with a warning log).

## 4. Reproducibility

An experiment row is a complete coordinate system: dataset + feature + label + quality
+ replay versions + configuration hash. Two experiments with identical pins run on
identical data; results are comparable and reproducible.
