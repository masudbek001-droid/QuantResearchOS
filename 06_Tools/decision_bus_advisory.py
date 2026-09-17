#!/usr/bin/env python3
"""
QuantResearchOS — Decision Bus Advisory (ADR-0018)

Loads risk + research synthesis + baseline + walk-forward, computes
advisory bus multiplier/flag/hint consensus per regime.

Outputs:
- 04_Output/DecisionBus/decision_bus_report.json
- 03_Documents/Reports/DECISION_BUS_REPORT.md

Advisory only, no trading authority, reproducible.
"""
import json, pathlib
from datetime import datetime

ROOT = pathlib.Path(__file__).resolve().parent.parent
RISK = ROOT / "04_Output" / "Risk" / "risk_advisory_report.json"
RES = ROOT / "04_Output" / "Research" / "research_synthesis_report.json"
STAT = ROOT / "04_Output" / "Statistics" / "statistical_baseline_report.json"
WF = ROOT / "05_Training" / "Metrics" / "phase_d_walk_forward_v907100.json"
OUT_JSON = ROOT / "04_Output" / "DecisionBus" / "decision_bus_report.json"
OUT_MD = ROOT / "03_Documents" / "Reports" / "DECISION_BUS_REPORT.md"


def load(p):
    return json.loads(p.read_text(encoding="utf-8"))


def main():
    risk = load(RISK)
    res = load(RES)
    stat = load(STAT)
    wf = load(WF)

    risk_vol = risk["advisory_tables"]["volatility_regime"]
    # synthetic per-regime bus: risk mult * research conf shave
    research_conf = res["synthesis"]["confidence"]
    syn_feature = res["synthesis"]["feature_hint"]
    vol_high_mult = risk_vol["high"]["multiplier"]  # 0.50
    vol_normal_mult = risk_vol["normal"]["multiplier"]  # 0.85

    def bus_multiplier(base):
        m = base
        if research_conf < 0.55:
            m *= 0.85
        # walk-forward logistic low -> shave
        if wf["models"]["QROS_LogisticRegression_Baseline_v1"]["avg_accuracy"] < 0.40:
            m *= 0.90
        m = max(0.50, min(1.50, round(m, 2)))
        return m

    examples = {
        "low_vol_hour12": bus_multiplier(1.00),
        "normal_vol_hour21": bus_multiplier(0.85 * 0.70),
        "high_vol_low_conf": bus_multiplier(0.50 * 0.80),
    }

    bus_flag_for = {}
    for k, v in examples.items():
        if risk["advisory_tables"]["volatility_regime"]["high"]["multiplier"] == 0.5 and "high" in k:
            flag = "CAUTION" if v >= 0.50 else "ELEVATED"
            # elevated only when daily tight
            if v == 0.50:
                flag = "CAUTION"
            bus_flag_for[k] = flag
        elif v < 0.90:
            bus_flag_for[k] = "REDUCED"
        else:
            bus_flag_for[k] = "NORMAL"
    # override high to CAUTION
    bus_flag_for["high_vol_low_conf"] = "CAUTION"

    report = {
        "generated_at": datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC"),
        "sources": {
            "risk": str(RISK.relative_to(ROOT)),
            "research": str(RES.relative_to(ROOT)),
            "baseline": str(STAT.relative_to(ROOT)),
        },
        "inputs": {
            "risk_high_mult": vol_high_mult,
            "risk_normal_mult": vol_normal_mult,
            "research_confidence": research_conf,
            "research_feature_hint": syn_feature,
            "logistic_wf": wf["models"]["QROS_LogisticRegression_Baseline_v1"]["avg_accuracy"],
        },
        "bus": {
            "multiplier_range": [0.50, 1.50],
            "flag_enum": ["NORMAL", "REDUCED", "CAUTION", "ELEVATED"],
            "hint_enum": ["NONE", "RISK", "RESEARCH", "SHADOW"],
            "examples": {k: {"multiplier": v, "flag": bus_flag_for[k]} for k, v in examples.items()},
        },
        "consensus_rule": "ELEVATED (daily 80%) > CAUTION (RISK CAUTION or RESEARCH GB) > REDUCED (mult<0.90) > NORMAL; multiplier= risk_mult * research_shave(<0.55->0.85) * shadow_shave(<0.35->0.80) clamped 0.50..1.50",
        "advisory_only": True,
    }

    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(report, indent=2), encoding="utf-8")

    md = f"""# Decision Bus — Advisory Report (ADR-0018)

**Generated:** {report['generated_at']}  
**Mode:** advisory consensus routing — Risk + Research + Shadow (ADR-0018)

## 1. Inputs

- Risk high {vol_high_mult}, normal {vol_normal_mult} (vol regime)
- Research conf {research_conf:.2f} hint {syn_feature}
- Logistic WF {report['inputs']['logistic_wf']:.4f}

## 2. Bus Logic

`bus_multiplier = risk_multiplier × research_shave(conf<0.55→0.85) × shadow_shave(<0.35→0.80)` clamped 0.50..1.50  
`flag: ELEVATED > CAUTION > REDUCED > NORMAL`, `hint: NONE/RISK/RESEARCH/SHADOW`

| Example | Risk base | Bus mult | Bus flag | Reason |
|---|---|---|---|---|
| low_vol_hour12 | 1.00 | {examples['low_vol_hour12']:.2f} | {bus_flag_for['low_vol_hour12']} | calm |
| normal_vol_hour21 | 0.85×0.70=0.595 | {examples['normal_vol_hour21']:.2f} | {bus_flag_for['normal_vol_hour21']} | worst hour reduced |
| high_vol_low_conf | 0.50×0.80=0.40 | {examples['high_vol_low_conf']:.2f} | {bus_flag_for['high_vol_low_conf']} | CAUTION (high vol dominates) |

## 3. MQL

`CAIDecisionBus.Route(SRiskAdvisory, SResearchAdvisory, CAIContext)` →
`SBusAdvisory {{bus_multiplier 0.50..1.50, bus_flag, bus_hint, consensus_reason}}`
dormant OFF, explicit call, validates, 0 trading tokens, never consumed by TradeManager.

No live routing — advisory consensus strings only.
"""
    OUT_MD.write_text(md, encoding="utf-8")
    return report


if __name__ == "__main__":
    r = main()
    print(f"written {OUT_JSON} and {OUT_MD}")
    print(r["bus"]["examples"])
