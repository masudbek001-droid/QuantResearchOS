# FEATURE REGISTRY — `FeatureRegistry` (schema v8)

Implemented by Task 0012 under ADR-0010. The Feature Registry is the **official
catalogue of all market features** — the only source of truth for feature definitions.
Every calculated feature carries a name, version, category, description, owner,
validation rule and calculation status.

## 1. Schema

### `FeatureRegistry`

`FeatureID` (PK autoinc) · `FeatureName` · `FeatureVersion` · `FeatureCategory` ·
`Description` · `Owner` · `ValidationRule` · `Status` (`ENUM_FEATURE_STATUS`: ACTIVE /
RESERVED / DEPRECATED) · `CreatedAt` · `DeprecatedAt` (nullable) ·
`UNIQUE(FeatureName, FeatureVersion)` + `idx_feature_name(FeatureName)`

Versioning is additive: a redefined feature gets a new version row, old versions are
kept (optionally marked DEPRECATED with a timestamp) so any historical dataset stays
interpretable.

## 2. Categories (STEP 2)

`FEATURE_PRICE(0)`, `FEATURE_VOLATILITY(1)`, `FEATURE_TREND(2)`, `FEATURE_SESSION(3)`,
`FEATURE_TIME(4)`, `FEATURE_STATISTICAL(5)`, `FEATURE_CUSTOM(6)`.

## 3. Registrar (STEP 3) — `CFeatureRegistry`

```
bool RegisterFeature(name,version,category,description,owner,validation_rule);
bool ValidateFeature(name,version,category,validation_rule);
bool GetFeature(name,version,SFeatureInfo&);
int  GetVersion(name);            // newest non-deprecated version
int  ListFeatures(string &lines[]);
void SeedStandardFeatures(void);  // the official catalogue, v1
```

On init the registry seeds the 22 `SFeatureSnapshot` features at version 1 with their
owners (`CFeatureBuilder`) and validation rules (ranges, finiteness, boolean) — the
same rules the Feature Builder validation already enforces at runtime.

## 4. Dataset integration (STEP 4)

Every exported dataset is pinned by a sidecar manifest
(`MQL5/Files/CBEA/dataset_v<n>.manifest.txt`, refreshed each completed bar):

```
DatasetVersion=1
FeatureVersion=1        (+ FeatureCount)
LabelVersion=1
QualityVersion=<QualityID of the latest quality report>
QualityStatus=<status>
GeneratedAt=...
```

FeatureVersion + DatasetVersion + LabelVersion + QualityVersion travel together —
**no feature ambiguity**: any exported file can be traced back to exact definitions,
labels and the quality verdict it passed under.

## 5. Validation (STEP 5)

Registration rejects: duplicate `FeatureName+FeatureVersion` (idempotent no-op when
identical intent, blocked by the UNIQUE constraint), invalid version (≤0), missing
validation rule (empty), unknown category (outside the enum).

## 6. Runtime policy

Registration is idempotent and runs at init; the manifest refresh is one small file
write per completed bar. Trading code never reads the registry; all SQL goes through
the DAL.
