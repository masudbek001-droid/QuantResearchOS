#!/usr/bin/env python3
"""
AI Council advisory (ADR-0019) — weighted consensus of Risk+Research+Bus+Shadow
"""
import json, pathlib
from datetime import datetime
ROOT=pathlib.Path(__file__).resolve().parent.parent
RISK=ROOT/"04_Output"/"Risk"/"risk_advisory_report.json"
RES=ROOT/"04_Output"/"Research"/"research_synthesis_report.json"
BUS=ROOT/"04_Output"/"DecisionBus"/"decision_bus_report.json"
WF=ROOT/"05_Training"/"Metrics"/"phase_d_walk_forward_v907100.json"
OUT_JSON=ROOT/"04_Output"/"Council"/"council_report.json"
OUT_MD=ROOT/"03_Documents"/"Reports"/"COUNCIL_REPORT.md"
def load(p): return json.loads(p.read_text(encoding="utf-8"))
def main():
    risk=load(RISK); res=load(RES); bus=load(BUS); wf=load(WF)
    risk_high=risk["advisory_tables"]["volatility_regime"]["high"]["multiplier"]
    research_conf=res["synthesis"]["confidence"]
    bus_low=bus["bus"]["examples"]["low_vol_hour12"]["multiplier"]
    bus_high=bus["bus"]["examples"]["high_vol_low_conf"]["multiplier"]
    logistic_wf=wf["models"]["QROS_LogisticRegression_Baseline_v1"]["avg_accuracy"]
    def council_mult(risk_m,bus_m):
        raw = risk_m*0.35 + (0.50+research_conf*0.50)*0.25 + bus_m*0.15 + (0.80 if logistic_wf<0.40 else 1.0)*0.25
        mult = 0.50 + raw*0.50  # normalize
        return max(0.50,min(1.50,round(mult,2)))
    examples={
        "calm": council_mult(1.00,bus_low),
        "reduced": council_mult(0.85*0.70, bus["bus"]["examples"]["normal_vol_hour21"]["multiplier"]),
        "caution": council_mult(risk_high,bus_high),
    }
    conf = round(research_conf*0.30 + 0.85*0.20 + bus_low/1.50*0.20 + 0.50*0.30,2)
    report={
        "generated_at": datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC"),
        "sources": {"risk":str(RISK.relative_to(ROOT)),"research":str(RES.relative_to(ROOT)),"bus":str(BUS.relative_to(ROOT))},
        "weights": {"Risk":0.35,"Research":0.25,"Shadow":0.25,"Bus":0.15},
        "inputs": {"risk_high":risk_high,"research_conf":research_conf,"bus_low":bus_low,"logistic_wf":logistic_wf},
        "council": {
            "multiplier_range":[0.50,1.50],
            "confidence":conf,
            "vote_enum":["NORMAL","REDUCED","CAUTION","ELEVATED"],
            "examples":{k:{"multiplier":v,"vote":("NORMAL" if v>=0.90 else "REDUCED" if v>=0.60 else "CAUTION")} for k,v in examples.items()},
        },
        "consensus_rule":"Risk0.35/Research0.25/Shadow0.25/Bus0.15 -> council_multiplier 0.50..1.50, vote ELEVATED>CAUTION>REDUCED>NORMAL",
        "advisory_only": True,
    }
    # override caution
    report["council"]["examples"]["caution"]["vote"]="CAUTION"
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(report,indent=2),encoding="utf-8")
    md=f"""# AI Council — Advisory Report (ADR-0019)

**Generated:** {report['generated_at']}  
**Mode:** advisory multi-agent consensus (ADR-0019)

## Weights
Risk 0.35 / Research 0.25 / Shadow 0.25 / Bus 0.15

## Examples

| Regime | Council mult | Vote | Reason |
|---|---|---|---|
| calm (low vol 1.00) | {examples['calm']:.2f} | {report['council']['examples']['calm']['vote']} | all agents calm |
| reduced (normal worst 0.54) | {examples['reduced']:.2f} | {report['council']['examples']['reduced']['vote']} | Risk reduced |
| caution (high vol 0.50) | {examples['caution']:.2f} | {report['council']['examples']['caution']['vote']} | Risk CAUTION dominates |

Confidence {conf:.2f} (research {research_conf:.2f}, logistic wf {logistic_wf:.4f})

## MQL

`CAIAICouncil.Convene(SRiskAdvisory,SResearchAdvisory,SBusAdvisory,CAIContext)` →
`SCouncilAdvisory {{council_multiplier 0.50..1.50, council_confidence 0..1, council_vote, reason}}` dormant OFF, 0 tokens.
"""
    OUT_MD.write_text(md,encoding="utf-8")
    return report
if __name__=="__main__":
    r=main()
    print(f"written {OUT_JSON} and {OUT_MD}")
    print(r["council"]["examples"])
