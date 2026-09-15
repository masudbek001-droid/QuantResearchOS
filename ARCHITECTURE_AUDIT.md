# Architecture Audit — 2026-09-15

## Scope

Audit root: `C:\QuantResearchOS`. The project source is under `01_Source`; the active compiler is `C:\Program Files\MetaTrader\MetaEditor64.exe`.

## Findings

- Source tree is present under `C:\QuantResearchOS\01_Source\EA\MQL5`.
- Active compiler/runtime target is `C:\Program Files\MetaTrader`.
- Trading core remains frozen by MIPS v1.0.
- Context, Feature Builder, Data Access, History, Replay, Research, Model, ONNX,
  and Shadow AI layers are now validated through Stage 15 (final reconciliation PASS).
- `CTradeManager` owns runtime services. Research/replay/history remain dormant
  unless invoked through explicit validation/API paths.
- `CAIShadowInference` is observation-only and not consumed by `CTradeManager`.
- `CBEA_Models.db` is schema v2 with registered baseline models, feature-vector
  contracts, evaluations, and ONNX metadata.

## Status

Architecture is verified through Stage 15. AI remains research/shadow-only and is
not promoted to live trading authority.
