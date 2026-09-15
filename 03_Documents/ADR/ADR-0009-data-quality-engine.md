# ADR-0009 — Research Data Quality Engine (schema v7, mandatory export gate)

*Status: Accepted (approved by engineering Task 0011).*

## Context
Research datasets are the input for future ML work. Without an enforced quality gate,
a dataset with broken references, duplicates or look-ahead leakage could reach
training and silently poison every model built on it.

## Decision
1. Raise `DB_SCHEMA_VERSION` to 7 and add `DatasetQuality` (append-only report rows:
   counts, four scores, status, timestamp) with a version index. Migration `6 → 7`
   runs through `ApplyMigration("research data quality engine", ddl[2])`.
2. Add `CDataQualityAnalyzer` (in `EAData/`): `AnalyzeDataset()` (all STEP-4 checks,
   scores 0..100, status), `GenerateQualityReport()`, `ValidateDataset()`; one
   analysis per completed bar.
3. Hard violations (duplicates, missing snapshots/labels, broken FKs, invalid
   timestamps/features, look-ahead, label-version mismatch) always produce
   `QUALITY_FAIL` regardless of the score.
4. Export protection: `CDatasetBuilder` gains an additive, optional
   `AttachQuality()`; once attached, CSV export refuses any version whose latest
   report is not `QUALITY_PASS`. No override path exists; an unanalyzed dataset is
   blocked too.

## Consequences
* ML exports are impossible unless the dataset provably passes every rule.
* Quality history is auditable (append-only reports) and reproducible (deterministic
  counts and scores).
* Builder logic itself is unchanged — the gate is a new additive dependency wired by
  the trade manager; trading runtime is unaffected.
