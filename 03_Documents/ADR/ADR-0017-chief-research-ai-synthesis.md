# ADR-0017: Chief Research AI — Research Synthesis Advisory (Sprint 10)

## Status

Accepted. (Implementing Sprint 10 / Chief Research AI)

## Context

- Sprint 9 / ADR-0016 delivered Chief Risk AI advisory (CAIRiskAdvisory, risk_advisory_report.json, test PASS) — advisory only, dormant OFF, 54 .mqh.
- Research Platform (Sprint 5 / ADR-0012) holds immutable Experiments, deterministic Benchmarks (9 metrics), WalkForward windows — all PASS (Stage 7).
- Training pipeline (Sprint 7) and statistical baseline (Phase C) are reproducible: 56,514 H1 bars, 40,566 clean breakouts (WR 54.96% PF 1.95), volatility/hourly stratification, 2 baselines with walk-forward avg_accuracy 0.39–0.42.
- No research synthesis exists that automatically turns experiment/benchmark/walk-forward/model artifacts into **advisory next-experiment recommendations**. Manual triage is engineering bottleneck.
- ADR-0015 gates still hold: advisory only until production ADR; cannot alter trading logic.

## Decision

Implement **Chief Research AI** as **research-side advisory synthesis** (Python research, no MQL trading authority):

1. **Python research tool** `06_Tools/chief_research_advisory.py`:
   - Loads: `statistical_baseline_report.json` (regime/hourly), `phase_d_supervised_baseline_v907100.json`, `phase_d_walk_forward_v907100.json`, `risk_advisory_report.json` (ADR-0016).
   - Synthesizes: per-regime expectancy vs model accuracy, hourly expectancy vs model calibration, walk-forward variance, feature importance proxy (ATR/Range/Trend vs label), benchmark completeness (9 metrics), experiment sealing audit.
   - Outputs: `04_Output/Research/research_synthesis_report.json` (machine) + `03_Documents/Reports/RESEARCH_SYNTHESIS_REPORT.md` (human) — reproducible, no DB writes, no lookahead (uses only closed-bar aggregates + walk-forward means).
   - Advisory recommendations (strings only): next feature to ablate, next model to try (e.g., GradientBoosting), next window to expand, data quality gate to re-run.

2. **MQL advisory stub** `EAContext/EAContextResearchAdvisory.mqh` (`CAIResearchAdvisory`):
   - Pure advisory, dormant OFF, explicit `Update()` reading `SRiskAdvisory` + `CAIContext` + market regime, outputs `SResearchAdvisory { next_experiment_hint, feature_hint, window_hint, confidence }` — observable via logger, never gates trading, zero trading tokens.
   - Validates multiplier bounds, hint enums, no OrderSend/PositionClose/CRiskManager/CExitEngine calls.

3. **Safety invariants** (ADR-0015/0016 preserved):
   - No DB writes, no file writes from MQL, no trade blocking, no risk bypass, no exit reorder.
   - Default OFF; rollback = `Reset()`.
   - Tested by `01_Source/Tests/test_chief_research_ai.py` → 0 forbidden tokens, hint enums valid, synthesis JSON schema PASS, no lookahead.

## Mandatory Gates Before Any Live Effect

Same as ADR-0015 gates 1–7 PLUS:
- Research synthesis validation PASS (JSON schema, hint enums, 0 tokens).
- Safety audit `trade_manager_calls=0` still holds (new advisory not consumed).

## Rollback Rule

Identical to ADR-0015: `Reset()` + disable flag, MIPS v1.0 unchanged.

## Consequences

- Research triage becomes automated and auditable; next-experiment hints are reproducible from committed JSON.
- No live behavior change — advisory strings only until future ADR explicitly wires them behind flag with tester evidence.

## References
- `STATISTICAL_BASELINE_REPORT.md` (WR 54.96% PF 1.95, volv3 hourly)
- `phase_d_*` metrics (walk-forward 0.39/0.42)
- `RISK_ADVISORY_REPORT.md` (vol/hourly/confidence tables)
- `STAGE7_RESEARCH_VALIDATION.md` (9 metrics, sealing)
