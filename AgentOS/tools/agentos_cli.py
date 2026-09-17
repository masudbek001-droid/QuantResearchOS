#!/usr/bin/env python3
"""
AgentOS — CLI v1.0
Git-native helpers for Task/Report/Lock/Event/Worker operations.
Human and worker agents use this to avoid manual markdown editing errors.

Usage:
  python AgentOS/tools/agentos_cli.py task create --title "..." --module MOD-RESEARCH --priority P1 --files "path/**"
  python AgentOS/tools/agentos_cli.py task claim --id TASK-0001 --worker worker-research
  python AgentOS/tools/agentos_cli.py task update --id TASK-0001 --status IN_PROGRESS --worker worker-research
  python AgentOS/tools/agentos_cli.py report create --task TASK-0001 --worker worker-research --verdict PASS --artifacts "path/file"
  python AgentOS/tools/agentos_cli.py lock acquire --path "path/**" --worker worker-research --task TASK-0001
  python AgentOS/tools/agentos_cli.py event emit --emitter worker-research --type task.claimed --correlation TASK-0001 --payload '{"branch":"..."}'
"""
import argparse
import pathlib
import re
import sys
import json
from datetime import datetime, timezone, timedelta

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
AGENTOS = ROOT / "AgentOS"

def now_utc():
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

def now_utc_sec():
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

def read(path):
    return (AGENTOS / path).read_text(encoding="utf-8")

def write(path, content):
    (AGENTOS / path).write_text(content, encoding="utf-8")

def next_id(prefix, text):
    nums = [int(m.group(1)) for m in re.finditer(rf"{prefix}-(\d+)", text)]
    nxt = max(nums, default=0) + 1
    return f"{prefix}-{nxt:04d}"

# --- TASK ---

def task_create(args):
    tq = read("TASK_QUEUE.md")
    nid = next_id("TASK", tq)
    module = args.module
    # validate module exists in OWNERSHIP_MAP
    om = read("OWNERSHIP_MAP.md")
    if module not in om:
        print(f"[error] Module {module} not in OWNERSHIP_MAP.md", file=sys.stderr)
        sys.exit(1)
    new_row = f"| {nid} | {args.title} | {module} | - | OPEN | {args.priority} | `{args.files}` | - | {now_utc()} | {now_utc()} |"
    # insert before last line's summary
    lines = tq.splitlines()
    # find last table row (starts with | TASK-)
    last_idx = None
    for i, l in enumerate(lines):
        if re.match(r"\|\s*TASK-\d+", l):
            last_idx = i
    if last_idx is None:
        print("[error] TASK_QUEUE table not found", file=sys.stderr)
        sys.exit(1)
    lines.insert(last_idx+1, new_row)
    # update summary line
    for i, l in enumerate(lines):
        if l.startswith("*Last synced:"):
            # count OPEN
            open_cnt = sum(1 for ll in lines if "| OPEN |" in ll)
            # we added one, so recount after insert
            # simple: parse again
            pass
    new_content = "\n".join(lines) + "\n"
    write("TASK_QUEUE.md", new_content)
    # emit event
    event_emit_raw(args.worker or "worker-agentos", "task.created", nid, json.dumps({"title": args.title, "module": module}))
    print(f"created {nid}")

