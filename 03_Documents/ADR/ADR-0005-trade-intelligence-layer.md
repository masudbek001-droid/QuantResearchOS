# ADR-0005 — Trade Intelligence Layer (schema v3, research-first)

*Status: Accepted (approved by engineering Task 0007).*

## Context
Quantitative research needs complete trade metadata linked to market observations.
The CSV journal is frozen by contract and serves operational statistics; the Market
Intelligence DB (ADR-0004) already stores per-bar observations.

## Decision
1. Raise `DB_SCHEMA_VERSION` to 3 and add the `Trades` table (metadata + result +
   duration + strategy flags) with six indexes; migration `2 → 3` runs through
   `ApplyMigration("trade intelligence phase 1", ddl[7])`.
2. Every trade references `EntrySnapshotID` / `ExitSnapshotID` in `MarketSnapshots`:
   entry links to the newest snapshot **before the entry bar** (no look-ahead), exit to
   the newest snapshot by exit time; missing snapshots reject the write.
3. Add `CTradeWriter` (in `EAData/`): `InsertTrade()` / `UpdateTradeExit()` /
   `ValidateTrade()`, no business logic. Hooks: `HandlePositionOpened` and
   `SyncWithChart` (insert), the existing single `RecordExitOnce` funnel (exit update).
4. `CTradeHistory` gains one additive reader `DealCostsOfPosition()` (gross profit,
   swap, commission); the CSV contract and trading behaviour are untouched.

## Consequences
* Research-ready dataset: trade outcomes joinable to full market feature vectors.
* The DAL stays the only persistence path; trading decisions and the frozen CSV are
  unaffected — writer failures only log warnings.
* Two extra statements per trade lifecycle (one INSERT, one UPDATE); no per-tick work.
