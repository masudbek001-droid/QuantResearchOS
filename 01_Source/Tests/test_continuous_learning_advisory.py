import pathlib
import re
import json
import sys
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
MQH = ROOT / "01_Source/EA/MQL5/Include/CandleBreakoutEA/EAContext/EAContextContinuousLearning.mqh"
TRADE = ROOT / "01_Source/EA/MQL5/Include/CandleBreakoutEA/EATradeManager.mqh"
PY = ROOT / "06_Tools/continuous_learning_advisory.py"
OUT = ROOT / "04_Output/Learning/learning_advisory_report.json"
FORBIDDEN = ["OrderSend","OrderDelete","PositionClose","CTrade","COrderManager","CPositionManager","CRiskManager","CExitEngine","SetDeviationInPoints","DatabaseExecute","TradeManager"]

def ok(c,m):
    if not c:
        print(f"[FAIL] {m}")
        sys.exit(1)
    print(f"[PASS] {m}")

def test_mqh():
    ok(MQH.exists(),"learning mqh exists")
    t = MQH.read_text(encoding="utf-8")
    ok("CAIContinuousLearning" in t,"class")
    ok("SLearningAdvisory" in t,"struct")
    ok("advisory only" in t.lower(),"advisory")

def test_no_tokens():
    t = MQH.read_text(encoding="utf-8")
    hits = [k for k in FORBIDDEN if re.search(rf"\b{re.escape(k)}\b", t)]
    ok(len(hits)==0,f"no forbidden {hits}")

def test_not_wired():
    ok((TRADE.read_text(encoding="utf-8").count("CAIContinuousLearning") + TRADE.read_text(encoding="utf-8").count("ContinuousLearning")) == 0,"TradeManager 0 learning calls")

def test_json():
    if not OUT.exists():
        r = subprocess.run([sys.executable, str(PY)], cwd=str(ROOT), capture_output=True, text=True)
        print(r.stdout[-400:])
        print(r.stderr[-400:])
        ok(OUT.exists(),"json generated")
    d = json.loads(OUT.read_text(encoding="utf-8"))
    ok("drift" in d,"drift key")
    ok(0.0 <= d["drift"]["drift_score"] <= 1.0,f"drift bounds {d['drift']['drift_score']}")
    ok(d["drift"]["retrain_hint"] in ["NONE","SCHEDULED","URGENT"],"hint enum")
    ok(d.get("advisory_only")==True,"advisory_only")
    print(f"[PASS] drift {d['drift']}")

if __name__ == "__main__":
    test_mqh()
    test_no_tokens()
    test_not_wired()
    test_json()
    print("[QROS_CONTINUOUS_LEARNING] STATUS=PASS | advisory=OBSERVE_ONLY | trade_manager_calls=0 | drift=PASS")
