# ADR-0013 — Historical Data Platform (schema v11: data sources, import history)

*Status: Accepted (approved by Sprint 6A: Tasks 1–6).*

*Update 2026-09-15: the original Models.db placeholder status in this ADR was
superseded by ADR-0014. `CBEA_Models.db` is now schema v2 with model registry,
feature-vector contracts, evaluations, and ONNX metadata.*

## Context
The platform replays and researches recorded data but had no first-class store for
RAW historical market data: ticks, multi-timeframe bars, broker metadata. Sprint 6A
must add acquisition + integrity + incremental sync without touching trading,
replay, experiment, benchmark, walk-forward, feature-builder, observation or label
engines.

## Decision
1. Three NEW dedicated SQLite stores under `MQL5\Files\CBEA\`: `Ticks.db` (raw
   ticks), `Market.db` (M1–D1 bars, 7 TFs), `Models.db` (architecture only —
   `ModelsSchemaVersion` seeded to 1). They are opened through `CSQLiteProvider`
   directly; `CDatabaseManager` stays bound to Research.db only.
2. Each dedicated store owns LOCAL `Symbols` + `Timeframes` master tables
   (`CHistoryStore::EnsureMasters`), keyed by `ENUM_TIMEFRAMES` values — SQLite has
   no cross-file foreign keys, so masters are replicated per store.
3. Deduplication by schema, not by code: `Ticks` UNIQUE(SymbolID, BrokerTime,
   Milliseconds, Bid, Ask) and `Bars` UNIQUE(SymbolID, TimeframeID, OpenTime) with
   `INSERT OR IGNORE` → re-exports and resumes cannot duplicate rows.
4. Resume by watermark: ticks resume at `MAX(BrokerTime)+1ms`, bars per TF at
   `MAX(OpenTime)`; interrupted runs are safe to re-run.
5. Research.db is EXTENDED, never restructured: v11 adds `DataSources`
   (UNIQUE broker/server/account → multi-broker ready) and `ImportHistory`
   (RUNNING/FINISHED/FAILED/INTERRUPTED, RecordsImported, Checksum, timestamps) via
   one additive migration.
6. Integrity is a read-only observer (`CDataIntegrityValidator`): duplicate,
   invalid, out-of-order, missing (weekend-aware), negative-spread and TF-ratio
   checks; it reports, the UNIQUE+resume mechanisms heal.
7. `CHistoryPlatform` is the single facade; it is **dormant at init** — exports run
   only via explicit `ExportAllHistory` / `SyncIncremental` / `ValidateIntegrity` /
   `GenerateStatistics` calls.

## Consequences
* Frozen engines (entry/exit/BE/carry/replay/experiment/benchmark/walk-forward/
  features/labels) see zero changes; only `EATradeManager` gains one dormant member.
* Tick/bulk writes bypass the DAL on purpose (raw volume), while research-visible
  bookkeeping (sources, imports) stays in the versioned Research.db chain.
* A second broker = one `DataSources` row + its own store files; no code change.
* Models.db was reserved for Sprint 6B+ at the time of this ADR; it is now active
  as schema v2 under ADR-0014.

## Alternatives rejected
* Storing ticks/bars in Research.db — bloats the research chain, slows migrations,
  couples raw volume to schema versioning.
* Cross-file ATTACH for shared masters — fragile across brokers/files, rejected in
  favour of small replicated masters.
* Dedup via SELECT-before-INSERT — O(n) per row; UNIQUE+OR IGNORE is atomic and free.
