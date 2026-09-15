# AgentOS — Example Workflow v1.0

**Traced example:** `TASK-0003` — *Seed TASK_QUEUE with example workflow* — `MOD-AGENTOS` — `worker-agentos` (orchestrator also acts as worker for AgentOS module).

This is the exact Git-based sequence workers follow. No direct messages — only commits.

---

## 0. Initial State (after MVP commit)

* `TASK_QUEUE.md`: `TASK-0003 | Seed TASK_QUEUE... | MOD-AGENTOS | - | OPEN | P1 | AgentOS/TASK_QUEUE.md | -`
* `LOCK_MANAGER.md`: 0 ACTIVE
* `EVENT_BUS.md`: `EVT-0004 task.created TASK-0003`
* Branch: `arena/01a0a3b5-quantresearchos`

---

## 1. Orchestrator Creates Task (already done at seed)

```bash
git fetch origin && git pull --ff-only
python AgentOS/tools/agentos_cli.py task create --title "Seed TASK_QUEUE with example workflow" --module MOD-AGENTOS --priority P1 --files "AgentOS/TASK_QUEUE.md"
# → appends TASK-0003 to TASK_QUEUE.md
# → appends EVT-0004 task.created to EVENT_BUS.md
# → commit: [AgentOS][TASK-0003][worker-agentos] create: Seed TASK_QUEUE with example workflow
# → git push origin arena/...
```

---

## 2. Worker Polls & Claims

```bash
git fetch origin && git pull --ff-only
cat AgentOS/TASK_QUEUE.md  # finds TASK-0003 OPEN, Module=MOD-AGENTOS, I am worker-agentos → owns it
cat AgentOS/OWNERSHIP_MAP.md  # confirms MOD-AGENTOS → worker-agentos
cat AgentOS/LOCK_MANAGER.md  # no ACTIVE lock on AgentOS/TASK_QUEUE.md

python AgentOS/tools/agentos_cli.py task claim --id TASK-0003 --worker worker-agentos
# → validates ownership 1:1
# → TASK_QUEUE.md: Owner=worker-agentos, Status=CLAIMED, Branch=worker/worker-agentos/TASK-0003, Updated=now
# → LOCK_MANAGER.md: LOCK-0001 | AgentOS/TASK_QUEUE.md | worker-agentos | TASK-0003 | ACTIVE
# → EVENT_BUS.md: EVT-0006 task.claimed TASK-0003 {"branch":"worker/worker-agentos/TASK-0003"}
# → commit: [AgentOS][TASK-0003][worker-agentos] claim: Seed TASK_QUEUE with example workflow
# → git checkout -b worker/worker-agentos/TASK-0003
# → git push -u origin worker/worker-agentos/TASK-0003
```

**Git diff for CLAIM (excerpt):**
```diff
- | TASK-0003 | ... | - | OPEN | ...
+ | TASK-0003 | ... | worker-agentos | CLAIMED | ... | worker/worker-agentos/TASK-0003 | ...
```

---

## 3. Worker Moves to IN_PROGRESS & Works

```bash
python AgentOS/tools/agentos_cli.py task update --id TASK-0003 --status IN_PROGRESS --worker worker-agentos
# → TASK_QUEUE.md Status=IN_PROGRESS
# → EVENT_BUS.md EVT-0007 task.in_progress
# → commit & push

# Now edit owned files (only AgentOS/TASK_QUEUE.md is locked, but owned)
# Simulate: add comment to TASK_QUEUE.md example section
echo "<!-- worked 2026-09-15 -->" >> AgentOS/TASK_QUEUE.md
git add AgentOS/TASK_QUEUE.md AgentOS/EVENT_BUS.md
git commit -m "[AgentOS][TASK-0003][worker-agentos] work: document example workflow trace"
git push
```

---

## 4. Worker Reports & Moves to REVIEW

```bash
python AgentOS/tools/agentos_cli.py report create --task TASK-0003 --worker worker-agentos --verdict PASS --artifacts "AgentOS/TASK_QUEUE.md,AgentOS/EVENT_BUS.md"
# → REPORT_QUEUE.md: REPORT-0002 | TASK-0003 | worker-agentos | PENDING | PASS | ...
# → TASK_QUEUE.md: Status=REVIEW
# → EVENT_BUS.md: EVT-0008 report.created REPORT-0002, EVT-0009 task.review
# → commit: [AgentOS][TASK-0003][worker-agentos] report: PASS — example workflow seeded
# → git push
```

**Report row:**
```
| REPORT-0002 | TASK-0003 | worker-agentos | PENDING | PASS | AgentOS/TASK_QUEUE.md,AgentOS/EVENT_BUS.md | 2026-09-15 07:40 UTC |
```

---

## 5. Orchestrator Reviews & Merges

```bash
git fetch origin && git checkout arena/01a0a3b5-quantresearchos && git pull
git fetch origin worker/worker-agentos/TASK-0003
# Review diff, run validate
python AgentOS/tools/validate.py  # → AGENTOS PASS
python AgentOS/tests/test_agentos.py  # → PASS

python AgentOS/tools/agentos_cli.py report approve --id REPORT-0002 --worker worker-agentos
# → REPORT_QUEUE.md Status=APPROVED
# → TASK_QUEUE.md Status=DONE, Updated=now
# → LOCK_MANAGER.md LOCK-0001 Status=RELEASED
# → EVENT_BUS.md EVT-0010 report.approved, EVT-0011 task.completed, EVT-0012 lock.released
# → commit: [AgentOS][TASK-0003][worker-agentos] approve: REPORT-0002 PASS

# Merge
git merge --no-ff worker/worker-agentos/TASK-0003 -m "Merge worker/worker-agentos/TASK-0003 — TASK-0003 DONE"
git push origin arena/01a0a3b5-quantresearchos
```

---

## 6. Final State

* `TASK_QUEUE.md`: `TASK-0003 | ... | worker-agentos | DONE | ...`
* `REPORT_QUEUE.md`: `REPORT-0002 | TASK-0003 | APPROVED | PASS`
* `LOCK_MANAGER.md`: `LOCK-0001 | ... | RELEASED`
* `EVENT_BUS.md`: 7 events for TASK-0003 (`created → claimed → in_progress → report.created → review → approved → completed → lock.released`)
* Branch `worker/worker-agentos/TASK-0003` merged, may be deleted.

---

## What This Proves

* Every step is a Git commit + push — no direct agent call.
* Lock prevents two workers editing `AgentOS/TASK_QUEUE.md` concurrently.
* Report links Task → Worker → Artifacts → Verdict → Review → Done.
* Event bus gives ordered history for any late-joining worker to replay.
* Ownership map guarantees worker-agentos is the only writer to MOD-AGENTOS (unless locked).

Copy this template for any `MOD-*`: replace `TASK-0003/MOD-AGENTOS/worker-agentos` with your `TASK-xxxx/MOD-YYYY/worker-zzzz` and repeat steps 2–5.