def task_claim(args):
    tq = read("TASK_QUEUE.md")
    tid = args.id
    worker = args.worker
    # find row
    if f"| {tid} |" not in tq:
        print(f"[error] Task {tid} not found", file=sys.stderr)
        sys.exit(1)
    # check ownership
    # parse task module
    m = re.search(rf"\|\s*{tid}\s*\|\s*[^|]+\|\s*([^|]+)\|", tq)
    if not m:
        print("[error] parse fail", file=sys.stderr)
        sys.exit(1)
    module = m.group(1).strip()
    # check worker owns module
    om = read("OWNERSHIP_MAP.md")
    wr = read("WORKER_REGISTRY.md")
    # find owner for module in ownership map
    # naive: check line contains module and worker
    if f"| {module} |" not in om:
        print(f"[error] module {module} not in map", file=sys.stderr)
        sys.exit(1)
    # find if worker owns module
    # look for row with module and worker
    if not re.search(rf"\|\s*{re.escape(module)}\s*\|[^|]*\|\s*[^|]*\|\s*{re.escape(worker)}\s*\|", om):
        print(f"[error] Worker {worker} does not own {module} per OWNERSHIP_MAP", file=sys.stderr)
        sys.exit(1)
    # check status is OPEN
    if f"| {tid} |" in tq:
        # extract status column (6th)
        line = [l for l in tq.splitlines() if f"| {tid} |" in l][0]
        cols = [c.strip() for c in line.strip().strip("|").split("|")]
        status = cols[4]
        if status != "OPEN":
            print(f"[error] Task {tid} status is {status}, not OPEN", file=sys.stderr)
            sys.exit(1)
    # perform claim: replace Owner, Status, Branch, Updated
    lines = tq.splitlines()
    new_lines = []
    for l in lines:
        if f"| {tid} |" in l and l.strip().startswith("|"):
            cols = [c.strip().strip("`") for c in l.strip().strip("|").split("|")]
            # columns: TaskID, Title, Module, Owner, Status, Priority, Files, Branch, Created, Updated
            cols[3] = worker
            cols[4] = "CLAIMED"
            cols[7] = f"worker/{worker}/{tid}"
            cols[9] = now_utc()
            # reconstruct with backticks for Files
            # cols[6] is Files without backticks; re-add
            files = cols[6]
            new_line = f"| {cols[0]} | {cols[1]} | {cols[2]} | {cols[3]} | {cols[4]} | {cols[5]} | `{files}` | {cols[7]} | {cols[8]} | {cols[9]} |"
            new_lines.append(new_line)
        else:
            new_lines.append(l)
    write("TASK_QUEUE.md", "\n".join(new_lines) + "\n")
    # acquire lock for Files path
    # extract files path from original line
    line = [l for l in tq.splitlines() if f"| {tid} |" in l][0]
    cols = [c.strip().strip("`") for c in line.strip().strip("|").split("|")]
    files_path = cols[6]
    # call lock acquire
    lock_acquire_raw(files_path, worker, tid, ttl=72)
    event_emit_raw(worker, "task.claimed", tid, json.dumps({"branch": f"worker/{worker}/{tid}"}))
    print(f"claimed {tid} as {worker}")

def task_update(args):
    tq = read("TASK_QUEUE.md")
    tid = args.id
    status = args.status
    worker = args.worker
    lines = tq.splitlines()
    new_lines = []
    found = False
    for l in lines:
        if f"| {tid} |" in l and l.strip().startswith("|"):
            cols = [c.strip().strip("`") for c in l.strip().strip("|").split("|")]
            if cols[3] != worker:
                print(f"[error] Task {tid} owned by {cols[3]}, not {worker}", file=sys.stderr)
                sys.exit(1)
            cols[4] = status
            cols[9] = now_utc()
            files = cols[6]
            new_line = f"| {cols[0]} | {cols[1]} | {cols[2]} | {cols[3]} | {cols[4]} | {cols[5]} | `{files}` | {cols[7]} | {cols[8]} | {cols[9]} |"
            new_lines.append(new_line)
            found = True
        else:
            new_lines.append(l)
    if not found:
        print(f"[error] {tid} not found", file=sys.stderr)
        sys.exit(1)
    write("TASK_QUEUE.md", "\n".join(new_lines) + "\n")
    event_emit_raw(worker, f"task.{status.lower()}", tid, json.dumps({"status": status}))
    print(f"updated {tid} -> {status}")

