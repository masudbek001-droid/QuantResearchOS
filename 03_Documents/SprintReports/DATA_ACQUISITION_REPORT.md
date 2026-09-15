# DATA ACQUISITION REPORT — Sprint 6A (Historical Data Platform, Tasks 1–6)

## 1. Architecture: four databases

| Store | File (`MQL5\Files\CBEA\`) | Owner | Contents |
|---|---|---|---|
| Ticks.db | `Ticks.db` | `CHistoryStore` + `CTickExporter` | raw ticks + tick metadata |
| Market.db | `Market.db` | `CHistoryStore` + `CBarExporter` | M1–D1 bars (7 TFs) + bar metadata |
| Models.db | `CBEA_Models.db` | `CHistoryStore` + model platform tools | schema v2 — model registry, feature-vector contracts, evaluations, ONNX metadata |
| Research.db | `candlebreakout_<magic>.db` | `CDatabaseManager` (DAL) | extended only: schema v11 adds `DataSources` + `ImportHistory` |

Each dedicated store carries LOCAL `Symbols` (SymbolID / Symbol / Digits / Point /
TickSize / ContractSize / Base / QuoteCurrency / Active) and `Timeframes` (7 rows,
TimeframeID = `ENUM_TIMEFRAMES` value, Minutes = PeriodSeconds/60) masters, seeded by
`CHistoryStore::EnsureMasters()` — SQLite has no cross-file foreign keys.

## 2. TASK 1 — CTickExporter (Ticks.db)

* `Ticks` table: UNIQUE(SymbolID, BrokerTime, Milliseconds, Bid, Ask), `INSERT OR
  IGNORE` → **no duplicates on re-export**; indexes on symbol, broker time, UTC.
* `ExportHistory(import_id)` — paged `CopyTicks(symbol, ticks, COPY_TICKS_ALL,
  from_ms, 100 000)`, per-page transactions, progress log every `HIST_PROGRESS_TICKS`
  (1 M) ticks, writes the import row counter.
* `ResumeExport()` — resume point = `MAX(BrokerTime)` (+1 ms) so an interrupted
  import continues exactly where it stopped (ImportHistory status INTERRUPTED/FAILED).
* `ValidateTicks()` — duplicate / invalid / out-of-order scan, returns the counts
  (also used by the integrity validator).
* `SyncLatestTicks()` — TASK 5 incremental entry point: exports only ticks after the
  newest stored tick.

## 3. TASK 2 — CBarExporter (Market.db)

* `Bars` table: UNIQUE(SymbolID, TimeframeID, OpenTime) + all 16 spec columns
  (OHLC, Volume, Spread, UTC/week/weekday/month/quarter/hour, Session, DST flag).
* `ExportBars(import_id)` — walks `HIST_TIMEFRAMES[7]` (M1 M5 M15 M30 H1 H4 D1) via
  paged `CopyRates`, per-page transactions, progress every `HIST_PROGRESS_BARS`
  (100 k) bars.
* `ResumeBars()` — per-TF resume point = `MAX(OpenTime) WHERE TimeframeID=…`;
  already-stored candles are skipped by the UNIQUE constraint.
* `ValidateBars()` — aggregate OHLC / spread / continuity scan.
* `SynchronizeBars()` — TASK 5 incremental: re-exports each timeframe from its last
  stored open time (the in-progress current bar is refreshed).

## 4. TASK 3 — CMetadataExporter

`MarketMetadata` key/value table (UNIQUE(SymbolID, MetaKey), ON CONFLICT UPDATE) in
BOTH Ticks.db and Market.db: digits, point, tick size/value, contract size, spread,
broker UTC offset (broker − GMT, hours), DST heuristic, base/quote currency, trade
mode, and Session1–Session5 per weekday via `SymbolInfoSessionTrade(symbol, day, 0,
from, to)`. Runs after every full export / sync.

## 5. TASK 6 — statistics (`CHistoryPlatform::GenerateStatistics`)

One report: tick total + Ticks.db size, bar total + Market.db size, Models.db size,
and per-timeframe counts with MIN..MAX coverage dates. Counts and durations also
land in Research.db `ImportHistory` (RecordsImported, Started/FinishedAt).

## 6. Data sources & import bookkeeping (schema v11)

* `DataSources` (Research.db): broker + server + account type registered once
  (`INSERT OR IGNORE` on UNIQUE(BrokerName, ServerName, AccountType)) →
  **multi-broker ready**: a second broker simply adds a row; stores stay separate.
* `ImportHistory`: every export/sync run gets `BeginImport(db_name)` →
  RecordsImported + deterministic Checksum (record-count hash) + status
  RUNNING→FINISHED / FAILED at `FinishImport`.

## 7. Verification

Compile: **0 errors, 0 warnings** (MetaEditor build 6184, `CandleBreakoutEA.ex5`,
205 506 bytes). The platform is **dormant at init** — `CHistoryPlatform::Initialize`
only opens stores, registers the source and prepares Models.db; no export runs until
`ExportAllHistory` / `SyncIncremental` is called. Trading, entry/exit, replay,
experiment, benchmark, walk-forward, feature-builder, observation and label engines
are untouched (verified by include-diff of the sprint: only `EATradeManager.mqh`
gained 1 member + 2 lines, `SchemaMigrations` v10→v11).
