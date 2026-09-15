"""
Test Chief Research AI advisory — ADR-0017
Validates MQL advisory, Python synthesis, no trading authority.
"""
import pathlib
import re
import json
import sys
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
MQH = ROOT / "01_Source" / "EA" / "MQL5" / "Include" / "CandleBreakoutEA" / "EAContext" / "EAContextResearchAdvisory.mqh"
TRADE_MANAGER = ROOT / "01_Source" / "EA" / "MQL5" / "Include" / "CandleBreakoutEA" / "EATradeManager.mqh"
PY_TOOL = ROOT / "06_Tools" / "chief_research_advisory.py"
OUT_JSON = ROOT / "04_Output" / "Research" / "research_synthesis_report.json"

FORBIDDEN = [
    "OrderSend", "OrderDelete", "PositionClose", "CTrade", "COrderManager",
    "CPositionManager", "CRiskManager", "CExitEngine", "SetDeviationInPoints",
    "DatabaseExecute", "TradeManager",
]

def assert_true(cond, msg):
    if not cond:
        print(f"[FAIL] {msg}")
        sys.exit(1)
    print(f"[PASS] {msg}")

def test_mqh():
    assert_true(MQH.exists(), "research advisory mqh exists")
    t = MQH.read_text(encoding="utf-8")
    assert_true("CAIResearchAdvisory" in t, "class present")
    assert_true("SResearchAdvisory" in t, "struct present")
    assert_true("ENUM_RESEARCH_HINT" in t, "enum present")
    assert_true("advisory only" in t.lower(), "advisory comment")

def test_no_forbidden():
    t = MQH.read_text(encoding="utf-8")
    hits = [tok for tok in FORBIDDEN if re.search(rf"\b{re.escape(tok)}\b", t)]
    assert_true(len(hits)==0, f"no forbidden tokens, found {hits}")

def test_not_wired():
    t = TRADE_MANAGER.read_text(encoding="utf-8")
    cnt = t.count("CAIResearchAdvisory") + t.count("ResearchAdvisory")
    assert_true(cnt==0, f"TradeManager 0 research advisory calls, found {cnt}")

def test_synthesis():
    if not OUT_JSON.exists():
        print(f"[WARN] {OUT_JSON} missing — running tool")
        r = subprocess.run([sys.executable, str(PY_TOOL)], cwd=str(ROOT), capture_output=True, text=True)
        print(r.stdout[-400:])
        print(r.stderr[-400:])
        assert_true(OUT_JSON.exists(), "research json generated")
    data = json.loads(OUT_JSON.read_text(encoding="utf-8"))
    assert_true("synthesis" in data, "synthesis key")
    syn = data["synthesis"]
    for k in ["feature_hint","window_hint","next_experiment_hint","confidence"]:
        assert_true(k in syn, f"synthesis has {k}")
    assert_true(0.0 <= syn["confidence"] <= 1.0, f"confidence {syn['confidence']} bounds")
    assert_true(syn["feature_hint"] in ["NONE","ABLATE_ATR","ABLATE_HOUR"], "feature hint enum")
    assert_true(syn["next_experiment_hint"] in ["NONE","TRY_GRADIENT_BOOST","RERUN_QUALITY"], "next hint enum")
    assert_true(data.get("advisory_only")==True, "advisory_only true")
    print(f"[PASS] synthesis hints feature={syn['feature_hint']} next={syn['next_experiment_hint']} conf={syn['confidence']}")

if __name__ == "__main__":
    test_mqh()
    test_no_forbidden()
    test_not_wired()
    test_synthesis()
    print("[QROS_CHIEF_RESEARCH] STATUS=PASS | advisory=OBSERVE_ONLY | trade_manager_calls=0 | hints=PASS")
