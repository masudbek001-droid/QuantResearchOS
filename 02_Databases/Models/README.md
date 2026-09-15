# 02_Databases/Models — Models.db

Runtime file: `C:\Program Files\MetaTrader\MQL5\Files\CBEA_Models.db`.

Current status:

- `ModelsSchemaVersion = 2`
- `ModelArchitectures`: seeded baseline architecture catalog
- `ModelRegistry`: trained research model registry
- `FeatureVectorContracts`: deterministic model input ordering
- `ModelEvaluations`: train/validation/test evaluation audit trail

The database is active for research/shadow-only artifacts (Stages 8–14 PASS). Walk-forward validation and MT5-side ONNX loading have PASSED (Stages 9–11). Live EA integration remains blocked until a future ADR authorizes advisory behavior and a Strategy Tester/replay regression gate passes (ADR-0015).
