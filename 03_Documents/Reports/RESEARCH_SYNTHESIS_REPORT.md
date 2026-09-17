# Chief Research AI — Synthesis Report (ADR-0017)

**Generated:** 2026-09-15 06:46 UTC  
**Mode:** advisory only — synthesis of statistical baseline + training + risk (ADR-0017)

## 1. Baseline (no lookahead)

- **Bars:** 56514 H1, clean breakouts 40566 WR 54.96% PF 1.945
- **Vol regimes:** Low WR 58.87% (1.00), High WR 49.79% (0.50 CAUTION) — see RISK_ADVISORY_REPORT.md
- **Models walk-forward:** Logistic 0.3901 std 0.0397, RF 0.4183 std 0.0210

## 2. Synthesis Hints (advisory strings)

| Hint | Value | Reason | Conf |
|---|---|---|---|
| **Feature** | ABLATE_ATR | High vol WR 49.79% random — test ATR/ATRRatio ablation | 0.65 |
| **Window** | NONE | Walk-forward variance low — keep 5 windows | 0.65 |
| **Next Experiment** | TRY_GRADIENT_BOOST | Risk CAUTION (high vol) — try GradientBoosting (seeded arch) vs RF | logistic WF 0.39 suggests quality re-run | 0.65 |
| **Quality** | RERUN_QUALITY | quality re-run when logistic <0.40 | 0.65 |

- **Feature ablation:** High vol random → test ATR ablation; worst hours → hour ablation.
- **Window:** High variance → expand training window (Sprint 5 walk-forward supports expanding).
- **Next experiment:** High vol CAUTION → try GradientBoostingClassifier (seeded in Models.db, not yet trained).
- **Quality:** Logistic WF 0.39 < RF 0.418 suggests quality gate re-run before promotion.

## 3. Mapping to MQL Advisory

`CAIResearchAdvisory.Update(SRiskAdvisory, CAIContext, atr_ratio, hour)` →
`SResearchAdvisory {next_experiment_hint, feature_hint, window_hint, confidence}`
dormant OFF, explicit call, validates 0..1 confidence, hint enums, 0 trading tokens.

## 4. Required Gates

1. Risk advisory PASS (ADR-0016)
2. Models.db v2 + walk-forward + statistical baseline PASS
3. This synthesis PASS (JSON schema + hints + 0 tokens)
4. Safety audit still 0 trade_manager_calls
5. Default OFF, rollback Reset()

No live research behavior change — advisory hints only.
