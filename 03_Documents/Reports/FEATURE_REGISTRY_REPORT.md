# FEATURE REGISTRY REPORT — Task 0012

## 1. Database version

`DB_SCHEMA_VERSION = 8` (was 7). Full chain: `1→2` market intelligence → `2→3` trade
intelligence → `3→4` observation engine → `4→5` label engine → `5→6` dataset builder →
`6→7` data quality → `7→8` feature registry, each transactional and recorded in
`MigrationHistory`.

## 2. Created table — `FeatureRegistry`

FeatureID (PK autoinc) · FeatureName · FeatureVersion · FeatureCategory · Description ·
Owner · ValidationRule · Status (ACTIVE/RESERVED/DEPRECATED) · CreatedAt ·
DeprecatedAt (nullable) · UNIQUE(FeatureName,FeatureVersion) + `idx_feature_name`

## 3. Categories & statuses (STEP 2)

`FEATURE_PRICE(0)`, `FEATURE_VOLATILITY(1)`, `FEATURE_TREND(2)`, `FEATURE_SESSION(3)`,
`FEATURE_TIME(4)`, `FEATURE_STATISTICAL(5)`, `FEATURE_CUSTOM(6)`;
`FEATURE_ACTIVE(0)`, `FEATURE_RESERVED(1)`, `FEATURE_DEPRECATED(2)`.

## 4. Registrar (STEP 3) — `CFeatureRegistry` (`EAData/FeatureRegistry.mqh`)

`RegisterFeature()` (idempotent per name+version) · `ValidateFeature()` ·
`GetFeature()` (full row into `SFeatureInfo`) · `GetVersion()` (newest non-deprecated)
· `ListFeatures()` (deterministic order) · `SeedStandardFeatures()` — seeds the 22
`SFeatureSnapshot` features at v1 with owner `CFeatureBuilder` and their validation
rules (ranges/finiteness/boolean).

## 5. Dataset integration (STEP 4)

Per-bar sidecar manifest `MQL5/Files/CBEA/dataset_v<n>.manifest.txt` pins:
`DatasetVersion`, `FeatureVersion` (+FeatureCount), `LabelVersion`,
`QualityVersion` (latest `DatasetQuality.QualityID`) and `QualityStatus`. Every
exportable dataset version is therefore unambiguous about its feature, label and
quality inputs.

## 6. Validation rules (STEP 5)

Rejected: duplicate FeatureName+Version (UNIQUE + idempotent no-op), invalid version
(≤0), missing validation rule (empty), unknown category (outside the enum).

## 7. Files created

| File | Purpose |
|---|---|
| `MQL5/Include/CandleBreakoutEA/EAData/FeatureRegistry.mqh` | registry + manifest writer |
| `FEATURE_REGISTRY.md` | catalogue contract / categories / integration / validation |
| `docs/adr/ADR-0010-feature-registry.md` | decision record |

## 8. Files modified (additive only)

| File | Change |
|---|---|
| `EAData/DatabaseTypes.mqh` | `DB_SCHEMA_VERSION 8`, `DB_TABLE_FEATURES`, category/status enums |
| `EAData/DatabaseSchema.mqh` | `MigrationToV8(ddl[])` — table + index |
| `EAData/DatabaseVersion.mqh` | `EnsureVersion` chain `1→…→8` |
| `EATradeManager.mqh` | +include, +`m_registry`, `Initialize` in `Init` (seeds catalogue), `Update(1)` after `m_quality.Update()` |
| `README.md`, `tools/build_manual.py` (+PDF) | tree (38 headers), counts (6 843 lines), binary size |

Dataset Builder, Data Quality Engine, Feature Builder, Label/Observation Engines,
trading logic: untouched.

## 9. Validation results

* `VERDICT: PASS - 0 errors, 0 warnings` (186 092 B binary).
* Trading/runtime unchanged; registry work = init seeding + one tiny manifest file
  per completed bar.
* Feature Registry operational (22 features seeded at v1 with rules and owners).
* Dataset version reproducibility preserved — manifests pin exact versions; exports
  and quality gating unchanged.
* DAL reused (all SQL via `CDatabaseManager`).

**Stop condition honoured:** no Replay, no AI, no Event Bus. Waiting for Task 0013.
