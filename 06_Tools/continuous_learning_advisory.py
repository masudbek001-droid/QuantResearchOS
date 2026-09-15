#!/usr/bin/env python3
"""Continuous Learning advisory (ADR-0020) — drift and retrain."""
import json
import pathlib
from datetime import datetime

ROOT = pathlib.Path(__file__).resolve().parent.parent
RISK = ROOT / "04_Output/Risk/risk_advisory_report.json"
COUNCIL = ROOT / "04_Output/Council/council_report.json"
WF = ROOT / "05_Training/Metrics/phase_d_walk_forward_v907100.json"
STAT = ROOT / "04_Output/Statistics/statistical_baseline_report.json"
OUT_JSON = ROOT / "04_Output/Learning/learning_advisory_report.json"
OUT_MD = ROOT / "03_Documents/Reports/LEARNING_ADVISORY_REPORT.md"

def load(p):
    return json.loads(p.read_text(encoding="utf-8"))

def main():
    risk = load(RISK)
    council = load(COUNCIL)
    wf = load(WF)
    stat = load(STAT)
    logistic = wf["models"]["QROS_LogisticRegression_Baseline_v1"]["avg_accuracy"]
    high_wr = stat["VolRegimeStats"][2]["WinRate"] if len(stat.get("VolRegimeStats", [])) >= 3 else 49.79
    drift = 0.25
    reason = []
    if risk["advisory_tables"]["volatility_regime"]["high"]["multiplier"] == 0.5:
        drift += 0.25
        reason.append("high vol CAUTION regime")
    if council["council"]["examples"]["caution"]["vote"] == "CAUTION":
        drift += 0.20
        reason.append("council CAUTION")
    if logistic < 0.40:
        drift += 0.20
        reason.append(f"logistic WF {logistic:.4f}<0.40 low")
    if high_wr < 50:
        drift += 0.10
        reason.append("high vol WR<50 drift")
    drift = min(1.0, round(drift, 2))
    hint = "NONE"
    if drift >= 0.70:
        hint = "URGENT"
    elif drift >= 0.45:
        hint = "SCHEDULED"
    if not reason:
        reason.append("stable baseline")
    report = {
        "generated_at": datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC"),
        "sources": {
            "risk": str(RISK.relative_to(ROOT)),
            "council": str(COUNCIL.relative_to(ROOT)),
            "wf": str(WF.relative_to(ROOT)),
        },
        "inputs": {
            "logistic_wf": logistic,
            "high_vol_wr": high_wr,
            "council_caution": council["council"]["examples"]["caution"]["vote"],
        },
        "drift": {
            "drift_score": drift,
            "retrain_hint": hint,
            "reason": ", ".join(reason),
        },
        "advisory_only": True,
    }
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(report, indent=2), encoding="utf-8")
    md = f"""# Continuous Learning — Advisory Report (ADR-0020)

**Generated:** {report['generated_at']}
**Mode:** drift & retrain advisory (ADR-0020)

## Drift Score {drift:.2f} → Retrain {hint}

- Risk high 0.50, council CAUTION, logistic {logistic:.4f}, highWR {high_wr}%
- Reason: {", ".join(reason)}

| Threshold | Hint |
|---|---|
| <0.45 | NONE (stable) |
| 0.45..0.70 | SCHEDULED (next window) |
| >=0.70 | URGENT (drift, retrain) |

## MQL

`CAIContinuousLearning.CheckDrift(SRiskAdvisory,SCouncilAdvisory,CAIContext)` → `SLearningAdvisory {{drift_score 0..1, retrain_hint NONE/SCHEDULED/URGENT}}` dormant OFF, 0 tokens.
"""
    OUT_MD.write_text(md, encoding="utf-8")
    return report

if __name__ == "__main__":
    r = main()
    print(f"written {OUT_JSON} and {OUT_MD}")
    print(r["drift"])
