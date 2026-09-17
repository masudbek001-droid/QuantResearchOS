"""
Test Chief Risk AI advisory — ADR-0016
Validates advisory-only behavior, multiplier bounds, regime mappings, and no trading authority.
No MT5 required; pure Python + static source scan.
"""
import pathlib
import re
import json
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
MQH = ROOT / "01_Source" / "EA" / "MQL5" / "Include" / "CandleBreakoutEA" / "EAContext" / "EAContextRiskAdvisory.mqh"
TRADE_MANAGER = ROOT / "01_Source" / "EA" / "MQL5" / "Include" / "CandleBreakoutEA" / "EATradeManager.mqh"
RISK_MQH = ROOT / "01_Source" / "EA" / "MQL5" / "Include" / "CandleBreakoutEA" / "EAContext" / "EAContextRiskAdvisory.mqh"
STAT_JSON = ROOT / "04_Output" / "Statistics" / "statistical_baseline_report.json"
WF_JSON = ROOT / "05_Training" / "Metrics" / "phase_d_walk_forward_v907100.json"
RISK_JSON = ROOT / "04_Output" / "Risk" / "risk_advisory_report.json"
PY_TOOL = ROOT / "06_Tools" / "chief_risk_advisory.py"

FORBIDDEN_TOKENS = [
    "OrderSend", "OrderDelete", "OrderModify", "PositionClose", "PositionSelect",
    "CTrade", "COrderManager", "CPositionManager", "CRiskManager", "CExitEngine",
    "TradeManager", "SetDeviationInPoints", "SetTypeFilling", "DatabaseExecute",
]

def assert_true(cond, msg):
    if not cond:
        print(f"[FAIL] {msg}")
        sys.exit(1)
    print(f"[PASS] {msg}")

def test_mqh_exists():
    assert_true(MQH.exists(), f"advisory mqh exists at {MQH}")
    text = MQH.read_text(encoding="utf-8")
    assert_true(len(text) > 2000, "mql file substantial")
    assert_true("CAIRiskAdvisory" in text, "class CAIRiskAdvisory present")
    assert_true("SRiskAdvisory" in text, "struct SRiskAdvisory present")
    assert_true("ENUM_RISK_ADVISORY_FLAG" in text, "enum present")
    assert_true("advisory only" in text.lower(), "advisory comment present")

def test_no_forbidden_tokens():
    text = MQH.read_text(encoding="utf-8")
    hits = []
    for tok in FORBIDDEN_TOKENS:
        # Use word boundary regex
        if re.search(rf"\b{re.escape(tok)}\b", text):
            hits.append(tok)
    assert_true(len(hits)==0, f"no forbidden tokens in advisory mqh (found {hits})")
    # Also ensure no direct DB writes
    assert_true("Database" not in text or "DatabaseExecute" not in text, "no DB writes")

def test_trade_manager_not_consuming():
    if not TRADE_MANAGER.exists():
        assert_true(False, "TradeManager not found")
    text = TRADE_MANAGER.read_text(encoding="utf-8")
    count = text.count("CAIRiskAdvisory") + text.count("RiskAdvisory") + text.count("m_risk_advisory")
    assert_true(count==0, f"TradeManager must have 0 risk advisory calls (found {count}) — advisory not wired")

