# AI Council — Advisory Report (ADR-0019)

**Generated:** 2026-09-15 06:48 UTC  
**Mode:** advisory multi-agent consensus (ADR-0019)

## Weights
Risk 0.35 / Research 0.25 / Shadow 0.25 / Bus 0.15

## Examples

| Regime | Council mult | Vote | Reason |
|---|---|---|---|
| calm (low vol 1.00) | 0.95 | NORMAL | all agents calm |
| reduced (normal worst 0.54) | 0.85 | REDUCED | Risk reduced |
| caution (high vol 0.50) | 0.83 | CAUTION | Risk CAUTION dominates |

Confidence 0.64 (research 0.65, logistic wf 0.3901)

## MQL

`CAIAICouncil.Convene(SRiskAdvisory,SResearchAdvisory,SBusAdvisory,CAIContext)` →
`SCouncilAdvisory {council_multiplier 0.50..1.50, council_confidence 0..1, council_vote, reason}` dormant OFF, 0 tokens.
