# OBSERVATION ENGINE REPORT — Task 0008

## 1. Database version

`DB_SCHEMA_VERSION = 4` (was 3). Chain for every file: `1→2` (market intelligence) →
`2→3` (trade intelligence) → `3→4` (observation engine), each transactional and recorded
in `MigrationHistory`.

## 2. Created table — `Observations`

ObservationID (PK autoinc) · SymbolID → Symbols · TimeframeID → Timeframes ·
ObservationTime · BarTime · ObservationType · FeatureSnapshotID → MarketSnapshots ·
TradeID (nullable → Trades) · Session · Hour · Weekday · Month · CreatedAt ·
UNIQUE(SymbolID,TimeframeID,BarTime,ObservationType)

## 3. Observation types (STEP 2)

`OBS_NEW_BAR(0)`, `OBS_BREAKOUT_UP(1)`, `OBS_BREAKOUT_DOWN(2)`, `OBS_INSIDE_BAR(3)`,
`OBS_OUTSIDE_BAR(4)`, `OBS_HIGH_VOLATILITY(5)` (range ≥ 1.5×ATR),
`OBS_LOW_VOLATILITY(6)` (range ≤ 0.75×ATR), `OBS_SESSION_OPEN(7)`,
`OBS_SESSION_CLOSE(8)`, `OBS_CUSTOM(9)`. Classification is descriptive labelling only
(fixed priority); it shares no code with the entry engine.

## 4. Writer (STEP 3) — `CObservationWriter` (`EAData/ObservationWriter.mqh`)

```
bool InsertObservation(bar_time,type,feature_snapshot_id,trade_id,
                       session,hour,weekday,month);
bool ValidateObservation(bar_time,observation_type,feature_snapshot_id);
void Update(void);   // one observation per completed candle
```

## 5. Automatic recording (STEP 4)

On the existing per-tick funnel, after the snapshot writer: when a new bar completed and
the Feature Builder snapshot is valid, exactly one observation is stored —
feature snapshot link (`SnapshotTime = BarTime`), market-context fields from the
validated snapshot, classified type, `TradeID = NULL`. No trade required; bar cache +
duplicate pre-check + UNIQUE constraint ⇒ exactly one row per candle, restart-safe.

## 6. Validation rules (STEP 5)

Rejected: duplicate observation, missing feature snapshot (no row for the bar / dangling
id), invalid BarTime (≤0 or future), invalid ObservationType (outside 0..9). Rejections
log a warning; trading never depends on recording.

## 7. Indexes (STEP 6)

`idx_obs_time(ObservationTime)` · `idx_obs_bar(BarTime)` · `idx_obs_type(ObservationType)`
· `idx_obs_symbol(SymbolID)` · `idx_obs_tf(TimeframeID)`

## 8. Files created

| File | Purpose |
|---|---|
| `MQL5/Include/CandleBreakoutEA/EAData/ObservationWriter.mqh` | enum + Observation Engine |
| `OBSERVATION_ENGINE.md` | schema / types / recording / validation / future compatibility |
| `docs/adr/ADR-0006-observation-engine.md` | decision record |

## 9. Files modified (additive only)

| File | Change |
|---|---|
| `EAData/DatabaseTypes.mqh` | `DB_SCHEMA_VERSION 4`, `DB_TABLE_OBSERVATIONS` |
| `EAData/DatabaseSchema.mqh` | `MigrationToV4(ddl[])` — table + 5 indexes |
| `EAData/DatabaseVersion.mqh` | `EnsureVersion` chain `1→2→3→4` |
| `EATradeManager.mqh` | +include, +`m_observations`, `Initialize` in `Init`, `Update()` after `m_market_writer.Update()` |
| `README.md`, `tools/build_manual.py` (+PDF) | tree (34 headers), counts (5 681 lines), binary size |

Entry/Exit/BreakEven/Carry/Profit-Lock, Feature Builder calculations, MarketSnapshots
and Trades schemas: untouched.

## 10. Validation results

* `VERDICT: PASS - 0 errors, 0 warnings` (163 284 B binary).
* Trading behaviour and runtime unchanged; recorder is write-only observation.
* Feature Builder reused (sole feature source), Context Layer reused (session/clock via
  the validated snapshot), DAL reused (all SQL via `CDatabaseManager`).
* Every completed candle creates exactly one observation; observations are independent
  from trades (`TradeID` NULL).

**Stop condition honoured:** no Replay, no Event Bus, no AI. Waiting for Task 0009.
