# ADR-0004 — Market Intelligence schema v2 (observations, not a trade journal)

*Status: Accepted (approved by engineering Task 0006).*

## Context
The Market Intelligence Platform needs a production observation store. The DAL
(ADR-0003) shipped schema v1 with metadata tables only. Trade journaling is explicitly
out of scope.

## Decision
1. Raise `DB_SCHEMA_VERSION` to 2 and add three tables: `Symbols`, `Timeframes`,
   `MarketSnapshots` (one row per completed main-TF bar), plus six query indexes and a
   `UNIQUE(SymbolID,TimeframeID,SnapshotTime)` constraint.
2. All schema changes flow through `CDatabaseVersion::ApplyMigration` (v1 → v2), so
   fresh and existing files share one version trail; unsupported versions are rejected.
3. Add `CMarketSnapshotWriter` (in `EAData/`) as the only writer: it persists the
   Feature Builder snapshot cross-checked against the Context Layer; no module computes
   new market statistics for storage.
4. No trade data, no positions, no strategy coupling; trading behaviour untouched.

## Consequences
* First production dataset for session/hour/weekday-conditioned analysis, future replay
  streaming and AI feature export.
* The DAL stays the only persistence path; SQLite remains isolated in `SQLiteProvider`.
* One extra per-bar INSERT (only on new completed bars); no per-tick database work.
