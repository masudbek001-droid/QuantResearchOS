# ADR-0020: Continuous Learning — Drift & Retrain Advisory (Sprint 13)

## Status

Accepted. (Implementing Sprint 13 / Continuous Learning)

## Context

- Sprints 9-12 delivered advisory chain: Risk + Research + Bus + Council (56→57 .mqh), all dormant, tests PASS.
- Training pipeline (Sprint 7) has walk-forward variance (logistic 0.3901 std ~0.04) and benchmark sealing — no drift detection or retrain advisory.
- Need advisory drift monitoring (stat baseline vs walk-forward) to suggest retrain without live effect.
- ADR-0015 gates still require advisory only.

## Decision

Implement **Continuous Learning** as drift & retrain advisory (Python + MQL):

1. **Python** `06_Tools/continuous_learning_advisory.py` — loads statistical_baseline_report.json + walk_forward + supervised metrics, computes drift score (WF variance + regime WR drift + feature staleness), outputs retrain_hint NONE/SCHEDULED/URGENT, writes `04_Output/Learning/learning_advisory_report.json` + `03_Documents/Reports/LEARNING_ADVISORY_REPORT.md`.

2. **MQL** `EAContext/EAContextContinuousLearning.mqh` (`CAIContinuousLearning` + `SLearningAdvisory`) — dormant OFF, explicit `CheckDrift(SRiskAdvisory,SCouncilAdvisory,CAIContext)` → drift_score 0..1, retrain_hint, observable, 0 tokens.

3. **Test** `test_continuous_learning_advisory.py` — 0 tokens, 0 TradeManager, drift bounds, hint enums, JSON schema.

## Gates/Rollback

Same as ADR-0015; default OFF, Reset() rollback, no MIPS change.

## References

- STATISTICAL_BASELINE_REPORT, phase_d_walk_forward, RISK/RESEARCH/BUS/COUNCIL reports
