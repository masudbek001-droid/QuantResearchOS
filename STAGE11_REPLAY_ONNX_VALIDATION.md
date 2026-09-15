# STAGE 11 — Replay + ONNX Inference Validation

Date: 2026-09-14

## Status

PASS — CLOSED.

Compile gate and active MetaTrader replay+ONNX runtime gate both passed.

## Scope

Stage 11 validates that model inference can run during deterministic replay
without touching live trading logic.

## Source & Artifacts

- Script source: `01_Source/EA/MQL5/Scripts/QuantResearchOS_ReplayOnnxValidation.mq5`
- Active MT5 script: `C:\Program Files\MetaTrader\MQL5\Scripts\QuantResearchOS_ReplayOnnxValidation.ex5`
- Compile log: `04_Output/Logs/compile_replay_onnx_validation.log`
- Replay DB: `candlebreakout_911001.db`
- Models:
  - `CBEA\Models\QROS_LogisticRegression_Baseline_v1.onnx`
  - `CBEA\Models\QROS_RandomForest_Baseline_v1.onnx`

## Compile Validation

- MetaEditor compile result: 0 errors, 0 warnings
- Active EX5 size: 59,680 bytes

## Runtime Evidence

Active MetaTrader execution on 2026-09-14:

- Replay timeline loaded: 5 bars, 2026-01-05 00:00 to 2026-01-05 04:00
- Logistic Regression and Random Forest ONNX models loaded on CPU.
- Inference passed on every replay bar.
- Probability sums validated at 1.0000 for both models on every bar.
- Final gate:
  `[QROS_STAGE11] STATUS=PASS | replay_id=1 | bars=5 | inferences=10 | state=REPLAY_FINISHED`

## Gate Decision

Stage 11 is closed.

Next gate: controlled EAContextAI integration planning. No live trading behavior
may change until promotion rules and a rollback path are documented and validated.
