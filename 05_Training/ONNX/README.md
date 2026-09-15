# 05_Training/ONNX

ONNX exports for in-EA inference.

Current Stage 8 artifacts:

- `QROS_LogisticRegression_Baseline_v1.onnx`
- `QROS_RandomForest_Baseline_v1.onnx`

Both files pass `onnx.checker.check_model` and are registered in
`CBEA_Models.db.ModelRegistry`.

No model may be promoted to EAContextAI until walk-forward validation, MT5-side
ONNX loading, checksum verification, and replay validation pass.
