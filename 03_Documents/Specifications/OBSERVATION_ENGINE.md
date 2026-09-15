# OBSERVATION ENGINE (Market Recorder) — schema v4

Implemented by Task 0008 under ADR-0006. The Observation Engine **records the market** —
it is not a trading feature. Recording runs whether or not a trade exists, and no
observation feeds any trading decision.

## 1. Schema

### `Observations` (facts — one row per completed candle)

`ObservationID` (PK autoinc) · `SymbolID` → `Symbols` · `TimeframeID` → `Timeframes` ·
`ObservationTime` (when it was recorded) · `BarTime` (the completed bar it describes) ·
`ObservationType` (enum below) · `FeatureSnapshotID` → `MarketSnapshots` (the full
feature vector of that bar) · `TradeID` (nullable → `Trades`) · `Session` · `Hour` ·
`Weekday` · `Month` · `CreatedAt` ·
`UNIQUE(SymbolID, TimeframeID, BarTime, ObservationType)`

## 2. Observation types (STEP 2)

| Value | Label | Meaning |
|---|---|---|
| 0 | `OBS_NEW_BAR` | plain completed candle (default) |
| 1 | `OBS_BREAKOUT_UP` | close beyond the previous bar high |
| 2 | `OBS_BREAKOUT_DOWN` | close beyond the previous bar low |
| 3 | `OBS_INSIDE_BAR` | range inside the previous bar range |
| 4 | `OBS_OUTSIDE_BAR` | range engulfs the previous bar range |
| 5 | `OBS_HIGH_VOLATILITY` | range ≥ 1.5 × ATR |
| 6 | `OBS_LOW_VOLATILITY` | range ≤ 0.75 × ATR |
| 7 | `OBS_SESSION_OPEN` | first bar of London/New-York (server clock) |
| 8 | `OBS_SESSION_CLOSE` | last bar of Asia/London (server clock) |
| 9 | `OBS_CUSTOM` | reserved for future recorders |

Classification is descriptive labelling with fixed priority
(breakout → outside → inside → volatility → session → new bar). It is **not** the entry
engine's breakout logic and never influences it.

## 3. Indexes (STEP 6)

`idx_obs_time(ObservationTime)`, `idx_obs_bar(BarTime)`, `idx_obs_type(ObservationType)`,
`idx_obs_symbol(SymbolID)`, `idx_obs_tf(TimeframeID)`.

## 4. Automatic recording (STEP 4)

`CObservationWriter::Update()` runs on the existing per-tick funnel. When a new bar has
completed and the Feature Builder snapshot is valid, exactly one observation is stored:
`BarTime` = the completed bar, `FeatureSnapshotID` = the `MarketSnapshots` row of that
same bar (written first by the snapshot writer), context fields (Session/Hour/Weekday/
Month) from the snapshot, `TradeID = NULL` — recording never depends on a trade.
Restart-safe: bar cache + the UNIQUE constraint + a duplicate pre-check guarantee
**exactly one** observation per candle.

## 5. Validation (STEP 5)

Rejected: duplicate observation (same symbol/timeframe/bar/type), missing feature
snapshot (no `MarketSnapshots` row for the bar, or dangling id), invalid `BarTime`
(≤ 0 or in the future), invalid `ObservationType` (outside 0..9). Rejections log a
warning; recording failures never affect trading.

## 6. Independence & reuse

* Independent from trading: `TradeID` is nullable and always NULL for automatic
  observations; nothing in the writer reads position state.
* Feature Builder reused as the only feature source (no new statistics computed);
  Context Layer values (session/hour) arrive through the validated snapshot; all
  persistence goes through the DAL (`CDatabaseManager`).

## 7. Future compatibility

* **Replay**: `Observations` gives the event skeleton (what happened, when, of what
  kind); joined to `MarketSnapshots` it is a full per-bar timeline.
* **AI**: type labels + linked feature vectors are ready-made training samples;
  `OBS_CUSTOM` and `TradeID` allow outcome-labelled datasets later without schema
  churn.
