# REPLAY ENGINE — `ReplaySessions` (schema v9, TASK 0013)

Part of Sprint 4 under ADR-0011. The Replay Engine replays **recorded history from the
database only** — it never touches broker data and never influences trading.

## 1. Schema

### `ReplaySessions`

`ReplayID` (PK autoinc) · `DatasetVersion` · `SymbolID` · `TimeframeID` · `StartTime` ·
`EndTime` · `CurrentReplayTime` · `ReplayState` · `ReplaySpeed` · `CurrentBar` ·
`TotalBars` · `CreatedAt` + `idx_replay_state(ReplayState)`

Session state is persisted on every transition — a replay is fully reconstructible
from the database alone.

## 2. States & speeds

`REPLAY_STOPPED(0)` → `REPLAY_INITIALIZED(1)` → `REPLAY_RUNNING(2)` ⇄
`REPLAY_PAUSED(3)` → `REPLAY_FINISHED(4)`.

Speeds: `STEP(0)`, `1X`, `2X`, `5X`, `10X`, `25X`, `100X`, `UNLIMITED`.

## 3. Controller — `CReplayController` (`EAReplay/ReplayController.mqh`)

```
long InitializeReplay(dataset_version,symbol_id,timeframe_id,start,end);
bool StartReplay / PauseReplay / ResumeReplay / StopReplay(void);
bool SeekTo(datetime);
bool StepForward / StepBackward(void);
bool SetSpeed(ENUM_REPLAY_SPEED);
void Advance(uint elapsed_ms);      // host-driven clock for RUNNING sessions
```

* `InitializeReplay` passes the full integrity gate (TASK 0015), loads the timeline
  window and registers the session row (`REPLAY_INITIALIZED`).
* Every state transition persists `CurrentReplayTime` / `CurrentBar` / state / speed.
* `Advance()` implements paced playback: `virtual_ms = elapsed_ms × speed`; STEP mode
  ignores the clock (manual `StepForward` only); UNLIMITED drains the window and marks
  the session FINISHED.
* **Automatic stop:** every start/resume/step re-runs the integrity gate — any failure
  forces `REPLAY_STOPPED` and logs the reason.

## 4. Data sources (database only)

`ReplaySessions`, `MarketSnapshots`, `Observations`, `ObservationLabels`, `Trades`,
`ResearchDatasets`, `FeatureRegistry`, `DatasetQuality` — nothing else. The controller
owns a `CReplayTimeline` (playback) and a `CReplayValidator` (integrity).

## 5. Runtime policy

The trade manager initializes the controller at `OnInit` but never starts a replay:
sessions begin only through explicit API calls (future console/UI in later sprints).
Trading behaviour and per-tick runtime are unchanged.
