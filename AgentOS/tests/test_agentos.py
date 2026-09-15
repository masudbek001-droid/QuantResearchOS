"""
AgentOS v1.0 Tests — MVP collaboration layer invariants

Run: python AgentOS/tests/test_agentos.py
     or python -m pytest AgentOS/tests/test_agentos.py -v
"""
import pathlib
import re
import subprocess
import sys
import json

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
AGENTOS = ROOT / "AgentOS"

def ok(cond, msg):
    if not cond:
        print(f"[FAIL] {msg}")
        sys.exit(1)
    print(f"[PASS] {msg}")

def read(fname):
    return (AGENTOS / fname).read_text(encoding="utf-8")

def test_protocol_exists():
    ok((AGENTOS / "AGENT_PROTOCOL.md").exists(), "AGENT_PROTOCOL.md exists")
    t = read("AGENT_PROTOCOL.md")
    ok("Git is the bus" in t, "protocol Git bus clause")
    ok("One module, one owner" in t, "single-owner clause")
    ok("No direct agent-to-agent" in t, "no direct assumption clause")
    ok("advisory only" in t.lower(), "advisory preserved")

def test_all_eight_files():
    for fname in ["AGENT_PROTOCOL.md","TASK_QUEUE.md","REPORT_QUEUE.md","LOCK_MANAGER.md","OWNERSHIP_MAP.md","DECISION_LOG.md","EVENT_BUS.md","WORKER_REGISTRY.md"]:
        ok((AGENTOS / fname).exists(), f"{fname} exists")
        c = read(fname)
        ok(len(c.strip()) > 200, f"{fname} substantial (>200 chars)")

def test_ownership_single_owner():
    om = read("OWNERSHIP_MAP.md")
    # parse modules and workers
    rows = []
    for line in om.splitlines():
        if line.strip().startswith("| MOD-"):
            cols = [c.strip() for c in line.strip().strip("|").split("|")]
            rows.append(cols)
    modules = [r[0] for r in rows]
    owners = [r[3] for r in rows]
    ok(len(modules) == len(set(modules)), f"OWNERSHIP_MAP modules unique ({modules})")
    ok(len(owners) == len(set(owners)), f"OWNERSHIP_MAP workers unique 1:1 ({owners})")
    ok(len(modules) >= 8, f"OWNERSHIP_MAP at least 8 modules ({len(modules)})")

def test_worker_registry_one_to_one():
    wr = read("WORKER_REGISTRY.md")
    om = read("OWNERSHIP_MAP.md")
    # extract registry rows
    wr_rows = [l for l in wr.splitlines() if l.strip().startswith("| worker-")]
    om_rows = [l for l in om.splitlines() if l.strip().startswith("| MOD-")]
    wr_ids = [r.split("|")[1].strip() for r in wr_rows]
    wr_mods = [r.split("|")[2].strip() for r in wr_rows]
    ok(len(wr_ids) == len(set(wr_ids)), f"WORKER_REGISTRY WorkerID unique ({len(wr_ids)})")
    ok(len(wr_mods) == len(set(wr_mods)), f"WORKER_REGISTRY ModuleOwned unique ({len(wr_mods)})")
    # cross-check
    om_map = {}
    for r in om_rows:
        cols = [c.strip() for c in r.strip().strip("|").split("|")]
        om_map[cols[0]] = cols[3]
    for wid, mod in zip(wr_ids, wr_mods):
        ok(mod in om_map, f"registry {wid} module {mod} in ownership map")
        ok(om_map[mod] == wid, f"registry {wid} ↔ ownership {mod} matches ({om_map[mod]})")

def test_no_direct_assumptions():
    proto = read("AGENT_PROTOCOL.md")
    ok("Workers communicate only through AgentOS" in proto or "communicate only through AgentOS" in proto.lower() or "Git is the bus" in proto, "protocol forbids direct assumptions")
    # Ensure no file contains direct agent-to-agent RPC mention
    for fname in ["AGENT_PROTOCOL.md","TASK_QUEUE.md","EVENT_BUS.md"]:
        t = read(fname)
        ok("Telegram" not in t or "not implemented" in t or "No Telegram" in t or "Out of scope" in t, f"{fname} Telegram correctly not implemented or mentioned as out of scope")