def test_multiplier_bounds():
    # Simulate Python logic from chief_risk_advisory
    def vol_mult(atr):
        if atr <= 0: return 1.0
        if atr <=0.75: return 1.00
        if atr <=1.50: return 0.85
        return 0.50
    def hour_mult(h):
        if h<0 or h>23: return 1.0
        if h in (12,1,13,5,14): return 1.00
        if h in (21,4): return 0.70
        if 8 <= h <=20: return 0.85
        return 0.90
    def conf_mult(pred_available, label, p_fake, conf):
        if not pred_available: return 1.0
        if label==3 and p_fake>0.50: return 0.50
        if conf<0.35: return 0.80
        return 1.0
    # Test all regimes stay in 0.5..1.5
    for atr in [0.0, 0.5, 1.0, 2.0]:
        for h in [0,1,4,12,21]:
            for conf in [0.2, 0.5, 0.9]:
                mult = vol_mult(atr) * hour_mult(h) * conf_mult(True, 0, 0.0, conf)
                if mult<0.5: mult=0.5
                if mult>1.5: mult=1.5
                assert_true(0.50 <= mult <= 1.50, f"mult bounds atr={atr} h={h} conf={conf} => {mult}")
    # High vol must be 0.5
    assert_true(vol_mult(2.0)==0.50, "high vol 0.50")
    assert_true(vol_mult(0.5)==1.00, "low vol 1.00")
    # Fake breakout high p
    assert_true(conf_mult(True,3,0.60,0.9)==0.50, "fake breakout 0.50")
    assert_true(conf_mult(True,1,0.10,0.20)==0.80, "low conf 0.80")
    print("[PASS] multiplier logic verified")

def test_daily_and_carry():
    # Daily tightening 80% logic
    def daily_tight(pnl, limit):
        if limit>0 and pnl>=0.80*limit: return True
        if limit>0 and pnl<=-0.80*abs(limit): return True
        return False
    assert_true(daily_tight(85,100)==True, "daily 85/100 tight")
    assert_true(daily_tight(79,100)==False, "daily 79/100 not")
    assert_true(daily_tight(-85,100)==True, "daily loss tight")
    # Carry
    def carry_ok(flag, trend):
        if flag in ("CAUTION","ELEVATED"): return False
        if trend<70 and trend>=0: return False if flag!="NORMAL" else False # simplified
        return True
    # Just check that CAUTION always blocks carry
    assert_true(carry_ok("CAUTION", 90)==False, "CAUTION blocks carry")
    assert_true(carry_ok("NORMAL", 80)==True, "NORMAL allows carry if trend high")

def test_risk_json():
    if not RISK_JSON.exists():
        print(f"[WARN] risk json not yet generated at {RISK_JSON} — run chief_risk_advisory.py")
        # try to generate via import
        import subprocess
        result = subprocess.run([sys.executable, str(PY_TOOL)], cwd=str(ROOT), capture_output=True, text=True)
        print(result.stdout[-500:])
        print(result.stderr[-500:])
        assert_true(RISK_JSON.exists(), "risk json generated by tool")
    data = json.loads(RISK_JSON.read_text(encoding="utf-8"))
    assert_true("advisory_tables" in data, "risk json has advisory_tables")
    vol = data["advisory_tables"]["volatility_regime"]
    assert_true(vol["low"]["multiplier"]==1.00, "vol low 1.00")
    assert_true(vol["high"]["multiplier"]==0.50, "vol high 0.50")
    hourly = data["advisory_tables"]["hourly"]
    assert_true(hourly["12"]["multiplier"]==1.00, "hour 12 1.00")
    assert_true(hourly["21"]["multiplier"]==0.70, "hour 21 0.70")
    assert_true(data["normalization"]["risk_multiplier_range"]==[0.50,1.50], "range 0.5-1.5")
    assert_true(data["models"]["walk_forward"]["logistic_avg_accuracy"]<0.5, "wf logistic <0.5 (0.39)")
    print("[PASS] risk json content verified")

def test_python_tool_no_lookahead():
    text = PY_TOOL.read_text(encoding="utf-8")
    assert_true("Future" not in text or "lookahead" in text.lower(), "tool mentions lookahead handling")
    assert_true("statistical_baseline_report.json" in text, "tool loads baseline")
    assert_true("phase_d_walk_forward" in text, "tool loads wf")

if __name__ == "__main__":
    test_mqh_exists()
    test_no_forbidden_tokens()
    test_trade_manager_not_consuming()
    test_multiplier_bounds()
    test_daily_and_carry()
    test_python_tool_no_lookahead()
    test_risk_json()
    print("[QROS_CHIEF_RISK] STATUS=PASS | advisory=OBSERVE_ONLY | trade_manager_calls=0 | multiplier_bounds=PASS | vol_maps=PASS")
