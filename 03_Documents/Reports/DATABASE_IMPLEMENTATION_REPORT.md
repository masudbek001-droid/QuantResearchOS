# DATABASE IMPLEMENTATION REPORT — Task 0005 (DAL Foundation)

## 1. Files created

| File | Purpose |
|---|---|
| `MQL5/Include/CandleBreakoutEA/EAData/DatabaseTypes.mqh` | `ENUM_DB_STATUS` + `DbStatusToString`, schema version (1), file/table name constants |
| `EAData/IDataProvider.mqh` | pure interface: Initialize/Open/Close/IsOpen, BeginTransaction/Commit/Rollback, Execute/Prepare/Insert/Update/Delete/Select, Backup/Restore/Validate |
| `EAData/SQLiteProvider.mqh` | `CSQLiteProvider : IDataProvider` — basic SQLite binding: open/close, schema creation, version check, connection validation, transactions, generic statements, CSV backup/restore. **No trade storage.** |
| `EAData/DatabaseManager.mqh` | `CDatabaseManager` — the only class visible outside `EAData/`; owns the provider, logs lifecycle, passes the API through |
| `EAData/DatabaseSchema.mqh` | schema v1 DDL (`DatabaseInfo`, `SchemaVersion`, `MigrationHistory`) + identity rows (product/magic/symbol/created/last_open) |
| `EAData/DatabaseVersion.mqh` | version read/ensure + `ApplyMigration()` funnel (transactional, recorded in `MigrationHistory`) |
| `EAData/DatabaseValidation.mqh` | stateless rules: file name, supported version, schema table existence, transaction probe |
| `DATABASE_LAYER.md` | responsibilities / architecture / interfaces / provider model / versioning / migration strategy |
| `docs/adr/ADR-0003-data-access-layer.md` | architecture decision record |

## 2. Files modified (additive only)

| File | Change |
|---|---|
| `EATradeManager.mqh` | +include, +`CDatabaseManager m_database` member, `Initialize()` + `Open()` in `Init`, `Close()` in `Deinit` |
| `CandleBreakoutEA.mq5` | header comment lists `EAData/*.mqh` |
| `README.md`, `tools/build_manual.py` (+PDF) | module tree (31 headers), counts (4 855 lines), binary size, DAL paragraph |

## 3. Public API (CDatabaseManager)

```
void            Initialize(const CEASettings&, CLogger&);
bool            Open(void);            // create/open file, ensure schema v1, validate
void            Close(void);
bool            IsOpen(void) const;
ENUM_DB_STATUS  LastStatus(void) const;
bool            BeginTransaction/Commit/Rollback(void) const;
bool            Execute(const string) const;
int             Prepare(const string) const;         // 0 = error
int             Insert/Update/Delete(const string) const; // affected rows via SQL changes(), -1 = error
int             Select(const string, string &rows[]) const; // row count, ';' separated columns
bool            Backup/Restore(const string path) const;   // CSV per metadata table
ENUM_DB_STATUS  Validate(void);
string          ToString(void) const;
```

## 4. Implemented features (SQLiteProvider, basic only)

Open/create database file (`CBEA/candlebreakout_<magic>.db`), close, idempotent schema v1
creation, version stamp/read/reject-unsupported, connection + schema + transaction
validation, transactions, execute/prepare/select, affected-row counting, CSV backup and
restore of the metadata tables.

## 5. Validation rules

`DB_OK` | `DB_ERR_OPEN` (file could not be opened/created) | `DB_ERR_CONNECTION` (no
handle) | `DB_ERR_EXECUTE` | `DB_ERR_SCHEMA` (metadata table missing) | `DB_ERR_VERSION`
(version outside 1..DB_SCHEMA_VERSION) | `DB_ERR_TRANSACTION` (begin+rollback probe
failed) | `DB_ERR_VALIDATION` (file name rejected). `Validate()` checks connection →
schema → version → transactions, in that order.

## 6. Platform findings (recorded for future tasks)

The shipped terminal (MetaEditor build 6184) exposes the current-generation Database API:
row stepping is `DatabaseRead()` (not `DatabaseStep`), column count is
`DatabaseColumnsCount()`, getters use out-parameters (`DatabaseColumnText(stmt,col,&s)`),
handles are `int`, rollback is `DatabaseTransactionRollback()`, CSV I/O is
`DatabaseExport(db,table,file,flags,sep)` / 7-parameter `DatabaseImport(...)`, and there
is no `DatabaseRowsAffected` — affected rows come from SQL `changes()`. All of this is
isolated inside `SQLiteProvider.mqh` (verified by a probe-compile against the installed
terminal before adapting the DAL).

## 7. Backward compatibility

* `VERDICT: PASS - 0 errors, 0 warnings` (134 592 B binary).
* Runtime/trading/exit/pending/BreakEven/carry untouched; Feature Builder and Context
  Layer untouched; no existing module migrated.
* DAL failures only log warnings; the EA trades normally without a database.

## 8. Pending work (future tasks)

1. Trade tables + journaling (ADR + migration to schema v2).
2. Statistics/exit-reason persistence; replay consumption; feature snapshot store.
3. Backup scheduling and integrity checks.

**Stop condition honoured:** no Trade tables created, no data migrated, no Replay /
Event Bus implemented. Waiting for Task 0006.