def lock_acquire_raw(path, worker, task, ttl=72):
    lm = read("LOCK_MANAGER.md")
    # check duplicate ACTIVE for same Path
    if re.search(rf"\|\s*LOCK-\d+\s*\|\s*{re.escape(path)}\s*\|[^|]*\|[^|]*\|[^|]*\|[^|]*\|\s*ACTIVE", lm):
        # append DENIED
        nid = next_id("LOCK", lm)
        row = f"| {nid} | {path} | {worker} | {task} | {now_utc()} | {(datetime.now(timezone.utc)+timedelta(hours=ttl)).strftime('%Y-%m-%d %H:%M UTC')} | DENIED | conflict |"
        # insert into history section (after ## Denied)
        # For simplicity, append before last sweep line
        lines = lm.splitlines()
        # find last ACTIVE row insert point
        last_idx = None
        for i, l in enumerate(lines):
            if re.match(r"\|\s*LOCK-\d+\s*\|", l):
                last_idx = i
        if last_idx is not None:
            lines.insert(last_idx+1, row)
        else:
            lines.append(row)
        write("LOCK_MANAGER.md", "\n".join(lines) + "\n")
        event_emit_raw(worker, "lock.denied", task, json.dumps({"path": path, "reason": "ACTIVE exists"}))
        print(f"[warn] lock DENIED for {path} (ACTIVE exists) -> {nid}", file=sys.stderr)
        return nid
    nid = next_id("LOCK", lm)
    expires = (datetime.now(timezone.utc) + timedelta(hours=ttl)).strftime("%Y-%m-%d %H:%M UTC")
    row = f"| {nid} | {path} | {worker} | {task} | {now_utc()} | {expires} | ACTIVE |"
    lines = lm.splitlines()
    # find header of Active Locks table and insert after last ACTIVE/placeholder
    last_idx = None
    for i, l in enumerate(lines):
        if re.match(r"\|\s*LOCK-\d+\s*\|", l) or l.strip() == "| - | - | - | - | - | - | - |":
            last_idx = i
        if l.strip().startswith("## Denied"):
            break
    if last_idx is not None:
        # if placeholder row exists, replace it
        if lines[last_idx].strip() == "| - | - | - | - | - | - | - |":
            lines[last_idx] = row
        else:
            lines.insert(last_idx+1, row)
    else:
        lines.append(row)
    write("LOCK_MANAGER.md", "\n".join(lines) + "\n")
    event_emit_raw(worker, "lock.acquired", task, json.dumps({"path": path, "lock": nid}))
    print(f"acquired {nid} for {path}")
    return nid

def lock_acquire(args):
    lock_acquire_raw(args.path, args.worker, args.task, ttl=args.ttl)

def report_create(args):
    rq = read("REPORT_QUEUE.md")
    nid = next_id("REPORT", rq)
    tq = read("TASK_QUEUE.md")
    if f"| {args.task} |" not in tq:
        print(f"[error] Task {args.task} not found", file=sys.stderr)
        sys.exit(1)
    row = f"| {nid} | {args.task} | {args.worker} | PENDING | {args.verdict} | `{args.artifacts}` | {now_utc()} |"
    lines = rq.splitlines()
    last_idx = None
    for i, l in enumerate(lines):
        if re.match(r"\|\s*REPORT-\d+", l):
            last_idx = i
    if last_idx is None:
        print("[error] REPORT_QUEUE table not found", file=sys.stderr)
        sys.exit(1)
    lines.insert(last_idx+1, row)
    write("REPORT_QUEUE.md", "\n".join(lines) + "\n")
    # update TASK_QUEUE to REVIEW
    tq_lines = read("TASK_QUEUE.md").splitlines()
    new_tq = []
    for l in tq_lines:
        if f"| {args.task} |" in l and l.strip().startswith("|"):
            cols = [c.strip().strip("`") for c in l.strip().strip("|").split("|")]
            cols[4] = "REVIEW"
            cols[9] = now_utc()
            files = cols[6]
            new_line = f"| {cols[0]} | {cols[1]} | {cols[2]} | {cols[3]} | {cols[4]} | {cols[5]} | `{files}` | {cols[7]} | {cols[8]} | {cols[9]} |"
            new_tq.append(new_line)
        else:
            new_tq.append(l)
    write("TASK_QUEUE.md", "\n".join(new_tq) + "\n")
    event_emit_raw(args.worker, "report.created", nid, json.dumps({"task": args.task, "verdict": args.verdict}))
    print(f"created {nid} for {args.task}")

