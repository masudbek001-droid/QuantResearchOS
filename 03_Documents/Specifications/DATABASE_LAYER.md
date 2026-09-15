# DATABASE LAYER (DAL) — `MQL5/Include/CandleBreakoutEA/EAData/`

Implemented by Task 0005 under ADR-0003. The Data Access Layer is the **only persistence
interface** of the project: no module may talk to SQLite (or any future storage) directly.

## 1. Responsibilities

* Own every database lifecycle operation: open, close, schema creation, version check,
  validation, transactions, generic statements, backup/restore.
* Isolate SQLite completely behind `IDataProvider` — swappable provider model.
* Foundation only: metadata tables in schema v1, **no trade tables, no business logic**.

## 2. Architecture

```
consumers (future: trade journal, statistics, replay, AI store)
        │  use ONLY
        ▼
CDatabaseManager          ← the single public facade (owned by CTradeManager)
        │  delegates through
        ▼
IDataProvider (interface) ← Initialize/Open/Close/BeginTransaction/Commit/Rollback/
        ▲                   Execute/Prepare/Insert/Update/Delete/Select/Backup/Restore/Validate
        │ implements
CSQLiteProvider           ← MT5 SQLite binding (internal to EAData/)
        │ uses
CDatabaseSchema · CDatabaseVersion · CDatabaseValidation
```

Files: `DatabaseTypes.mqh` (status enum, constants, table names), `IDataProvider.mqh`
(pure interface), `SQLiteProvider.mqh` (implementation), `DatabaseManager.mqh` (facade),
`DatabaseSchema.mqh` (DDL), `DatabaseVersion.mqh` (versioning/migrations),
`DatabaseValidation.mqh` (stateless rules).

## 3. Interfaces

`IDataProvider` is a pure abstract contract with the 15 mandated operations. Anything
persistence-related must be expressible through it; adding operations requires an ADR.

## 4. Provider model

* `CSQLiteProvider` implements the contract with the MT5 Database API of the shipped
  terminal (build 6184 generation: `DatabaseRead/DatabaseColumnsCount/DatabaseTransaction-
  Rollback/DatabaseExport/DatabaseImport`; handles are `int`; affected rows via SQL
  `changes()` since this build exposes no `DatabaseRowsAffected`).
* Providers are constructed inside `CDatabaseManager` only; the rest of the project never
  sees the concrete class.

## 5. Versioning

* `DB_SCHEMA_VERSION = 1` (metadata only): `DatabaseInfo(key,value)`,
  `SchemaVersion(version,applied_at)`, `MigrationHistory(id,from_version,to_version,
  description,applied_at)`.
* Opening a new file creates the schema and stamps version 1 plus identity rows
  (product, magic, symbol, created, last_open).
* A file with a version above the supported range is rejected (`DB_ERR_VERSION`), never
  auto-migrated.

## 6. Migration strategy

* Every future schema change ships as DDL + `CDatabaseVersion::ApplyMigration(from,to,
  description,ddl[])`, executed in one transaction and recorded in `MigrationHistory`.
* Migrations run forward-only, one version at a time; rollback is a restore from backup,
  not a down-migration.

## 7. Validation (STEP 6)

`Validate()` checks, in order: connection open → metadata tables exist → schema version
supported → transactions available (begin+rollback probe). Any failure returns the exact
`ENUM_DB_STATUS` and never blocks trading.

## 8. Runtime policy

`CTradeManager` initializes and opens the DAL in `Init` and closes it in `Deinit`.
DAL failures are logged as warnings; trading continues unaffected. The DAL performs
zero per-tick work.