def test_git_based():
    proto = read("AGENT_PROTOCOL.md")
    ok("git pull" in proto.lower(), "protocol mentions git pull")
    ok("git push" in proto.lower(), "protocol mentions git push")
    ok("branch" in proto.lower(), "protocol mentions branch")
    # check task queue mentions git
    tq = read("TASK_QUEUE.md")
    ok("git" in tq.lower() or " AgentOS/tools/agentos_cli.py" in tq, "TASK_QUEUE references git/cli")

def test_validate_passes():
    result = subprocess.run([sys.executable, str(AGENTOS / "tools/validate.py")], cwd=str(ROOT), capture_output=True, text=True)
    print(result.stdout[-500:])
    print(result.stderr[-500:])
    ok(result.returncode == 0, f"validate.py PASS (exit 0), got {result.returncode}")
    ok("[AGENTOS] STATUS=PASS" in result.stdout, "validate output PASS")

def test_lock_no_duplicate_active():
    lm = read("LOCK_MANAGER.md")
    active_paths = re.findall(r"\|\s*LOCK-\d+\s*\|\s*([^\|]+?)\s*\|\s*[^|]+\|\s*[^|]+\|[^|]*\|[^|]*\|\s*ACTIVE", lm)
    ok(len(active_paths) == len(set(active_paths)), f"LOCK_MANAGER no duplicate ACTIVE paths ({active_paths})")

def test_trading_not_modified():
    # Ensure AgentOS did not touch trading core or advisory modules
    # Check git status for outside AgentOS modifications (should be only AgentOS files pending)
    result = subprocess.run(["git", "status", "--porcelain"], cwd=str(ROOT), capture_output=True, text=True)
    lines = result.stdout.splitlines()
    # Allow AgentOS files and maybe docs, but not EA source
    for l in lines:
        if not l.strip():
            continue
        path = l[3:].strip().strip('"')
        # ignore untracked AgentOS files (expected)
        if path.startswith("AgentOS/"):
            continue
        if path.startswith("03_Documents/ADR/ADR-0021"):
            continue
        if path.startswith("03_Documents/Reports/AGENTOS"):
            continue
        if "AgentOS" in path:
            continue
        # trading core paths should not appear as modified
        if "01_Source/EA/MQL5" in path and path.endswith(".mqh"):
            ok(False, f"trading logic modified unexpectedly: {path}")
        if "EAContextRiskAdvisory" in path or "EAContextResearchAdvisory" in path:
            ok(False, f"AI advisory modified unexpectedly: {path}")
    ok(True, "no trading/AI advisory modifications detected (only AgentOS)")

def test_example_workflow_present():
    ok((AGENTOS / "EXAMPLE_WORKFLOW.md").exists(), "EXAMPLE_WORKFLOW.md exists")
    t = read("EXAMPLE_WORKFLOW.md")
    ok("TASK-0003" in t, "example workflow traces TASK-0003")
    ok("git fetch origin" in t, "example shows git fetch")
    ok("lock.acquired" in t or "LOCK_MANAGER" in t, "example mentions lock")

def test_cli_exists():
    ok((AGENTOS / "tools/agentos_cli.py").exists(), "agentos_cli.py exists")
    ok((AGENTOS / "tools/validate.py").exists(), "validate.py exists")
    # try help
    r = subprocess.run([sys.executable, str(AGENTOS / "tools/agentos_cli.py"), "--help"], capture_output=True, text=True)
    ok(r.returncode == 0 or "usage" in r.stdout.lower() or "usage" in r.stderr.lower(), "cli --help works")

if __name__ == "__main__":
    test_protocol_exists()
    test_all_eight_files()
    test_ownership_single_owner()
    test_worker_registry_one_to_one()
    test_no_direct_assumptions()
    test_git_based()
    test_validate_passes()
    test_lock_no_duplicate_active()
    test_trading_not_modified()
    test_example_workflow_present()
    test_cli_exists()
    print("\n[AGENTOS_TESTS] STATUS=PASS — all 11 checks passed")
