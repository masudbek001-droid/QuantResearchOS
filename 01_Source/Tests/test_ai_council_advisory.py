import pathlib,re,json,sys,subprocess
ROOT=pathlib.Path(__file__).resolve().parent.parent.parent
MQH=ROOT/"01_Source"/"EA"/"MQL5"/"Include"/"CandleBreakoutEA"/"EAContext"/"EAContextAICouncil.mqh"
TRADE=ROOT/"01_Source"/"EA"/"MQL5"/"Include"/"CandleBreakoutEA"/"EATradeManager.mqh"
PY=ROOT/"06_Tools"/"ai_council_advisory.py"
OUT=ROOT/"04_Output"/"Council"/"council_report.json"
FORBIDDEN=["OrderSend","OrderDelete","PositionClose","CTrade","COrderManager","CPositionManager","CRiskManager","CExitEngine","SetDeviationInPoints","DatabaseExecute","TradeManager"]
def ok(c,m):
    if not c: print(f"[FAIL] {m}"); sys.exit(1)
    print(f"[PASS] {m}")
def test_mqh():
    ok(MQH.exists(),"council mqh exists")
    t=MQH.read_text(encoding="utf-8")
    ok("CAIAICouncil" in t,"class")
    ok("SCouncilAdvisory" in t,"struct")
    ok("advisory only" in t.lower(),"advisory")
def test_no_tokens():
    t=MQH.read_text(encoding="utf-8")
    hits=[k for k in FORBIDDEN if re.search(rf"\b{re.escape(k)}\b",t)]
    ok(len(hits)==0,f"no forbidden {hits}")
def test_not_wired():
    ok((TRADE.read_text(encoding="utf-8").count("CAIAICouncil")+TRADE.read_text(encoding="utf-8").count("AICouncil"))==0,"TradeManager 0 council calls")
def test_json():
    if not OUT.exists():
        r=subprocess.run([sys.executable,str(PY)],cwd=str(ROOT),capture_output=True,text=True)
        print(r.stdout[-400:]); print(r.stderr[-400:])
        ok(OUT.exists(),"json generated")
    d=json.loads(OUT.read_text(encoding="utf-8"))
    ok("council" in d,"council key")
    for k,v in d["council"]["examples"].items():
        ok(0.50 <= v["multiplier"] <= 1.50,f"{k} mult {v['multiplier']}")
        ok(v["vote"] in ["NORMAL","REDUCED","CAUTION","ELEVATED"],f"{k} vote")
    ok(d.get("advisory_only")==True,"advisory_only")
    print(f"[PASS] council examples {d['council']['examples']}")
if __name__=="__main__":
    test_mqh(); test_no_tokens(); test_not_wired(); test_json()
    print("[QROS_AI_COUNCIL] STATUS=PASS | advisory=OBSERVE_ONLY | trade_manager_calls=0 | multiplier_bounds=PASS")
