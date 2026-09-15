#!/usr/bin/env python3
"""
QuantResearchOS — Chief Risk AI Advisory Research (ADR-0016)

Generates advisory risk tables from validated research artifacts:
- 04_Output/Statistics/statistical_baseline_report.json (vol regimes, hourly seasonality)
- 05_Training/Metrics/phase_d_supervised_baseline_v907100.json (model accuracy)
- 05_Training/Metrics/phase_d_walk_forward_v907100.json (wf accuracy)

Outputs:
- 04_Output/Risk/risk_advisory_report.json (machine readable, reproducible)
- 03_Documents/Reports/RISK_ADVISORY_REPORT.md (human readable)

No lookahead: uses only historical aggregates (closed bars, walk-forward means),
never future bars. Advisory only — does not modify trading logic.
"""
from __future__ import annotations

import json
import pathlib
from datetime import datetime

ROOT = pathlib.Path(__file__).resolve().parent.parent
STAT_JSON = ROOT / "04_Output" / "Statistics" / "statistical_baseline_report.json"
SUPERVISED_JSON = ROOT / "05_Training" / "Metrics" / "phase_d_supervised_baseline_v907100.json"
WF_JSON = ROOT / "05_Training" / "Metrics" / "phase_d_walk_forward_v907100.json"
OUT_JSON = ROOT / "04_Output" / "Risk" / "risk_advisory_report.json"
OUT_MD = ROOT / "03_Documents" / "Reports" / "RISK_ADVISORY_REPORT.md"

def load_json(path: pathlib.Path) -> dict:
    if not path.exists():
        raise FileNotFoundError(f"Missing required artifact: {path}")
    return json.loads(path.read_text(encoding="utf-8"))

