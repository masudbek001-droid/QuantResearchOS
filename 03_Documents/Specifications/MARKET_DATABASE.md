# MARKET INTELLIGENCE DATABASE — schema v2

Implemented by Task 0006 under ADR-0004, on top of the Data Access Layer (`EAData/`).
This is **not** a trade journal — it is the observation store of the Market Intelligence
Platform. No trade, position or order data is stored.

## 1. Schema

### `Symbols` (reference)
`SymbolID` (PK, autoincrement) · `Symbol` (UNIQUE) · `Digits` · `Point` · `TickSize` ·
`TickValue` · `ContractSize` · `CreatedAt`

### `Timeframes` (reference)
`TimeframeID` (PK = MQL5 `ENUM_TIMEFRAMES` value) · `Name` (UNIQUE) · `Minutes`

### `MarketSnapshots` (facts — one row per completed main-TF bar)
`SnapshotID` (PK, autoincrement) · `SymbolID` → `Symbols` · `TimeframeID` → `Timeframes` ·
`SnapshotTime` (bar open time, epoch) · `Spread` · `ATR` · `ATRRatio` · `Open` · `High` ·
`Low` · `Close` · `BodySize` · `BodyPercent` · `UpperShadow` · `LowerShadow` · `"Range"` ·
`Volatility` · `TrendDirection` · `TrendStrength` · `CurrentSession` · `CurrentHour` ·
`Weekday` · `Month` · `Quarter` · `BrokerOffset` · `CreatedAt` ·
`UNIQUE(SymbolID, TimeframeID, SnapshotTime)`

`"Range"` is quoted everywhere because RANGE is an SQL keyword.

## 2. Relationships

```
Symbols 1 ── * MarketSnapshots * ── 1 Timeframes
```

Facts never duplicate symbol/timeframe attributes; reference rows are registered once by
the writer (`EnsureReferences`) with `INSERT OR IGNORE` and cached in memory.

## 3. Indexes

| Index | Column | Purpose |
|---|---|---|
| `idx_snap_time` | SnapshotTime | time-range scans (replay, charts) |
| `idx_snap_symbol` | SymbolID | per-symbol history |
| `idx_snap_tf` | TimeframeID | per-timeframe slices |
| `idx_snap_session` | CurrentSession | session-conditioned statistics |
| `idx_snap_hour` | CurrentHour | hour-of-day conditioning |
| `idx_snap_weekday` | Weekday | day-of-week conditioning |
| (implicit) | UNIQUE(SymbolID,TimeframeID,SnapshotTime) | duplicate rejection |

## 4. Writer (`CMarketSnapshotWriter`)

Single responsibility: persist one observation per completed main-TF bar.
Data source = validated `SFeatureSnapshot` (Feature Builder), cross-checked against the
Context Layer (`CMarketContext` hour/session must agree); raw OHLC read from the same
completed bar. At most one write per bar (bar-time cache + UNIQUE constraint);
restart-safe. Zero per-tick cost when the database is closed or no new bar exists.

## 5. Validation (rejected rows)

Invalid OHLC (`high<low`, OHLC outside range, zero range), negative ATR, negative spread,
NaN/Infinity (Feature Builder rule set reused), Context/Feature mismatch, duplicate
`(SymbolID, TimeframeID, SnapshotTime)`. Rejections are logged; trading never depends on
a successful write.

## 6. Versioning

`DB_SCHEMA_VERSION = 2`. Fresh files are stamped v1 then migrated `1 → 2` through
`CDatabaseVersion::ApplyMigration()` (transactional, recorded in `MigrationHistory`),
so every database carries an identical version trail. Files with unsupported versions
are rejected, never auto-migrated.

## 7. Future compatibility

* **Replay**: `MarketSnapshots` rows are timestamped, ordered and index-backed — a replay
  engine can stream `WHERE SnapshotTime BETWEEN …` in bar order without touching live
  code.
* **AI**: the row layout is already a flat feature vector (24 numeric feature columns +
  condition keys); a training export is a single `SELECT`, and `Reserved` schema slots
  arrive by migration v3 without rewriting consumers.
* **Trade journal**: separate future tables in the same database (v3+), never mixed with
  observation data.
