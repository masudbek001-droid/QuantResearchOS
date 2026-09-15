# REPLAY VALIDATION & CONSISTENCY (TASK 0015)

`CReplayValidator` (`EAReplay/ReplayValidator.mqh`) protects replay from corrupt or
ambiguous data. Every check is a database query — no broker access.

## 1. Checks

| Method | Detects |
|---|---|
| `ValidateReplayRange` | invalid bounds, empty window (no snapshots) |
| `ValidateDatasetVersion` | empty dataset, dataset that never passed the quality gate (`DatasetQuality.QualityStatus = QUALITY_PASS` required) |
| `ValidateSnapshotContinuity` | **missing snapshots** (row count vs expected `(max−min)/TF + 1`), **duplicate timestamps** (COUNT vs COUNT DISTINCT), broken timeline |
| `ValidateObservationContinuity` | duplicate bar observations, observations not covering every snapshot |
| `ValidateTradeContinuity` | **broken references** (dataset `TradeID` missing in `Trades`), exit before entry |
| `ValidateTimeline` | **out-of-order** / non-increasing loaded timelines |
| `ValidateReplayIntegrity` | the full gate: dataset → range → snapshot → observation → trade |

## 2. Automatic stop

`CReplayController` runs `ValidateReplayIntegrity` before `InitializeReplay`,
`StartReplay`, `ResumeReplay` and after **every** `StepForward`/`StepBackward`. Any
failure forces `REPLAY_STOPPED`, persists the state and logs the reason — a replay can
never continue on broken data.

## 3. Dataset mismatch protection

Replay sessions pin a `DatasetVersion`; trade synchronization only returns trades
referenced by that dataset version, and initialization refuses datasets without a
`QUALITY_PASS` report — a dataset that changed quality status cannot be replayed
under an old session.
