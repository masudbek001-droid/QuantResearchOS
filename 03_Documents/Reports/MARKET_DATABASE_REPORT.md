# MARKET DATABASE REPORT — Task 0006 (Market Intelligence Phase 1)

## 1. Database version

`DB_SCHEMA_VERSION = 2` (was 1). Migration path: fresh files are stamped v1 then migrated
`1 → 2` via `ApplyMigration("market intelligence phase 1", ddl[9])`; existing v1 files
migrate the same way; every migration is transactional and recorded in `MigrationHistory`.

## 2. Created tables

| Table | Columns |
|---|---|
| `Symbols` | SymbolID (PK, autoinc), Symbol (UNIQUE), Digits, Point, TickSize, TickValue, ContractSize, CreatedAt |
| `Timeframes` | TimeframeID (PK = ENUM_TIMEFRAMES value), Name (UNIQUE), Minutes |
| `MarketSnapshots` | SnapshotID (PK, autoinc), SymbolID, TimeframeID, SnapshotTime, Spread, ATR, ATRRatio, Open, High, Low, Close, BodySize, BodyPercent, UpperShadow, LowerShadow, "Range", Volatility, TrendDirection, TrendStrength, CurrentSession, CurrentHour, Weekday, Month, Quarter, BrokerOffset, CreatedAt, UNIQUE(SymbolID,TimeframeID,SnapshotTime) |

No trade tables. No positions stored.

## 3. Indexes (STEP 2)

`idx_snap_time(SnapshotTime)`, `idx_snap_symbol(SymbolID)`, `idx_snap_tf(TimeframeID)`,
`idx_snap_session(CurrentSession)`, `idx_snap_hour(CurrentHour)`,
`idx_snap_weekday(Weekday)` — plus the implicit UNIQUE-constraint index.

## 4. Snapshot writer (STEP 3)

`CMarketSnapshotWriter::InsertMarketSnapshot()` — single responsibility: persist one
observation per completed main-TF bar. Sources: `SFeatureSnapshot` (Feature Builder,
primary), `CMarketContext` (Context Layer cross-check), raw OHLC of the same completed
bar. Per-tick `Update()` is a no-op unless a new completed bar exists; restart-safe via
bar-time cache + the UNIQUE constraint.

## 5. Validation rules (STEP 4)

Rejected: invalid OHLC (high<low, OHLC outside [low,high], zero range), negative ATR,
negative spread, NaN/Infinity (Feature Builder rule set reused), Context/Feature
mismatch (hour/session disagreement), duplicate (SymbolID,TimeframeID,SnapshotTime).
All rejections log a warning; the EA never depends on a successful write.

## 6. Files created

| File | Purpose |
|---|---|
| `MQL5/Include/CandleBreakoutEA/EAData/MarketSnapshotWriter.mqh` | the observation writer |
| `MARKET_DATABASE.md` | schema / relationships / indexes / replay & AI compatibility |
| `docs/adr/ADR-0004-market-intelligence-schema.md` | decision record |

## 7. Files modified (additive only)

| File | Change |
|---|---|
| `EAData/DatabaseTypes.mqh` | `DB_SCHEMA_VERSION 2`, table-name constants |
| `EAData/DatabaseSchema.mqh` | `MigrationToV2(ddl[])` — 3 tables + 6 indexes |
| `EAData/DatabaseVersion.mqh` | `EnsureVersion` now stamps v1 and runs the 1→2 migration (includes `DatabaseSchema.mqh`) |
| `EATradeManager.mqh` | +include, +`m_market_writer` member, `Initialize(...)` in `Init`, `Update()` after `m_features.Update()` on the existing dashboard path |
| `README.md`, `tools/build_manual.py` (+PDF) | tree (32 headers), counts (5 127 lines), binary size, DAL v2 paragraph |

`SQLiteProvider`, `DatabaseManager`, `IDataProvider`, Feature Builder, Context Layer,
entry/exit/pending/BreakEven/carry logic: untouched.

## 8. Validation results

* `VERDICT: PASS - 0 errors, 0 warnings` (146 464 B binary).
* Trading/runtime behaviour unchanged — writer only reads published snapshots and adds
  at most one INSERT per completed bar.
* DAL reused (all SQL goes through `CDatabaseManager`), Context Layer reused
  (cross-check), Feature Builder reused (sole feature source).
* Market snapshots storable: schema + indexes + writer + duplicate/dedup path in place.

**Stop condition honoured:** no Trade tables, no positions stored, no Replay / Event Bus /
AI. Waiting for Task 0007.
