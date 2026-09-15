# ADR-0010 — Feature Registry and feature versioning (schema v8)

*Status: Accepted (approved by engineering Task 0012).*

## Context
Datasets, labels and quality reports all reference market features, but feature
definitions themselves lived only in code. Research needs an explicit, versioned
catalogue so that any dataset can be traced to exact feature semantics.

## Decision
1. Raise `DB_SCHEMA_VERSION` to 8 and add `FeatureRegistry` (name, version, category,
   description, owner, validation rule, status, created/deprecated timestamps) with
   `UNIQUE(FeatureName,FeatureVersion)`. Migration `7 → 8` runs through
   `ApplyMigration("feature registry", ddl[2])`.
2. Define `ENUM_FEATURE_CATEGORY` (PRICE/VOLATILITY/TREND/SESSION/TIME/STATISTICAL/
   CUSTOM) and `ENUM_FEATURE_STATUS` (ACTIVE/RESERVED/DEPRECATED).
3. Add `CFeatureRegistry` (in `EAData/`): `RegisterFeature()` / `ValidateFeature()` /
   `GetFeature()` / `GetVersion()` / `ListFeatures()`, seeding the 22 snapshot
   features at version 1 on init.
4. Dataset integration: a per-bar sidecar manifest pins
   FeatureVersion + DatasetVersion + LabelVersion + QualityVersion(+status) next to
   every exportable dataset version — no feature ambiguity.

## Consequences
* Feature definitions are versioned, owned and validated; redefinitions are additive
  and never break historical datasets.
* Exports are fully traceable (manifest), complementing the quality gate (ADR-0009).
* Trading runtime untouched; registry work is init-time plus one tiny file per bar.
