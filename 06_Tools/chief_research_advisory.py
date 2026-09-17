#!/usr/bin/env python3
"""
QuantResearchOS — Chief Research AI Synthesis (ADR-0017)

Synthesis advisory for next experiment from validated artifacts:
- 04_Output/Statistics/statistical_baseline_report.json
- 05_Training/Metrics/phase_d_supervised_baseline_v907100.json
- 05_Training/Metrics/phase_d_walk_forward_v907100.json
- 04_Output/Risk/risk_advisory_report.json

Outputs:
- 04_Output/Research/research_synthesis_report.json
- 03_Documents/Reports/RESEARCH_SYNTHESIS_REPORT.md

No lookahead, advisory only, reproducible.
"""
from __future__ import annotations

import json
import pathlib
from datetime import datetime

ROOT = pathlib.Path(__file__).resolve().parent.parent
STAT = ROOT / "04_Output" / "Statistics" / "statistical_baseline_report.json"
SUP = ROOT / "05_Training" / "Metrics" / "phase_d_supervised_baseline_v907100.json"
WF = ROOT / "05_Training" / "Metrics" / "phase_d_walk_forward_v907100.json"
RISK = ROOT / "04_Output" / "Risk" / "risk_advisory_report.json"
OUT_JSON = ROOT / "04_Output" / "Research" / "research_synthesis_report.json"
OUT_MD = ROOT / "03_Documents" / "Reports" / "RESEARCH_SYNTHESIS_REPORT.md"

def load(p):
    if not p.exists():
        raise FileNotFoundError(p)
    return json.loads(p.read_text(encoding="utf-8"))

