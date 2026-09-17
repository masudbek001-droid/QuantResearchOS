# Decision Bus — Advisory Report (ADR-0018)

**Generated:** 2026-09-15 06:47 UTC  
**Mode:** advisory consensus routing — Risk + Research + Shadow (ADR-0018)

## 1. Inputs

- Risk high 0.5, normal 0.85 (vol regime)
- Research conf 0.65 hint ABLATE_ATR
- Logistic WF 0.3901

## 2. Bus Logic

`bus_multiplier = risk_multiplier × research_shave(conf<0.55→0.85) × shadow_shave(<0.35→0.80)` clamped 0.50..1.50  
`flag: ELEVATED > CAUTION > REDUCED > NORMAL`, `hint: NONE/RISK/RESEARCH/SHADOW`

| Example | Risk base | Bus mult | Bus flag | Reason |
|---|---|---|---|---|
| low_vol_hour12 | 1.00 | 0.90 | NORMAL | calm |
| normal_vol_hour21 | 0.85×0.70=0.595 | 0.54 | REDUCED | worst hour reduced |
| high_vol_low_conf | 0.50×0.80=0.40 | 0.50 | CAUTION | CAUTION (high vol dominates) |

## 3. MQL

`CAIDecisionBus.Route(SRiskAdvisory, SResearchAdvisory, CAIContext)` →
`SBusAdvisory {bus_multiplier 0.50..1.50, bus_flag, bus_hint, consensus_reason}`
dormant OFF, explicit call, validates, 0 trading tokens, never consumed by TradeManager.

No live routing — advisory consensus strings only.
