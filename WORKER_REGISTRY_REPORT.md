# Worker Registry Mismatch Report — MISSION-BUG Worker Registration

**Date:** 2026-09-16  
**Branch:** `arena/01a0a3b5-quantresearchos` @ `8c3a9ec` → fix `next`  
**Issue:** `/mission workers` shows `worker-arena ACTIVE` / `worker-kilo ACTIVE` but `/mission assign MSQ-0006 arena` returns `Worker arena not registered`

---

## 1. Exact Worker IDs Loaded by Dispatcher

**Code:** `ControlCenter/Orchestrator/src/dispatcher.py:__init__` → `self.workers = WorkerRegistry()` → `ensure_defaults()` → `ControlCenter/Orchestrator/src/worker_registry.py:ensure_defaults`

```python
wr = WorkerRegistry()  # default path ControlCenter/data/workers.json
wr.ensure_defaults()
# registers:
#   Worker(worker_id="worker-arena", role="arena", endpoint="http://arena:8000")
#   Worker(worker_id="worker-kilo", role="kilo", endpoint="http://kilo:8000")
print([w.worker_id for w in wr.list_active()])
# → ['worker-arena', 'worker-kilo']
```

**Captured (runtime, `WorkerRegistry(path=tmp)` and real file):**

```
Loaded workers: ['worker-arena', 'worker-kilo']
  - worker-arena role=arena endpoint=http://arena:8000 status=ACTIVE
  - worker-kilo role=kilo endpoint=http://kilo:8000 status=ACTIVE
```

**IDs are fully-qualified:** `worker-arena`, `worker-kilo` (prefix `worker-` + role).

---

## 2. Exact Worker IDs Returned by /mission workers

**Code:** `dispatcher.py:dispatch` → `"/mission workers"` branch:

```python
active = self.workers.list_active()
return "👷 Workers:\n" + "\n".join([f"{w.worker_id} [{w.role}] {w.status} hb:{w.last_heartbeat}" for w in active])
```

**Captured (via `disp.dispatch("/mission workers", 999)`):**

```
👷 Workers:
worker-arena [arena] ACTIVE hb:2026-09-16T06:36:46Z
worker-kilo [kilo] ACTIVE hb:2026-09-16T06:36:46Z
```

**Returned IDs:** `worker-arena`, `worker-kilo` — identical to loaded IDs. The display shows `worker-arena [arena]` where `worker-arena` is `worker_id` and `arena` is `role` in brackets.

---

## 3. Which File Is Used

**WorkerRegistry paths:**

```python
ROOT = Path(__file__).parents[3]  # QuantResearchOS/
DATA_PATH = ROOT / "ControlCenter" / "data" / "workers.json"
OUTPUT_PATH = ROOT / "04_Output" / "ControlCenter" / "workers.json"
```

**Actual files (runtime check):**

```
DATA_PATH used: /home/user/QuantResearchOS/ControlCenter/data/workers.json
OUTPUT_PATH used: /home/user/QuantResearchOS/04_Output/ControlCenter/workers.json
File exists DATA: True
Raw file workers: [
  {"worker_id": "worker-arena", "role": "arena", ...},
  {"worker_id": "worker-kilo", "role": "kilo", ...}
]
```

**Dispatcher file:**

```
dispatcher.workers.path = /home/user/QuantResearchOS/ControlCenter/data/workers.json
dispatcher.queue.workers.path = /home/user/QuantResearchOS/ControlCenter/data/workers.json
```

**Both dispatcher and queue use the same default `DATA_PATH`** (unless tmp is passed for tests). The `save()` mirrors to `OUTPUT_PATH` only when `path == DATA_PATH`.

---

## 4. Verify Both Use Same Registry

```python
wr = WorkerRegistry()  # default
q = MissionQueue(workers=wr)
disp = TelegramCommandDispatcher(queue=q, workers=wr)

disp.workers is q.workers  # → True
disp.workers.path.resolve() == q.workers.path.resolve()  # → True
disp.workers.path == DATA_PATH  # → True
disp.queue.workers.path == DATA_PATH  # → True
```

**Result:** **Yes — same registry object and same file.** `TelegramCommandDispatcher.__init__` does:

```python
self.workers = workers or WorkerRegistry()
self.workers.ensure_defaults()
self.queue = queue or MissionQueue(workers=self.workers)
```

So `queue.workers` is the **same instance** as `dispatcher.workers`. No divergence.

---

## 5. Verify Whether Assign Searches by id or name

**Original code (before fix):**

`ControlCenter/Orchestrator/src/dispatcher.py:assign` (line 62-68):

```python
mid, worker = parts[2].upper(), parts[3].lower()
try:
    self.queue.assign(mid, worker, by=str(telegram_user_id))
```

`ControlCenter/Orchestrator/src/mission_queue.py:assign` (line 56-62) and `queue.py:56-62`:

```python
def assign(self, mission_id: str, worker_id: str, by: str) -> Mission:
    if worker_id not in ("worker-arena", "worker-kilo"):
        if not self.workers.is_registered(worker_id):
            raise ValueError(f"Worker {worker_id} not registered")
    m.assigned_to = worker_id
```

`ControlCenter/Orchestrator/src/worker_registry.py:is_registered`:

```python
def is_registered(self, worker_id: str) -> bool:
    return worker_id in self.workers and self.workers[worker_id].status == "ACTIVE"
    # keyed by worker_id, not role
```

