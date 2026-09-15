# Continuous Learning — Advisory Report (ADR-0020)

**Generated:** 2026-09-15 06:48 UTC
**Mode:** drift & retrain advisory (ADR-0020)

## Drift Score 1.00 → Retrain URGENT

- Risk high 0.50, council CAUTION, logistic 0.3901, highWR 49.79%
- Reason: high vol CAUTION regime, council CAUTION, logistic WF 0.3901<0.40 low, high vol WR<50 drift

| Threshold | Hint |
|---|---|
| <0.45 | NONE (stable) |
| 0.45..0.70 | SCHEDULED (next window) |
| >=0.70 | URGENT (drift, retrain) |

## MQL

`CAIContinuousLearning.CheckDrift(SRiskAdvisory,SCouncilAdvisory,CAIContext)` → `SLearningAdvisory {drift_score 0..1, retrain_hint NONE/SCHEDULED/URGENT}` dormant OFF, 0 tokens.
