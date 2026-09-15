# IMPORT REPORT — Sprint 6A (Research.db schema v11 + import bookkeeping)

## 1. Schema v11 migration (Research.db only)

Chain `1→…→10→11`, single migration `MigrationToV11(ddl[3])`,
label `"historical data platform masters"`:

* `DataSources` — DataSourceID PK autoinc, BrokerName, ServerName, AccountType,
  Platform, CreatedAt, **UNIQUE(BrokerName, ServerName, AccountType)** → one row per
  broker/server/account triple; a second broker adds a row, nothing else changes.
* `ImportHistory` — ImportID PK autoinc, DatabaseName, DataSourceID, StartedAt,
  FinishedAt, RecordsImported (default 0), Checksum, ImportStatus (default 0)
  + `idx_import_db` on DatabaseName.
* `ENUM_IMPORT_STATUS`: RUNNING(0) / FINISHED(1) / FAILED(2) / **INTERRUPTED(3)** —
  the resumable state; a crash leaves RUNNING rows that the next
  `ResumeExport` / `ResumeBars` continues past via the store's MAX() resume points.

Existing tables (trades, observations, labels, replay, experiments, benchmarks,
walk-forward) are untouched — v11 is additive only.

## 2. Import lifecycle (`CHistoryPlatform`)

```
BeginImport(db_name)  → INSERT (RUNNING) → ImportID
  ... paged export (ticks or bars) ...
FinishImport(id, records, checksum, status)
  → UPDATE FinishedAt, RecordsImported, Checksum, ImportStatus
```

* Checksum = deterministic record-count hash (`IntegerToString(records)`), stored as
  TEXT so future hashes (SHA-style over pages) stay compatible.
* `ExportAllHistory` books TWO rows (Ticks.db, Market.db) per full run;
  `SyncIncremental` books two rows per incremental run — full audit trail of every
  acquisition event with duration (Started/FinishedAt) and volume.

## 3. Data-source registration

`RegisterDataSource()` at init: broker = `TERMINAL_COMPANY`, server =
`ACCOUNT_SERVER`, account = demo/real, platform = MT5 build number;
`INSERT OR IGNORE` + lookup → `m_source_id` stamped on every import row and every
exported tick/bar batch context.

## 4. Verification

Compile: **0 errors, 0 warnings** (MetaEditor build 6184), `CandleBreakoutEA.ex5`
205 506 bytes. Migration chain tested by build-time SQL review; runtime v10→v11
upgrade path uses the existing `CDatabaseManager` migration runner (unchanged).