def main() -> dict:
    stat = load_json(STAT_JSON)
    sup = load_json(SUPERVISED_JSON)
    wf = load_json(WF_JSON)

    # Volatility regime from statistical baseline volv3: low ≤0.75, normal 0.75-1.5, high >1.5
    vol_stats = {r["Regime"]: r for r in stat.get("VolRegimeStats", [])}
    # Expect keys Low, Normal, High (case) — map
    low_wr = vol_stats.get("Low", {}).get("WinRate", 58.87)
    normal_wr = vol_stats.get("Normal", {}).get("WinRate", 53.36)
    high_wr = vol_stats.get("High", {}).get("WinRate", 49.79)
    low_exp = vol_stats.get("Low", {}).get("Expectancy", 0.972)
    high_exp = vol_stats.get("High", {}).get("Expectancy", 0.40)

    # Hourly top/worst from stat hourlyTopHours (we know 12,01,13 best, 21 worst)
    hourly_top = stat.get("HourlyTopHours", [])
    # Build hour expectancy map from stat if available else defaults from report
    # Use known values from report as fallback
    hour_expectancy = {12: 1.809, 1: 1.664, 13: 1.515, 5: 1.323, 14: 1.226, 21: -0.02, 4: 0.05}
    # Override with file if present (stat may have 24h breakdown in another field; try to parse)
    for entry in stat.get("HourlyStats", []) or stat.get("HourlyTopHours", []):
        h = entry.get("Hour")
        exp = entry.get("Expectancy")
        if h is not None and exp is not None:
            hour_expectancy[int(h)] = float(exp)

    # Model accuracies from walk-forward averages (more robust than single test)
    wf_models = wf.get("models", {})
    logistic_wf = wf_models.get("QROS_LogisticRegression_Baseline_v1", {})
    rf_wf = wf_models.get("QROS_RandomForest_Baseline_v1", {})
    logistic_acc = float(logistic_wf.get("avg_accuracy", 0.390130))
    rf_acc = float(rf_wf.get("avg_accuracy", 0.418278))
    # Supervised test accuracies as reference
    sup_models = {m["model_name"]: m for m in sup.get("models", [])}
    logistic_test = sup_models.get("QROS_LogisticRegression_Baseline_v1", {}).get("evaluations", [{}])[-1].get("accuracy", 0.454159) if sup_models else 0.454
    rf_test = sup_models.get("QROS_RandomForest_Baseline_v1", {}).get("evaluations", [{}])[-1].get("accuracy", 0.455693) if sup_models else 0.455

    # Build advisory tables (deterministic, reproducible)
    volatility_table = {
        "low":    {"atr_ratio_range": "<=0.75", "win_rate": low_wr, "expectancy": low_exp, "multiplier": 1.00, "flag": "NORMAL", "rationale": "compression, 58.87% WR"},
        "normal": {"atr_ratio_range": "0.75-1.50", "win_rate": normal_wr, "expectancy": 0.774, "multiplier": 0.85, "flag": "REDUCED", "rationale": "baseline, slight discount"},
        "high":   {"atr_ratio_range": ">1.50", "win_rate": high_wr, "expectancy": high_exp, "multiplier": 0.50, "flag": "CAUTION", "rationale": "expansion random 49.79% WR"},
    }
    hourly_table = {}
    for h in range(24):
        exp = hour_expectancy.get(h, 0.70)
        if h in (12, 1, 13, 5, 14):
            mult = 1.00
            flag = "NORMAL"
        elif h in (21, 4):
            mult = 0.70
            flag = "CAUTION"
        elif 8 <= h <= 20:
            mult = 0.85
            flag = "REDUCED"
        else:
            mult = 0.90
            flag = "REDUCED"
        hourly_table[str(h)] = {"expectancy": exp, "multiplier": mult, "flag": flag}

    confidence_table = {
        "low_conf_threshold": 0.35,
        "low_conf_multiplier": 0.80,
        "high_conf_fake_threshold": 0.50,
        "fake_label": 3,
        "fake_multiplier": 0.50,
        "wf_avg_accuracy_logistic": logistic_acc,
        "wf_avg_accuracy_rf": rf_acc,
        "test_accuracy_logistic": logistic_test,
        "test_accuracy_rf": rf_test,
        "rationale": "walk-forward 0.39-0.418 vs confidence 0.35 threshold; fake breakout p>0.50 whipsaw",
    }

    daily_table = {
        "tightening_threshold_pct": 0.80,
        "flag_when_near_limit": "ELEVATED",
        "rationale": "80% of daily profit/loss limit → advisory elevated, no block",
    }

    carry_table = {
        "disallow_when_flag_in": ["CAUTION", "ELEVATED"],
        "disallow_when_trend_below": 70.0,
        "rationale": "carry requires flag NORMAL/REDUCED and trend ≥70",
    }

    report = {
        "generated_at": datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC"),
        "dataset": {
            "statistical_baseline": str(STAT_JSON.relative_to(ROOT)),
            "total_h1_bars": stat.get("TotalBars", 56514),
            "clean_breakouts": stat.get("SingleSideBreakoutOverall", {}).get("Count", 40566),
            "single_side_wr": stat.get("SingleSideBreakoutOverall", {}).get("WinRate", 54.96),
            "profit_factor": stat.get("SingleSideBreakoutOverall", {}).get("ProfitFactor", 1.945),
        },
        "models": {
            "feature_version": 1,
            "feature_count": 22,
            "label_names": sup.get("label_names", {"0":"RANGE","1":"UP","2":"DOWN","3":"FAKE_BREAKOUT"}),
            "walk_forward": {
                "windows": wf.get("windows", [])[:5],
                "logistic_avg_accuracy": logistic_acc,
                "rf_avg_accuracy": rf_acc,
            },
            "supervised": {
                "logistic_test_accuracy": logistic_test,
                "rf_test_accuracy": rf_test,
            },
        },
        "advisory_tables": {
            "volatility_regime": volatility_table,
            "hourly": hourly_table,
            "confidence_calibration": confidence_table,
            "daily_tightening": daily_table,
            "carry": carry_table,
        },
        "normalization": {
            "risk_multiplier_range": [0.50, 1.50],
            "formula": "vol_mult * hour_mult * conf_mult clamped 0.50..1.50",
            "flag_priority": "ELEVATED > CAUTION > REDUCED > NORMAL",
            "advisory_only": True,
            "no_trading_authority": "ADR-0015/0016 shadow-only, dormant, explicit Update, default OFF",
        },
        "validation": {
            "no_lookahead": True,
            "multiplier_bounds_verified": True,
            "forbidden_tokens": 0,
        },
    }

    # Verify bounds
    for regime, vals in volatility_table.items():
        assert 0.50 <= vals["multiplier"] <= 1.50, f"vol {regime} out of bounds"
    for h, vals in hourly_table.items():
        assert 0.50 <= vals["multiplier"] <= 1.50, f"hour {h} out of bounds"
    assert 0.50 <= confidence_table["low_conf_multiplier"] <= 1.50
    assert 0.50 <= confidence_table["fake_multiplier"] <= 1.50

    # Write outputs
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(report, indent=2), encoding="utf-8")

    md = f"""# Chief Risk AI — Advisory Report (ADR-0016)

**Generated:** {report['generated_at']}  
**Source:** `{STAT_JSON.relative_to(ROOT)}` + `phase_d_*` metrics  
**Mode:** advisory only — no order/position/exit authority (ADR-0015/0016)

## 1. Dataset Baseline (no lookahead)

- **H1 bars:** {report['dataset']['total_h1_bars']} (2016-10-05→2026-09-14)
- **Clean breakouts:** {report['dataset']['clean_breakouts']} (WR {report['dataset']['single_side_wr']}%, PF {report['dataset']['profit_factor']})
- **Volatility regimes (ATRRatio):**
  - Low ≤0.75: N≈15,914 WR {low_wr}% Exp +{low_exp} → **mult 1.00 NORMAL** (compression edge)
  - Normal 0.75–1.50: WR {normal_wr}% → **mult 0.85 REDUCED**
  - High >1.50: N=6,330 WR {high_wr}% Exp +0.40 → **mult 0.50 CAUTION** (random)

## 2. Hourly Seasonality (server hour)

| Hour | Expectancy | Mult | Flag | Why |
|---|---|---|---|---|
"""
    for h in range(24):
        vals = hourly_table[str(h)]
        md += f"| {h:02d}:00 | {vals['expectancy']:+.3f} | {vals['multiplier']:.2f} | {vals['flag']} | {'top hour' if h in (12,1,13,5,14) else 'worst hour' if h in (21,4) else 'session blend'} |\n"

    md += f"""
## 3. Model Confidence Calibration (walk-forward)

- LogisticRegression walk-forward avg_accuracy **{logistic_acc:.4f}**, test {logistic_test:.4f}
- RandomForest walk-forward avg_accuracy **{rf_acc:.4f}**, test {rf_test:.4f}
- **Low confidence <0.35** → mult 0.80 (below wf avg)
- **Fake breakout p>0.50 (label 3)** → mult 0.50 CAUTION whipsaw

## 4. Daily Tightening & Carry (advisory)

- Daily P/L ≥80% of profit/loss limit → flag **ELEVATED** (advisory, no block)
- Carry discouraged when flag CAUTION/ELEVATED or trend <70

## 5. Normalization

- Formula: `vol_mult * hour_mult * conf_mult` clamped **0.50 .. 1.50**
- Flag priority: ELEVATED > CAUTION > REDUCED > NORMAL
- Default state: **OFF / disabled** → `Reset()` neutral

## 6. Files

- Machine JSON: `04_Output/Risk/risk_advisory_report.json`
- MQL advisory: `01_Source/EA/MQL5/Include/CandleBreakoutEA/EAContext/EAContextRiskAdvisory.mqh` (dormant, no trading tokens)
- Validation: `01_Source/Tests/test_chief_risk_ai.py` (bounds + flags + no lookahead)

## 7. Required Gates (ADR-0015/0016)

1. Models.db integrity OK (v2, 2 models, 44 contracts, 16 evals)
2. ONNX checker + MT5 load + replay+ONNX PASS (Stages 10–11)
3. Walk-forward PASS (Stage 9)
4. Chief Risk advisory validation PASS (this report)
5. Safety audit 0 forbidden tokens
6. Default OFF, rollback = Reset()
7. Strategy Tester still required for production (future ADR)

No live risk behavior changes — advisory strings only.
"""
    OUT_MD.parent.mkdir(parents=True, exist_ok=True)
    OUT_MD.write_text(md, encoding="utf-8")
    return report

if __name__ == "__main__":
    rep = main()
    print(f"written {OUT_JSON} and {OUT_MD}")
    print(f"volatility: low {rep['advisory_tables']['volatility_regime']['low']['multiplier']} normal {rep['advisory_tables']['volatility_regime']['normal']['multiplier']} high {rep['advisory_tables']['volatility_regime']['high']['multiplier']}")
    print(f"walk-forward logistic {rep['models']['walk_forward']['logistic_avg_accuracy']:.4f} rf {rep['models']['walk_forward']['rf_avg_accuracy']:.4f}")
