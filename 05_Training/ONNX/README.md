# 05_Training/ONNX

ONNX exports for in-EA inference.

Current Stage 8 artifacts:

- `QROS_LogisticRegression_Baseline_v1.onnx`
- `QROS_RandomForest_Baseline_v1.onnx`

Both files pass `onnx.checker.check_model` and are registered in
`CBEA_Models.db.ModelRegistry` with checksums.

Walk-forward validation (Stage 9), MT5-side ONNX loading (Stage 10), checksum verification, and replay+ONNX validation (Stage 11) have all PASSED. Promotion to advisory/production remains blocked until a future ADR and Strategy Tester regression gate pass (ADR-0015). Current mode is shadow-only inference via `CAIShadowInference` (Stage 13–14 PASS).
