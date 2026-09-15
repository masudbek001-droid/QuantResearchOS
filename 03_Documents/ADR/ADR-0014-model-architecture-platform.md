# ADR-0014: Model Architecture Platform (`Models.db` Schema v2, Feature Vector Contracts, Model Lifecycle)

## Status

Accepted.

## Context

Sprint 6A established the four-database architecture (`Ticks.db`, `Market.db`, `Models.db`, and `Research.db`). `Models.db` was seeded as schema-only (`ModelsSchemaVersion` = 1).

To transition from raw historical bars and observations (Sprints 4–6A) into reproducible machine learning and statistical modeling (Sprints 7–9), a formal schema and contract layer is required to store:
1. Model architectures and frameworks (scikit-learn, XGBoost, ONNX).
2. Version-pinned trained models with full hyperparameter and performance metrics tracking.
3. Feature vector input contracts (defining the exact order, types, and normalization parameters mapping from `CFeatureRegistry` to the ONNX tensor input).
4. Out-of-sample and walk-forward evaluation audit trails.

## Decision

1. Extend `Models.db` to schema v2 (`ModelsSchemaVersion` = 2) with the following relational tables:
   - `ModelArchitectures`: Catalogues model families (LogisticRegression, RandomForest, GradientBoosting, MLP) and input/output tensor specifications.
   - `ModelRegistry`: Official repository of trained models, pinning `DatasetVersion`, `FeatureVersion`, `LabelVersion`, hyperparameters JSON, metric scores, ONNX file paths, and deployment states (`EXPERIMENTAL`, `CANDIDATE`, `PRODUCTION`, `RETIRED`).
   - `FeatureVectorContracts`: Strict ordering and normalization specifications for every input feature fed to the model, ensuring zero training-inference skew.
   - `ModelEvaluations`: Audit trail of in-sample, out-of-sample, and walk-forward validation passes.
2. Maintain strict DAL isolation: trading core remains frozen; models are loaded into the EA only through the reserved `EAContextAI` slot via validated ONNX runtime contracts.

## Consequences

- **Positive**: Complete reproducibility from dataset rows to ONNX deployment. Eliminates any feature ordering or scaling discrepancies between Python training and MQL5 inference.
- **Negative**: Adds schema migration management for `Models.db`.
- **Mitigation**: Follow the established idempotent migration pattern with `ModelsSchemaVersion` tracking and additive DDL.
