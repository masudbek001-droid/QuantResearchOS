# ADR-0019: AI Council — Multi-Agent Advisory Consensus (Sprint 12)

## Status

Accepted. (Implementing Sprint 12 / AI Council)

## Context

- Sprints 9-11 delivered Risk (ADR-0016), Research (ADR-0017), Decision Bus (ADR-0018) — all advisory only, dormant, 56 .mqh, tests PASS.
- No multi-agent council exists to show weighted consensus of 4 agents (Risk, Research, Shadow AI, Statistical Baseline).
- ADR-0015 gates still require advisory only.

## Decision

Implement **AI Council** as advisory consensus (Python + MQL):

1. **Python** `06_Tools/ai_council_advisory.py` — loads risk, research, decision_bus, baseline, wf → weights Risk 0.35 / Research 0.25 / Shadow 0.25 / Baseline 0.15 → council_multiplier 0.50..1.50, council_confidence, council_vote NORMAL/REDUCED/CAUTION/ELEVATED, council_hint. Outputs `04_Output/Council/council_report.json` + `03_Documents/Reports/COUNCIL_REPORT.md`.

2. **MQL** `EAContext/EAContextAICouncil.mqh` (`CAIAICouncil` + `SCouncilAdvisory`) — dormant OFF, explicit `Convene(SRiskAdvisory,SResearchAdvisory,SBusAdvisory,CAIContext)` → council advisory observable, never calls trading, 0 tokens, Validate 0.50..1.50.

3. **Test** `test_ai_council_advisory.py` — 0 tokens, 0 TradeManager calls, bounds, JSON schema.

## Gates/Rollback

Same as ADR-0015; council default OFF, Reset() rollback, no MIPS change.

## References

- ADR-0016/0017/0018, STATISTICAL_BASELINE_REPORT, phase_d_walk_forward
