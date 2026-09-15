# REPLAY TIMELINE & PLAYBACK ENGINE (TASK 0014)

`CReplayTimeline` (`EAReplay/ReplayTimeline.mqh`) is the deterministic playback core.

## 1. Determinism contract

* The window is loaded **once** with a single ordered query
  (`ORDER BY SnapshotTime ASC`) and kept in memory; playback only walks the array.
* Out-of-order or duplicate timestamps abort the load — a broken window can never be
  replayed.
* No `CopyRates()`, no `iTime/iClose`, no symbol info, no broker call of any kind —
  **the database is the only source**.

## 2. API

```
bool LoadReplayWindow(dataset_version,symbol_id,timeframe_id,start,end);
bool MoveNext(void);  bool MovePrevious(void);
bool JumpToTime(datetime);           // last bar with SnapshotTime <= moment
bool JumpToBar(int index);
bool GetCurrentSnapshot(SReplaySnapshot&);        // 23 recorded fields
bool SynchronizeCurrentObservation(SReplayObservation&);
bool SynchronizeCurrentTrade(SReplayTrade&);      // dataset trade active in the bar
bool SynchronizeCurrentLabel(SReplayLabel&);      // ground truth of the bar
```

`SReplaySnapshot` mirrors the `MarketSnapshots` row exactly; observation/label/trade
synchronization are single indexed lookups keyed by the current bar time and the
dataset version.

## 3. Playback speeds (implemented in the controller's `Advance()`)

| Mode | Behaviour |
|---|---|
| `REPLAY_SPEED_STEP` | no automatic advance — `StepForward()`/`StepBackward()` only |
| `1X…100X` | one bar per `timeframe period / speed` of real time (host-driven) |
| `REPLAY_SPEED_UNLIMITED` | drains the window immediately, session → FINISHED |

## 4. Boundary behaviour

`MoveNext` at the last bar returns false (controller marks FINISHED); `MovePrevious`
at bar 0 returns false; a FINISHED session steps back into PAUSED. Every movement is
persisted through the controller.
