# ADR-0018: Decision Bus — Advisory Consensus Routing (Sprint 11)

## Status

Accepted. (Implementing Sprint 11 / Decision Bus)

## Context

- Sprint 9-10 delivered advisory Risk AI (vol/hourly/confidence 0.50..1.50) and advisory Research AI (feature/window/next hints 0.60..0.65) — both dormant OFF, 55 .mqh, tests PASS, no trading authority.
- Shadow AI (Stage 6) remains disabled default, valid predictions but weak walk-forward (0.39/0.42).
- No consensus layer exists to show how Risk + Research + Shadow would vote together — triage still manual.
- ADR-0015 gates: advisory only until production ADR, no live decision change.

## Decision

Implement **Decision Bus** as **advisory consensus routing** (Python + MQL, advisory only):

1. **Python** `06_Tools/decision_bus_advisory.py`:
   - Loads `risk_advisory_report.json` + `research_synthesis_report.json` + `statistical_baseline_report.json` + `phase_d_walk_forward_v907100.json`.
   - Computes per-bar hypothetical vote: Risk multiplier × Research confidence → bus multiplier 0.50..1.50, bus flag NORMAL/REDUCED/CAUTION/ELEVATED, bus hint NONE/RESEARCH/ RISK, consensus string. No DB writes, no lookahead (means only).
   - Outputs `04_Output/DecisionBus/decision_bus_report.json` + `03_Documents/Reports/DECISION_BUS_REPORT.md`, reproducible.

2. **MQL** `EAContext/EAContextDecisionBus.mqh` (`CAIDecisionBus` + `SBusAdvisory`):
   - Dormant OFF, explicit `Route(SRiskAdvisory, SResearchAdvisory, CAIContext)` → `SBusAdvisory {bus_multiplier, bus_flag, bus_hint, consensus_reason}` observable only.
   - Never calls TradeManager/CRiskManager/CExitEngine/OrderSend. Validates 0.50..1.50, flags priority ELEVATED>CAUTION>REDUCED>NORMAL.
   - Wraps Risk + Research advisories, ready for future wire behind flag when tester proves no MIPS regression.

3. **Safety**: Same as ADR-0015/0016/0017 — 0 tokens, default OFF, Reset() rollback, test `test_decision_bus_advisory.py` checks 0 forbidden tokens, 0 TradeManager calls, multiplier bounds, flag priority, JSON schema.

## Gates

- Risk PASS + Research PASS + Shadow PASS (Stages 6-7 + ADR-0016/0017).
- Decision Bus validation PASS + safety audit (0 tokens, 0 trade_manager_calls).

## Rollback

Reset() + disable; MIPS v1.0 unchanged.

## References
- RISK_ADVISORY_REPORT.md, RESEARCH_SYNTHESIS_REPORT.md, STATISTICAL_BASELINE_REPORT, phase_d_walk_forward