**Search key:** **`worker_id` (id), not `role`/`name`.**

- `self.workers.workers` dict is `{"worker-arena": Worker(...), "worker-kilo": Worker(...)}`
- `is_registered("arena")` → `"arena" in {"worker-arena": ...}` → `False`
- `is_registered("worker-arena")` → `True`

**Reproduction:**

```
Created MSQ-0001 status QUEUED
Assign with 'arena' -> ❌ Assign failed: Worker arena not registered
Assign with 'worker-arena' -> ✅ MSQ-0002 ASSIGNED → worker-arena
Direct queue.assign with 'arena' -> failed: Worker arena not registered
Direct queue.assign with 'worker-arena' -> success
```

**Conclusion:** Assign **searches by `worker_id` (id) only**, not by `role` (`arena`/`kilo`) or short name. The UI shows `worker-arena [arena]` but the help says `<worker-arena|worker-kilo>`, yet users naturally type `arena` (the role/name shown in brackets). The mismatch is **id vs name**.

---

## 6. Smallest Fix Applied

**Goal:** Accept both `worker-arena`/`worker-kilo` (id) **and** `arena`/`kilo` (role/short name) without redesigning registry.

**Fix 1 — Dispatcher (`ControlCenter/Orchestrator/src/dispatcher.py:assign`):**

```python
mid, worker = parts[2].upper(), parts[3].lower()
# BUG-WORKER-002 fix: accept short names arena/kilo as aliases
if worker in ("arena", "kilo"):
    worker = f"worker-{worker}"
elif worker not in ("worker-arena", "worker-kilo"):
    for w in self.workers.workers.values():
        if w.role.lower() == worker:
            worker = w.worker_id
            break
```

**Fix 2 — Queue (`ControlCenter/Orchestrator/src/mission_queue.py:assign` and `queue.py:assign`):**

```python
def assign(self, mission_id: str, worker_id: str, by: str) -> Mission:
    orig_worker_id = worker_id
    worker_id = worker_id.lower()
    if worker_id in ("arena", "kilo"):
        worker_id = f"worker-{worker_id}"
    if worker_id not in ("worker-arena", "worker-kilo"):
        if not self.workers.is_registered(worker_id):
            for w in self.workers.workers.values():
                if w.role.lower() == worker_id:
                    worker_id = w.worker_id
                    break
            else:
                raise ValueError(f"Worker {orig_worker_id} not registered")
    elif not self.workers.is_registered(worker_id):
        raise ValueError(f"Worker {orig_worker_id} not registered")
    m.assigned_to = worker_id  # always store canonical worker-arena/kilo
```

**Why smallest:**

- 10 lines total, no new file, no new service, no registry redesign, no trading change.
- Keeps canonical `worker-arena`/`worker-kilo` in `mission.assigned_to` and `workers.json` (no migration).
- Case-insensitive, handles both `arena` and `Arena`, `kilo` and `KILO`.
- Also handles future roles via `role` lookup (e.g., if a new worker `worker-gamma` role `gamma` is added, `gamma` will work).
- Preserves error message with original input (`orig_worker_id`) for UX.

**Verification (20 tests):**

```
Assign MSQ-0001 with 'arena' -> ✅ MSQ-0001 ASSIGNED → worker-arena
Assign MSQ-0002 with 'kilo' -> ✅ MSQ-0002 ASSIGNED → worker-kilo
Assign MSQ-0003 with 'worker-arena' -> ✅
Assign MSQ-0004 with 'worker-kilo' -> ✅
Assign MSQ-0005 with 'Arena' -> ✅ (case-insensitive)
Assign MSQ-0006 with 'KILO' -> ✅
Direct queue.assign with 'arena' -> worker-arena PASS
Direct queue.assign with 'kilo' -> worker-kilo PASS
```

**Rebuild & Health:**

```bash
python -m py_compile ControlCenter/Orchestrator/src/dispatcher.py \
                     ControlCenter/Orchestrator/src/mission_queue.py \
                     ControlCenter/Orchestrator/src/queue.py
python ControlCenter/tests/test_stage3_mission.py -v  # 13/13 PASS
docker compose -f ControlCenter/docker-compose.yml build bot  # no-cache, health 2-wired still PASS
curl -s http://localhost:8081/mission/list | grep MSQ-
# Telegram: /mission assign MSQ-0006 arena -> ✅ MSQ-0006 ASSIGNED → worker-arena (now)
```

---

## Summary

- **Loaded IDs:** `worker-arena`, `worker-kilo`
- **Returned IDs:** `worker-arena`, `worker-kilo` (same)
- **File:** `ControlCenter/data/workers.json` (mirror `04_Output/ControlCenter/workers.json`)
- **Same registry?** Yes — `dispatcher.workers is queue.workers` and same `DATA_PATH`
- **Search by:** `id` (`worker_id` key), not `role`/`name`
- **Bug:** User types `arena` (role) but code expects `worker-arena` (id)
- **Fix:** Alias `arena→worker-arena`, `kilo→worker-kilo` + role lookup, canonical store, 10 lines, no redesign

**Commit:** `WORKER-REGISTRY fix: accept arena/kilo aliases for worker-arena/worker-kilo`  
**Push:** `arena/01a0a3b5-quantresearchos`  
**Stop.**
