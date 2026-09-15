# STAGE 10 — MT5 ONNX Runtime Contract Validation

Date: 2026-09-14

## Status

PASS — CLOSED.

Compile gate and active MetaTrader runtime gate both passed.

## Scope

Stage 10 validates that MetaTrader can load the exported ONNX baseline models
and execute a deterministic 22-feature inference call.

## Source & Artifacts

- Script source: `01_Source/EA/MQL5/Scripts/QuantResearchOS_OnnxValidation.mq5`
- Active MT5 script: `C:\Program Files\MetaTrader\MQL5\Scripts\QuantResearchOS_OnnxValidation.ex5`
- Compile log: `04_Output/Logs/compile_onnx_validation.log`
- Logistic ONNX: `C:\Program Files\MetaTrader\MQL5\Files\CBEA\Models\QROS_LogisticRegression_Baseline_v1.onnx`
- Random Forest ONNX: `C:\Program Files\MetaTrader\MQL5\Files\CBEA\Models\QROS_RandomForest_Baseline_v1.onnx`

## Compile Validation

- MetaEditor compile result: 0 errors, 0 warnings
- Active EX5 size: 11,090 bytes

## Runtime Evidence

Active MetaTrader execution on 2026-09-14:

- Logistic Regression: `[QROS_STAGE10] MODEL=PASS`
- Random Forest: `[QROS_STAGE10] MODEL=PASS`
- Final gate: `[QROS_STAGE10] STATUS=PASS | onnx_models=2 | input_dim=22 | output_dim=4`

## Gate Decision

Stage 10 is closed.

No EAContextAI integration is authorized before Stage 10 and replay validation
with model inference both pass.
