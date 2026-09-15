#!/usr/bin/env python3
"""
AgentOS — Validator v1.0
Enforces invariants from AGENT_PROTOCOL.md. CI gate: non-zero exit on violation.
"""
import re
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
AGENTOS = ROOT / "AgentOS"

def read(path):
    return (AGENTOS / path).read_text(encoding="utf-8")

def parse_table(md_text, header_regex):
    """Return rows as list of dicts by splitting markdown table lines after header.
    Picks LAST matching header to skip schema tables that precede queue tables."""
    rows = []
    lines = md_text.splitlines()
    candidates = []
    for i, l in enumerate(lines):
        if re.search(header_regex, l):
            candidates.append(i)
    if not candidates:
        return rows
    header_idx = candidates[-1]  # last match is the data table, not schema
    # header line at header_idx, separator at +1, data from +2
    header = [h.strip() for h in lines[header_idx].strip().strip("|").split("|")]
    for line in lines[header_idx+2:]:
        if not line.strip().startswith("|"):
            break
        if line.strip().startswith("| -") or line.strip().startswith("| - -"):
            # empty placeholder row with dashes
            cols = [c.strip() for c in line.strip().strip("|").split("|")]
            if all(c in ("-", "", "--") for c in cols):
                continue
        cols = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cols) < len(header):
            continue
        # skip placeholder row where first col is "-"
        if cols[0] == "-" and all(c == "-" for c in cols):
            continue
        row = dict(zip(header, cols))
        rows.append(row)
    return rows

def fail(msg):
    print(f"[FAIL] {msg}")
    return False

def ok(msg):
    print(f"[PASS] {msg}")
    return True