def event_emit_raw(emitter, typ, correlation, payload):
    eb = read("EVENT_BUS.md")
    nid = next_id("EVT", eb)
    # payload must be JSON string
    try:
        json.loads(payload)
    except:
        payload = json.dumps({"detail": payload})
    row = f"| {nid} | {now_utc_sec()} | {emitter} | {typ} | {correlation} | `{payload}` |"
    lines = eb.splitlines()
    last_idx = None
    for i, l in enumerate(lines):
        if re.match(r"\|\s*EVT-\d+", l):
            last_idx = i
    if last_idx is None:
        print("[error] EVENT_BUS table not found", file=sys.stderr)
        sys.exit(1)
    lines.insert(last_idx+1, row)
    write("EVENT_BUS.md", "\n".join(lines) + "\n")
    print(f"event {nid} {typ}")

def event_emit(args):
    event_emit_raw(args.emitter, args.type, args.correlation, args.payload)

def main():
    parser = argparse.ArgumentParser(prog="agentos_cli")
    sub = parser.add_subparsers(dest="cmd")

    # task
    p_task = sub.add_parser("task")
    p_task_sub = p_task.add_subparsers(dest="sub")
    p_create = p_task_sub.add_parser("create")
    p_create.add_argument("--title", required=True)
    p_create.add_argument("--module", required=True)
    p_create.add_argument("--priority", default="P2")
    p_create.add_argument("--files", required=True)
    p_create.add_argument("--worker", default="worker-agentos")
    p_create.set_defaults(func=lambda a: task_create(a))

    p_claim = p_task_sub.add_parser("claim")
    p_claim.add_argument("--id", required=True)
    p_claim.add_argument("--worker", required=True)
    p_claim.set_defaults(func=lambda a: task_claim(a))

    p_update = p_task_sub.add_parser("update")
    p_update.add_argument("--id", required=True)
    p_update.add_argument("--status", required=True)
    p_update.add_argument("--worker", required=True)
    p_update.set_defaults(func=lambda a: task_update(a))

    # lock
    p_lock = sub.add_parser("lock")
    p_lock_sub = p_lock.add_subparsers(dest="sub")
    p_acq = p_lock_sub.add_parser("acquire")
    p_acq.add_argument("--path", required=True)
    p_acq.add_argument("--worker", required=True)
    p_acq.add_argument("--task", required=True)
    p_acq.add_argument("--ttl", type=int, default=72)
    p_acq.set_defaults(func=lambda a: lock_acquire(a))

    # report
    p_report = sub.add_parser("report")
    p_report_sub = p_report.add_subparsers(dest="sub")
    p_rep_create = p_report_sub.add_parser("create")
    p_rep_create.add_argument("--task", required=True)
    p_rep_create.add_argument("--worker", required=True)
    p_rep_create.add_argument("--verdict", required=True)
    p_rep_create.add_argument("--artifacts", required=True)
    p_rep_create.set_defaults(func=lambda a: report_create(a))

    # event
    p_event = sub.add_parser("event")
    p_event_sub = p_event.add_subparsers(dest="sub")
    p_evt_emit = p_event_sub.add_parser("emit")
    p_evt_emit.add_argument("--emitter", required=True)
    p_evt_emit.add_argument("--type", required=True)
    p_evt_emit.add_argument("--correlation", required=True)
    p_evt_emit.add_argument("--payload", required=True)
    p_evt_emit.set_defaults(func=lambda a: event_emit(a))

    args = parser.parse_args()
    if not hasattr(args, "func"):
        parser.print_help()
        sys.exit(1)
    args.func(args)

if __name__ == "__main__":
    main()
