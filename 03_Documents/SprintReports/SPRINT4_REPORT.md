# SPRINT 4 REPORT — Replay Foundation (Tasks 0013–0015)

## 1. Database version

`DB_SCHEMA_VERSION = 9` (was 8). Chain `1→…→8→9`, migration
`ApplyMigration("replay foundation", ddl[2])`: table `ReplaySessions` +
`idx_replay_state`.

## 2. TASK 0013 — Replay Engine Foundation

* `ReplaySessions`: ReplayID (PK), DatasetVersion, SymbolID, TimeframeID, StartTime,
  EndTime, CurrentReplayTime, ReplayState, ReplaySpeed, CurrentBar, TotalBars,
  CreatedAt.
* `ENUM_REPLAY_STATE`: STOPPED / INITIALIZED / RUNNING / PAUSED / FINISHED.
* `CReplayController`: `InitializeReplay()` (integrity-gated, registers session),
  `StartReplay()` / `PauseReplay()` / `ResumeReplay()` / `StopReplay()`,
  `SeekTo()`, `StepForward()` / `StepBackward()`, `SetSpeed()`, `Advance(elapsed_ms)`.
  Every transition persists state to the database.

## 3. TASK 0014 — Replay Timeline & Playback

* `CReplayTimeline`: `LoadReplayWindow()` (single ordered SELECT, in-memory),
  `MoveNext/MovePrevious`, `JumpToTime/JumpToBar`, `GetCurrentSnapshot()` (23 recorded
  fields), `SynchronizeCurrentObservation/Trade/Label()`.
* Deterministic: fixed order, load aborts on duplicates/out-of-order rows.
* **Database-only**: no `CopyRates()`, no broker/symbol calls anywhere in `EAReplay/`.
* Speeds: 1x, 2x, 5x, 10x, 25x, 100x, Unlimited, Step mode (manual).

## 4. TASK 0015 — Replay Validation & Consistency

* `CReplayValidator`: `ValidateReplayRange`, `ValidateDatasetVersion` (quality gate
  required), `ValidateSnapshotContinuity` (missing bars vs `(max−min)/TF+1`, duplicate
  timestamps), `ValidateObservationContinuity`, `ValidateTradeContinuity` (broken FK,
  exit<entry), `ValidateTimeline` (out-of-order), `ValidateReplayIntegrity` (full gate).
* **Automatic stop**: the controller re-runs the gate on start/resume and after every
  step; failure forces `REPLAY_STOPPED` (persisted + logged).

## 5. Files created

| File | Purpose |
|---|---|
| `MQL5/Include/CandleBreakoutEA/EAReplay/ReplayTypes.mqh` | states, speeds, replay structs |
| `EAReplay/ReplayValidator.mqh` | Task 0015 integrity engine |
| `EAReplay/ReplayTimeline.mqh` | Task 0014 deterministic playback |
| `EAReplay/ReplayController.mqh` | Task 0013 session control |
| `REPLAY_ENGINE.md`, `REPLAY_TIMELINE.md`, `REPLAY_VALIDATION.md` | module docs |
| `docs/adr/ADR-0011-replay-foundation.md` | decision record |

## 6. Files modified (additive only)

| File | Change |
|---|---|
| `EAData/DatabaseTypes.mqh` | `DB_SCHEMA_VERSION 9`, `DB_TABLE_REPLAY` |
| `EAData/DatabaseSchema.mqh` | `MigrationToV9(ddl[])` |
| `EAData/DatabaseVersion.mqh` | `EnsureVersion` chain `1→…→9` |
| `EATradeManager.mqh` | +include, +`m_replay` member, `Initialize` in `Init` (dormant; no auto-start, no per-tick work) |
| `README.md`, `tools/build_manual.py` (+PDF) | tree (42 headers), counts (7 721 lines), binary size |

Entry/Exit engines, Feature Builder, Dataset Builder, Observation/Label/Quality
engines: untouched.

## 7. Validation results

* `VERDICT: PASS - 0 errors, 0 warnings` (187 180 B binary).
* Trading behaviour and runtime unchanged; replay is dormant until explicitly started.
* Replay deterministic (single ordered load, strict monotonic timeline).
* Replay independent from broker and database-only (allowed tables only).
* Replay reproducible (sessions pinned to DatasetVersion + quality gate; state
  persisted per transition).

## 8. Not implemented (per stop condition)

Replay visualization, replay charts, AI, Event Bus, strategy replay, Monte Carlo,
walk-forward. **Waiting for Sprint 5.**
