# ADR-0015: AI Promotion and Safety Gates

## Status

Accepted.

## Context

Stages 8–11 created, exported, and validated baseline ONNX research models:

- local supervised training passed;
- ONNX export passed;
- walk-forward evaluation passed;
- MT5-side ONNX loading passed;
- replay-time ONNX inference passed.

These validations prove technical feasibility. They do **not** authorize live
strategy changes.

The trading core remains frozen by MIPS v1.0:

- entry frequency is final;
- AI may not silently veto mandatory strategy semantics;
- the Exit Engine remains the only exit-intelligence authority;
- the risk manager remains the only trading gate for hours and daily limits;
- no model may create, modify, or close orders directly.

## Decision

AI integration is allowed only through guarded, staged promotion:

1. **Research-only**
   - Models may be trained, evaluated, exported, replayed, and recorded.
   - No live trading behavior changes.

2. **Shadow inference**
   - EA may load a validated ONNX model and write predictions to `CAIContext`.
   - Predictions are observable only.
   - No entry, order, risk, or exit decision may read AI as an authority.

3. **Advisory sizing / management**
   - Requires a new ADR and tester evidence.
   - AI may influence only explicitly allowed advisory fields.
   - AI may not block mandatory entries if the strategy contract requires entry.
   - AI may not bypass risk manager blocks.
   - AI may not bypass or reorder Exit Engine priorities.

4. **Production candidate**
   - Requires reproducible training artifact, feature contract, ONNX checksum,
     walk-forward report, replay report, Strategy Tester report, rollback plan,
     and explicit status in `ModelRegistry`.

## Mandatory gates before any live effect

1. `CBEA_Models.db` integrity OK.
2. `ModelRegistry` row exists and references an ONNX file by checksum.
3. `FeatureVectorContracts` exactly match the 22-feature inference order.
4. ONNX checker passes.
5. MT5 ONNX script load/inference passes.
6. Replay+ONNX inference passes.
7. Walk-forward evaluation passes.
8. Strategy Tester pass verifies no entry/exit/risk invariant regression.
9. Rollback procedure restores AI disabled state without source edits.

## Rollback rule

The default state is AI disabled. If any AI gate fails:

- unload model handle;
- reset `CAIContext`;
- keep trading core behavior identical to MIPS v1.0;
- record the failed gate in `CHANGELOG.md` and the relevant stage report.

## Consequences

- AI can be added without corrupting the frozen trading architecture.
- Research artifacts remain auditable and reproducible.
- Live behavior cannot change accidentally because shadow inference is the first
  and only initially authorized integration mode.