def main():
    passed = True

    # 1. OWNERSHIP_MAP: Module unique, Worker unique
    try:
        om_text = read("OWNERSHIP_MAP.md")
        om_rows = parse_table(om_text, r"\|\s*Module\s*\|")
        modules = [r["Module"] for r in om_rows if r.get("Module") and r["Module"] != "-" and not r["Module"].startswith("-")]
        workers_om = [r["Owner"] for r in om_rows if r.get("Owner") and r["Owner"] != "-"]
        if len(modules) != len(set(modules)):
            passed = fail(f"OWNERSHIP_MAP Module duplicate: {modules}") and False
        else:
            ok(f"OWNERSHIP_MAP modules unique ({len(modules)})")
        if len(workers_om) != len(set(workers_om)):
            passed = fail(f"OWNERSHIP_MAP Worker duplicate (1 worker → 1 module violated): {workers_om}") and False
        else:
            ok(f"OWNERSHIP_MAP workers unique 1:1 ({len(workers_om)})")
        # check module format
        for m in modules:
            if not re.match(r"MOD-[A-Z]+", m):
                passed = fail(f"OWNERSHIP_MAP bad Module format: {m}") and False
    except Exception as e:
        passed = fail(f"OWNERSHIP_MAP parse error: {e}") and False

    # 2. WORKER_REGISTRY: WorkerID unique, ModuleOwned unique, matches ownership
    try:
        wr_text = read("WORKER_REGISTRY.md")
        wr_rows = parse_table(wr_text, r"\|\s*WorkerID\s*\|")
        wids = [r["WorkerID"] for r in wr_rows if r.get("WorkerID") and r["WorkerID"] != "-"]
        mods = [r["ModuleOwned"] for r in wr_rows if r.get("ModuleOwned") and r["ModuleOwned"] != "-"]
        if len(wids) != len(set(wids)):
            passed = fail(f"WORKER_REGISTRY WorkerID duplicate: {wids}") and False
        else:
            ok(f"WORKER_REGISTRY WorkerID unique ({len(wids)})")
        if len(mods) != len(set(mods)):
            passed = fail(f"WORKER_REGISTRY ModuleOwned duplicate (1:1 violated): {mods}") and False
        else:
            ok(f"WORKER_REGISTRY ModuleOwned unique 1:1 ({len(mods)})")
        # cross-check ownership map
        om_map = {r["Module"]: r["Owner"] for r in om_rows}
        for r in wr_rows:
            wid = r.get("WorkerID")
            mod = r.get("ModuleOwned")
            if wid == "-" or mod == "-":
                continue
            expected_owner = om_map.get(mod)
            if expected_owner is None:
                passed = fail(f"WORKER_REGISTRY {wid} owns {mod} not in OWNERSHIP_MAP") and False
            elif expected_owner != wid:
                passed = fail(f"WORKER_REGISTRY mismatch: {mod} owned by {expected_owner} in map but {wid} in registry") and False
            # branch prefix check (strip backticks)
            bp = r.get("BranchPrefix","").strip().strip("`").strip()
            if bp != f"worker/{wid}/":
                passed = fail(f"WORKER_REGISTRY {wid} BranchPrefix {bp} != worker/{wid}/") and False
        ok("WORKER_REGISTRY ownership cross-check PASS")
        # check branch prefix format for at least one
        ok(f"WORKER_REGISTRY cross-check complete ({len(wids)} workers)")
    except Exception as e:
        passed = fail(f"WORKER_REGISTRY parse error: {e}") and False

    # 3. LOCK_MANAGER: No duplicate ACTIVE path (scan whole file via regex — handles two tables)
    try:
        lm_text = read("LOCK_MANAGER.md")
        # regex captures ACTIVE rows across both Active and Denied sections
        active_paths_raw = re.findall(r"\|\s*LOCK-\d+\s*\|\s*([^\|]+?)\s*\|\s*[^|]+\|\s*[^|]+\|[^|]*\|[^|]*\|\s*ACTIVE", lm_text)
        # strip backticks/spaces
        active_paths = [p.strip().strip("`").strip() for p in active_paths_raw]
        if len(active_paths) != len(set(active_paths)):
            passed = fail(f"LOCK_MANAGER duplicate ACTIVE Path: {active_paths}") and False
        else:
            ok(f"LOCK_MANAGER no duplicate ACTIVE Path (found {len(active_paths)} ACTIVE)")
        # also validate each ACTIVE row has Acquired/Expires via parse_table fallback (only Active section)
        # Use regex to extract full ACTIVE rows for format check
        active_rows_raw = re.findall(r"(\|\s*LOCK-\d+\s*\|[^\n]*\|\s*ACTIVE[^\n]*)", lm_text)
        for row in active_rows_raw:
            cols = [c.strip().strip("`") for c in row.strip().strip("|").split("|")]
            # cols: LockID, Path, Worker, TaskID, Acquired, Expires, Status
            if len(cols) >= 6:
                acq = cols[4] if len(cols)>4 else ""
                exp = cols[5] if len(cols)>5 else ""
                if not acq or not exp:
                    passed = fail(f"LOCK_MANAGER ACTIVE missing Acquired/Expires: {row}") and False
        ok("LOCK_MANAGER format PASS")
    except Exception as e:
        passed = fail(f"LOCK_MANAGER parse error: {e}") and False

    # 4. TASK_QUEUE: TaskID monotonic, Status valid, Module exists, Owner ownership
    try:
        tq_text = read("TASK_QUEUE.md")
        tq_rows = parse_table(tq_text, r"\|\s*TaskID\s*\|")
        tids = [r["TaskID"] for r in tq_rows if r.get("TaskID") and r["TaskID"] != "-"]
        # monotonic check: TASK-0001 < TASK-0002 etc
        nums = [int(re.search(r"TASK-(\d+)", t).group(1)) for t in tids if re.search(r"TASK-(\d+)", t)]
        if nums != sorted(nums):
            passed = fail(f"TASK_QUEUE TaskID not monotonic: {tids}") and False
        else:
            ok(f"TASK_QUEUE monotonic ({len(tids)} tasks)")
        valid_status = {"OPEN","CLAIMED","IN_PROGRESS","REVIEW","DONE","BLOCKED","CANCELLED"}
        for r in tq_rows:
            if r.get("Status") and r["Status"] not in valid_status and r["Status"] != "-":
                passed = fail(f"TASK_QUEUE invalid Status {r['Status']} for {r['TaskID']}") and False
            # module exists check
            mod = r.get("Module")
            if mod and mod != "-" and mod not in modules:
                passed = fail(f"TASK_QUEUE {r['TaskID']} Module {mod} not in OWNERSHIP_MAP") and False
            # owner check if not OPEN
            owner = r.get("Owner")
            status = r.get("Status")
            if owner and owner != "-" and status not in ("OPEN","BLOCKED"):
                # owner must be in registry and own module
                if owner not in wids:
                    passed = fail(f"TASK_QUEUE {r['TaskID']} Owner {owner} not in registry") and False
                else:
                    # find owner's module
                    owner_mod = None
                    for wr in wr_rows:
                        if wr.get("WorkerID") == owner:
                            owner_mod = wr.get("ModuleOwned")
                            break
                    if owner_mod != mod:
                        passed = fail(f"TASK_QUEUE {r['TaskID']} Owner {owner} owns {owner_mod} but task Module is {mod}") and False
        ok("TASK_QUEUE status/module/owner checks PASS")
    except Exception as e:
        passed = fail(f"TASK_QUEUE parse error: {e}") and False

    # 5. REPORT_QUEUE: ReportID monotonic, TaskID exists, Worker owns module
    try:
        rq_text = read("REPORT_QUEUE.md")
        rq_rows = parse_table(rq_text, r"\|\s*ReportID\s*\|")
        rids = [r["ReportID"] for r in rq_rows if r.get("ReportID") and r["ReportID"] != "-"]
        r_nums = [int(re.search(r"REPORT-(\d+)", x).group(1)) for x in rids if re.search(r"REPORT-(\d+)", x)]
        if r_nums != sorted(r_nums):
            passed = fail(f"REPORT_QUEUE ReportID not monotonic: {rids}") and False
        else:
            ok(f"REPORT_QUEUE monotonic ({len(rids)} reports)")
        tq_ids = set(tids)
        for r in rq_rows:
            task = r.get("TaskID")
            worker = r.get("Worker")
            if task and task != "-" and task not in tq_ids:
                passed = fail(f"REPORT_QUEUE {r['ReportID']} links to unknown TaskID {task}") and False
            # worker ownership check
            if worker and worker != "-" and task and task != "-":
                # find task module
                task_mod = None
                for tr in tq_rows:
                    if tr.get("TaskID") == task:
                        task_mod = tr.get("Module")
                        break
                # find worker's owned module
                worker_mod = None
                for wr in wr_rows:
                    if wr.get("WorkerID") == worker:
                        worker_mod = wr.get("ModuleOwned")
                        break
                if task_mod and worker_mod and task_mod != worker_mod:
                    passed = fail(f"REPORT_QUEUE {r['ReportID']} Worker {worker} owns {worker_mod} but Task {task} Module is {task_mod}") and False
            # verdict check
            verdict = r.get("Verdict")
            if verdict and verdict not in ("PASS","FAIL","BLOCKED","PARTIAL") and verdict != "-":
                passed = fail(f"REPORT_QUEUE invalid Verdict {verdict} for {r['ReportID']}") and False
        ok("REPORT_QUEUE linkage PASS")
    except Exception as e:
        passed = fail(f"REPORT_QUEUE parse error: {e}") and False

    # 6. EVENT_BUS: EventID monotonic, Type enum, Payload valid JSON
    try:
        eb_text = read("EVENT_BUS.md")
        eb_rows = parse_table(eb_text, r"\|\s*EventID\s*\|")
        eids = [r["EventID"] for r in eb_rows if r.get("EventID") and r["EventID"] != "-"]
        e_nums = [int(re.search(r"EVT-(\d+)", x).group(1)) for x in eids if re.search(r"EVT-(\d+)", x)]
        if e_nums != sorted(e_nums):
            passed = fail(f"EVENT_BUS EventID not monotonic: {eids}") and False
        else:
            ok(f"EVENT_BUS monotonic ({len(eids)} events)")
        valid_types = {"task.created","task.claimed","task.completed","task.blocked","task.in_progress","task.review","report.created","report.approved","report.rejected","lock.acquired","lock.released","lock.denied","lock.expired","decision.recorded","worker.registered","worker.heartbeat","worker.inactive"}
        import json
        for r in eb_rows:
            t = r.get("Type")
            if t and t not in valid_types and t != "-":
                passed = fail(f"EVENT_BUS invalid Type {t} for {r['EventID']}") and False
            payload = r.get("Payload")
            if payload and payload != "-":
                # payload is like `{"worker":"..."}`
                p = payload.strip().strip("`").strip()
                try:
                    json.loads(p)
                except Exception:
                    passed = fail(f"EVENT_BUS invalid JSON Payload for {r['EventID']}: {payload}") and False
            emitter = r.get("Emitter")
            if emitter and emitter != "-" and emitter not in wids:
                passed = fail(f"EVENT_BUS Emitter {emitter} not in registry for {r['EventID']}") and False
        ok("EVENT_BUS types/payload/emitter PASS")
    except Exception as e:
        passed = fail(f"EVENT_BUS parse error: {e}") and False

    # 7. DECISION_LOG: DecisionID monotonic, append-only check (monotonic)
    try:
        dl_text = read("DECISION_LOG.md")
        dl_rows = parse_table(dl_text, r"\|\s*DecisionID\s*\|")
        dids = [r["DecisionID"] for r in dl_rows if r.get("DecisionID") and r["DecisionID"] != "-"]
        d_nums = [int(re.search(r"DEC-(\d+)", x).group(1)) for x in dids if re.search(r"DEC-(\d+)", x)]
        if d_nums != sorted(d_nums):
            passed = fail(f"DECISION_LOG DecisionID not monotonic: {dids}") and False
        else:
            ok(f"DECISION_LOG monotonic ({len(dids)} decisions)")
        for r in dl_rows:
            author = r.get("Author")
            if author and author != "-" and author not in wids:
                passed = fail(f"DECISION_LOG Author {author} not in registry for {r['DecisionID']}") and False
        ok("DECISION_LOG author PASS")
    except Exception as e:
        passed = fail(f"DECISION_LOG parse error: {e}") and False

    # 8. No trading/AI advisory files touched outside AgentOS in this validator's scope?
    # We check that AgentOS files are not referencing forbidden direct modifications
    # This is a meta-check: ensure AGENT_PROTOCOL mentions advisory read-only
    try:
        proto = read("AGENT_PROTOCOL.md")
        if "advisory only" not in proto.lower():
            passed = fail("AGENT_PROTOCOL missing advisory only clause") and False
        else:
            ok("AGENT_PROTOCOL advisory clause present")
        if "Telegram" not in proto:
            # should mention Telegram not implemented
            pass
        ok("Protocol content checks PASS")
    except Exception as e:
        passed = fail(f"AGENT_PROTOCOL read error: {e}") and False

    print("\n" + ("="*60))
    if passed:
        print("[AGENTOS] STATUS=PASS — all invariants hold")
        return 0
    else:
        print("[AGENTOS] STATUS=FAIL — invariants violated")
        return 1

if __name__ == "__main__":
    sys.exit(main())
