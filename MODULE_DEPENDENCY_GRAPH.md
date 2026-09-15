# Module Dependency Graph

`CandleBreakoutEA.mq5` → `EASettings` + `EALogger` + `EATradeManager`

`EATradeManager` → trading core → context → feature builder → data access/writers → replay → research → history → dashboard/visuals.

Database ownership is centralized in `CDatabaseManager`, which owns the provider and delegates schema/version validation. Replay, research and history are initialized as dormant services and are invoked through explicit APIs.

Model/research tooling:

`CBEA_Market.db` → `train_phase_d_models.py` → `05_Training/FeatureVectors` →
`05_Training/Models` + `05_Training/ONNX` → `CBEA_Models.db`.

Shadow AI:

`CAIShadowInference` → `OnnxCreate/OnnxRun/OnnxRelease` → `CAIContext`.

There is deliberately no dependency from `CTradeManager` to `CAIShadowInference`.
AI predictions cannot affect entries, orders, risk, or exits.

The compiler include trace is the authoritative include graph for this audit.
