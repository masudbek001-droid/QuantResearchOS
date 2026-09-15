# WALK-FORWARD ENGINE — `WalkForwardRuns` (TASK 0018)

Window planning and run tracking for walk-forward research, stored in
`WalkForwardRuns` (`RunID`, `ExperimentID` → Experiments, `TrainingStart/End`,
`TestingStart/End`, `WindowNumber`, `ResultStatus`, `CreatedAt`, `idx_wf_exp`).

## 1. Window modes (`ENUM_WF_MODE`)

| Mode | Training window | Advance |
|---|---|---|
| `WF_ROLLING` | fixed length, slides forward | by `test_seconds` |
| `WF_EXPANDING` | start anchored, end grows to the test start | by `test_seconds` |
| `WF_FIXED` | disjoint consecutive train/test blocks | block by block |

`PlanWindows(experiment_id, mode, range_start, range_end, train_seconds,
test_seconds)` generates windows by **pure datetime arithmetic** — fully
deterministic; planning stops at the first rejected window so partial plans stay
reproducible.

## 2. Validation — overlapping windows rejected

`ValidateRun()` rejects:
* invalid/empty bounds;
* **test overlapping its own training window** (`TestingStart < TrainingEnd` —
  leakage guard; contiguous windows `TestingStart = TrainingEnd` are non-overlapping);
* **testing windows overlapping any existing run** of the same experiment
  (`NOT (TestingEnd ≤ start OR TestingStart ≥ end)` must hold) — every test bar
  belongs to at most one window.

Only mutable experiments accept runs; completed experiments are sealed.

## 3. Run lifecycle — `CWalkForwardEngine`

```
long CreateRun(experiment_id,train_start,train_end,test_start,test_end,window_number);
bool RunWindow(run_id);                 // CREATED -> RUNNING
bool FinishRun(run_id,success);         // RUNNING -> FINISHED / FAILED
bool ValidateRun(experiment_id,...);
int  PlanWindows(experiment_id,mode,range_start,range_end,train_s,test_s);
```

Run states: `WF_CREATED(0)` → `WF_RUNNING(1)` → `WF_FINISHED(2)` / `WF_FAILED(3)`;
window numbers auto-increment per experiment when not given explicitly.
