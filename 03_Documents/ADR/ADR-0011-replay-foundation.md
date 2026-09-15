# ADR-0011 — Replay Foundation (schema v9, database-only playback)

*Status: Accepted (approved by Sprint 4: Tasks 0013–0015).*

## Context
The platform records snapshots (v2), trades (v3), observations (v4), labels (v5),
datasets (v6), quality verdicts (v7) and a feature registry (v8). Quantitative
research needs to replay that recorded history deterministically, without broker
access and without touching the live EA.

## Decision
1. Raise `DB_SCHEMA_VERSION` to 9 and add `ReplaySessions` (persisted session state:
   window, clock, state, speed, bar counters). Migration `8 → 9` runs through
   `ApplyMigration("replay foundation", ddl[2])`.
2. New module `MQL5/Include/CandleBreakoutEA/EAReplay/`:
   * `ReplayTypes.mqh` — states, speeds, `SReplaySnapshot/Observation/Label/Trade`.
   * `ReplayValidator.mqh` (Task 0015) — integrity checks: missing snapshots,
     duplicates, broken references, out-of-order timelines, dataset/quality mismatch.
   * `ReplayTimeline.mqh` (Task 0014) — deterministic in-memory playback loaded once
     from `MarketSnapshots`, with observation/label/trade synchronization.
   * `ReplayController.mqh` (Task 0013) — session lifecycle, seek/step, speeds
     1x/2x/5x/10x/25x/100x/unlimited/step, automatic stop on integrity failure.
3. Replay reads ONLY: ReplaySessions, MarketSnapshots, Observations,
   ObservationLabels, Trades, ResearchDatasets, FeatureRegistry, DatasetQuality.
   No `CopyRates`, no broker calls, no live data of any kind.
4. The trade manager initializes the controller at init but never starts a session:
   replay is dormant infrastructure until a later sprint adds its driver/UI.

## Consequences
* Fully reproducible, database-only replay of recorded market + observation + label +
  trade history, gated by dataset quality.
* Live trading runtime is untouched; replay adds zero per-tick work.
* Later sprints can build visualization, strategy replay, Monte Carlo and walk-forward
  on top without schema churn.