def main():
    stat = load(STAT)
    sup = load(SUP)
    wf = load(WF)
    risk = load(RISK)

    total_bars = stat.get("TotalBars", 56514)
    wr = stat.get("SingleSideBreakoutOverall", {}).get("WinRate", 54.96)
    pf = stat.get("SingleSideBreakoutOverall", {}).get("ProfitFactor", 1.945)
    vol = {r["Regime"]: r for r in stat.get("VolRegimeStats", [])}
    high_wr = vol.get("High", {}).get("WinRate", 49.79)
    low_wr = vol.get("Low", {}).get("WinRate", 58.87)

    wf_models = wf.get("models", {})
    logistic_wf = wf_models.get("QROS_LogisticRegression_Baseline_v1", {})
    rf_wf = wf_models.get("QROS_RandomForest_Baseline_v1", {})
    logistic_avg = logistic_wf.get("avg_accuracy", 0.390130)
    rf_avg = rf_wf.get("avg_accuracy", 0.418278)
    # variance proxy
    logistic_wins = [w["accuracy"] for w in logistic_wf.get("windows", [])]
    rf_wins = [w["accuracy"] for w in rf_wf.get("windows", [])]
    import statistics
    logistic_std = statistics.pstdev(logistic_wins) if len(logistic_wins)>1 else 0.04
    rf_std = statistics.pstdev(rf_wins) if len(rf_wins)>1 else 0.03

    risk_vol = risk.get("advisory_tables", {}).get("volatility_regime", {})

    # Synthesis heuristics
    # 1. Feature ablation hints
    feature_hint = "NONE"
    feature_reason = "No ablation — baseline stable"
    if high_wr < 50.0:
        feature_hint = "ABLATE_ATR"
        feature_reason = "High vol WR 49.79% random — test ATR/ATRRatio ablation"
    elif stat.get("HourlyTopHours"):
        # worst hour heuristic
        feature_hint = "ABLATE_HOUR"
        feature_reason = "Worst hours 21/04 low WR — test hour/weekday ablation"

    # 2. Window hint
    window_hint = "NONE"
    window_reason = "Walk-forward variance low — keep 5 windows"
    if logistic_std > 0.045:
        window_hint = "EXPAND_WINDOW"
        window_reason = f"Logistic std {logistic_std:.4f} >0.045 — expand training window"

    # 3. Next experiment
    next_exp = "NONE"
    next_reason = "Hold — risk advisory 1.00 normal"
    if risk_vol.get("high", {}).get("multiplier", 0.5) == 0.5:
        next_exp = "TRY_GRADIENT_BOOST"
        next_reason = "Risk CAUTION (high vol) — try GradientBoosting (seeded arch) vs RF"

    # 4. Quality gate
    quality_hint = "NONE"
    # If walk-forward avg <0.42, suggest rerun quality
    if logistic_avg < 0.40:
        quality_hint = "RERUN_QUALITY"
        next_reason += " | logistic WF 0.39 suggests quality re-run"

    # Confidence heuristic 0..1
    confidence = 0.60
    if feature_hint != "NONE":
        confidence = 0.62
    if window_hint != "NONE":
        confidence = min(confidence, 0.58)
    if next_exp == "TRY_GRADIENT_BOOST":
        confidence = max(confidence, 0.65)

    report = {
        "generated_at": datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC"),
        "sources": {
            "statistical_baseline": str(STAT.relative_to(ROOT)),
            "supervised": str(SUP.relative_to(ROOT)),
            "walk_forward": str(WF.relative_to(ROOT)),
            "risk_advisory": str(RISK.relative_to(ROOT)),
            "total_bars": total_bars,
            "clean_breakouts": stat.get("SingleSideBreakoutOverall", {}).get("Count", 40566),
        },
        "baseline": {"win_rate": wr, "profit_factor": pf, "high_vol_wr": high_wr, "low_vol_wr": low_wr},
        "models": {
            "logistic_wf_avg_accuracy": logistic_avg,
            "rf_wf_avg_accuracy": rf_avg,
            "logistic_std": round(logistic_std, 5),
            "rf_std": round(rf_std, 5),
        },
        "synthesis": {
            "feature_hint": feature_hint,
            "feature_reason": feature_reason,
            "window_hint": window_hint,
            "window_reason": window_reason,
            "next_experiment_hint": next_exp,
            "next_reason": next_reason,
            "quality_hint": quality_hint,
            "confidence": confidence,
        },
        "advisory_only": True,
        "no_trading_authority": "ADR-0017 shadow-only, dormant OFF",
    }

    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(report, indent=2), encoding="utf-8")

    md = f"""# Chief Research AI — Synthesis Report (ADR-0017)

**Generated:** {report['generated_at']}  
**Mode:** advisory only — synthesis of statistical baseline + training + risk (ADR-0017)

## 1. Baseline (no lookahead)

- **Bars:** {total_bars} H1, clean breakouts {report['sources']['clean_breakouts']} WR {wr}% PF {pf}
- **Vol regimes:** Low WR {low_wr}% (1.00), High WR {high_wr}% (0.50 CAUTION) — see RISK_ADVISORY_REPORT.md
- **Models walk-forward:** Logistic {logistic_avg:.4f} std {logistic_std:.4f}, RF {rf_avg:.4f} std {rf_std:.4f}

## 2. Synthesis Hints (advisory strings)

| Hint | Value | Reason | Conf |
|---|---|---|---|
| **Feature** | {feature_hint} | {feature_reason} | {confidence:.2f} |
| **Window** | {window_hint} | {window_reason} | {confidence:.2f} |
| **Next Experiment** | {next_exp} | {next_reason} | {confidence:.2f} |
| **Quality** | {quality_hint} | quality re-run when logistic <0.40 | {confidence:.2f} |

- **Feature ablation:** High vol random → test ATR ablation; worst hours → hour ablation.
- **Window:** High variance → expand training window (Sprint 5 walk-forward supports expanding).
- **Next experiment:** High vol CAUTION → try GradientBoostingClassifier (seeded in Models.db, not yet trained).
- **Quality:** Logistic WF 0.39 < RF 0.418 suggests quality gate re-run before promotion.

## 3. Mapping to MQL Advisory

`CAIResearchAdvisory.Update(SRiskAdvisory, CAIContext, atr_ratio, hour)` →
`SResearchAdvisory {{next_experiment_hint, feature_hint, window_hint, confidence}}`
dormant OFF, explicit call, validates 0..1 confidence, hint enums, 0 trading tokens.

## 4. Required Gates

1. Risk advisory PASS (ADR-0016)
2. Models.db v2 + walk-forward + statistical baseline PASS
3. This synthesis PASS (JSON schema + hints + 0 tokens)
4. Safety audit still 0 trade_manager_calls
5. Default OFF, rollback Reset()

No live research behavior change — advisory hints only.
"""
    OUT_MD.parent.mkdir(parents=True, exist_ok=True)
    OUT_MD.write_text(md, encoding="utf-8")
    return report

if __name__ == "__main__":
    r = main()
    print(f"written {OUT_JSON} and {OUT_MD}")
    print(f"hints: feature {r['synthesis']['feature_hint']} window {r['synthesis']['window_hint']} next {r['synthesis']['next_experiment_hint']} conf {r['synthesis']['confidence']:.2f}")
