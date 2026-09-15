# ADR-0003 — Introduce the Data Access Layer (EAData/)

*Status: Accepted (approved by engineering Task 0005).*

## Context
MIPS requires a persistence foundation before any trade journaling, statistics storage,
replay or AI store can be built. Without a boundary, modules would talk to SQLite
directly and lock the project to one engine and scattered SQL.

## Decision
1. Add module `MQL5/Include/CandleBreakoutEA/EAData/` with `DatabaseTypes.mqh`,
   `IDataProvider.mqh`, `SQLiteProvider.mqh`, `DatabaseManager.mqh`,
   `DatabaseSchema.mqh`, `DatabaseVersion.mqh`, `DatabaseValidation.mqh`.
2. All persistence goes through `CDatabaseManager` → `IDataProvider`; SQLite is visible
   only inside `EAData/`.
3. Schema v1 contains metadata tables only (`DatabaseInfo`, `SchemaVersion`,
   `MigrationHistory`); trade tables arrive with a future ADR.
4. The DAL is wired into `CTradeManager` init/deinit only; failures never affect trading;
   no per-tick work.

## Consequences
* Provider-swappable persistence; consumers stay engine-agnostic.
* Build-6184 Database API generation is isolated in one file (`SQLiteProvider.mqh`):
  `DatabaseRead` instead of `DatabaseStep`, int handles, `changes()` for affected rows,
  7-parameter `DatabaseImport`.
* No runtime behaviour change; trading untouched; Feature Builder and Context Layer
  untouched.
