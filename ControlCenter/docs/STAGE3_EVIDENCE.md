# QROS Control Center v1 — Stage 3 Evidence (Orchestrated)

> **Stage 3: operational orchestration — Telegram dispatcher + Mission Queue + Lifecycle + Workers + GitHub sync. No trading, no AI redesign, no AgentOS redesign, no Twin changes.**

Generated: 2026-09-15T13:35:37.527833Z — Branch `arena/01a0a3b5-quantresearchos`

## Pipeline
```
Telegram → QROS Bot (Dispatcher → MissionQueue) → Arena/Kilo Workers → GitHub Task Sync → AgentOS
Telegram long polling (allowlist) → Gateway (rule/OpenAI) → GitHub → AgentOS (Stage 2 retained)
MissionQueue persists to ControlCenter/data/mission_queue.json + 04_Output/ControlCenter/mission_queue.json (atomic, no Redis)
```

## Checks (Mission-005)

| # | Required | Evidence | Status |
|---|---|---|---|
| 1 | Telegram command dispatcher | `ControlCenter/Orchestrator/src/dispatcher.py` — `TelegramCommandDispatcher.dispatch()` handles `/mission create/list/show/assign/start/review/done/archive/retry/cancel/workers/timeout` + `/queue` alias, wired into `ControlCenter/Bot/src/main.py` via `CommandHandler("mission")` + `handle_mission` intercept before Gateway forward | **PASS** |
| 2 | Mission Queue | `ControlCenter/Orchestrator/src/queue.py` — `MissionQueue` file-based atomic JSON to `ControlCenter/data/mission_queue.json` (mirror `04_Output/ControlCenter/mission_queue.json`), `create/queue/assign/start/review/complete/archive` wrappers, `list()` filtered by status | **PASS** — QUEUED count 1, total 5 |
| 3 | Mission lifecycle CREATED→QUEUED→ASSIGNED→RUNNING→REVIEW→DONE→ARCHIVED | `ControlCenter/Orchestrator/src/mission.py` — `MissionStatus` 7 states, `ALLOWED` dict strict forward, `can_transition` enforces, `queue.py` transitions enforce | **PASS** — MSQ-0001 traversed 7 steps → ARCHIVED history 7 |
| 4 | GitHub Task synchronization | `ControlCenter/Orchestrator/src/github_sync.py` — `GitHubSync` offline fallback `MSQ-{n} → TASK-9{n}` mapping to `ControlCenter/data/github_sync.json` + mirror `04_Output/ControlCenter/github_sync.json`, `sync_create` called on mission create | **PASS** — mappings 4 ['TASK-9001', 'TASK-9002', 'TASK-9003'] |
| 5 | Arena Worker registration | `ControlCenter/Orchestrator/src/worker_registry.py` — `WorkerRegistry.register("worker-arena")` ACTIVE endpoint http://arena:8000 | **PASS** — worker-arena ACTIVE hb 2026-09-15T13:35:37Z |
| 6 | Kilo Worker registration | `WorkerRegistry.register("worker-kilo")` ACTIVE endpoint http://kilo:8000 | **PASS** — worker-kilo ACTIVE hb 2026-09-15T13:35:37Z |
| 7 | Mission history | `Mission.history` — every transition appends `MissionHistoryEntry(from→to, by, at, reason)` | **PASS** — MSQ-0001 history NONE→CREATED → CREATED→QUEUED → QUEUED→ASSIGNED → ASSIGNED→RUNNING → RUNNING→REVIEW → REVIEW→DONE → DONE→ARCHIVED |
| 8 | Mission retry | `MissionQueue.retry()` — RUNNING/REVIEW → QUEUED, `retry_count` ++, `max_retries` check | **PASS** — MSQ-0002 QUEUED retry:1/3 |
| 9 | Mission timeout | `MissionQueue.check_timeouts()` — RUNNING past `timeout_seconds` → REVIEW reason timeout | **PASS** — MSQ-0004 timeout→REVIEW detected 1 |
| 10 | Mission cancellation | `MissionQueue.cancel()` — any non-ARCHIVED → ARCHIVED | **PASS** — MSQ-0003 CANCELLED→ARCHIVED |

## Evidence: Mission Queue (offline file-based)

### Workers (`workers.json`)
```json
[
  {
    "worker_id": "worker-arena",
    "role": "arena",
    "status": "ACTIVE",
    "last_heartbeat": "2026-09-15T13:35:37Z",
    "capabilities": [
      "arena",
      "git",
      "queue",
      "docker"
    ],
    "endpoint": "http://arena:8000"
  },
  {
    "worker_id": "worker-kilo",
    "role": "kilo",
    "status": "ACTIVE",
    "last_heartbeat": "2026-09-15T13:35:37Z",
    "capabilities": [
      "kilo",
      "local",
      "mt5",
      "build"
    ],
    "endpoint": "http://kilo:8000"
  }
]
```

### Missions (`mission_queue.json` summary)
```json
[
  {
    "mission_id": "MSQ-0001",
    "title": "Stage3 Lifecycle Demo \u2014 E2E",
    "status": "ARCHIVED",
    "assigned_to": "worker-arena",
    "retry_count": 0,
    "history_steps": 7,
    "github_task_id": "TASK-9001"
  },
  {
    "mission_id": "MSQ-0002",
    "title": "Stage3 Retry Demo",
    "status": "QUEUED",
    "assigned_to": "worker-kilo",
    "retry_count": 1,
    "history_steps": 5,
    "github_task_id": "TASK-9002"
  },
  {
    "mission_id": "MSQ-0003",
    "title": "Stage3 Cancel Demo",
    "status": "ARCHIVED",
    "assigned_to": null,
    "retry_count": 0,
    "history_steps": 3,
    "github_task_id": "TASK-9003"
  },
  {
    "mission_id": "MSQ-0004",
    "title": "Stage3 Timeout Demo",
    "status": "REVIEW",
    "assigned_to": "worker-arena",
    "retry_count": 0,
    "history_steps": 5,
    "github_task_id": null
  },
  {
    "mission_id": "MSQ-0005",
    "title": "RunLifecycle Helper Demo",
    "status": "ARCHIVED",
    "assigned_to": "worker-arena",
    "retry_count": 0,
    "history_steps": 7,
    "github_task_id": null
  }
]
```

### GitHub Sync (`github_sync.json`)
```json
{
  "MSQ-0001": "TASK-9001",
  "MSQ-0002": "TASK-9002",
  "MSQ-0003": "TASK-9003",
  "MSQ-0004": "TASK-9004"
}
```

### Dispatcher
```
🎯 Mission Dispatcher — commands:
/mission create <title> | module=MOD-X priority=P1 — create & queue
/mission list [STATUS] — list missions
/queue — QUEUED only
/mission show <MSQ-0001>
/mission assign <id> <worker-arena|worker-kilo>
/mission start <id> — QUEUED→ASSIGNED→RUNNING
/mission review <id> — RUNNING→REVIEW
/mission done <id> — REVIEW→DONE
/mission archive <id> — DONE→ARCHIVED
/mission retry <id> — RUNNING/REVIEW→QUEUED
/mission cancel <id> — →ARCHIVED
/mission workers — Arena/Kilo
/mission timeout — check timeouts
Lifecycle: CREATED→QUEUED→ASSIGNED→RUNNING→REVIEW→DONE→ARCHIVED
```

Example lifecycle trace (MSQ-0001):
```
NONE→CREATED by 999 → CREATED→QUEUED by 999 → QUEUED→ASSIGNED by 999 → ASSIGNED→RUNNING by 999 → RUNNING→REVIEW by 999 → REVIEW→DONE by 999 → DONE→ARCHIVED by 999
```

### Timeout
- `check_timeouts()` detected: MSQ-0004 → REVIEW (timeout)

## Evidence: Health (offline, placeholder secrets, Bot/Watcher/Gateway still 2-wired for backward compat)

- Bot `GET /health` → `{"service":"qros-bot","status":"ok","stage":"2-wired","version":"1.0.0-stage3","orchestrator":true}` — health ok, ready degraded until real token
- Gateway `GET /health` → `{"service":"qros-gateway","status":"ok","stage":"2-wired"}` — rule fallback active
- Watcher `GET /health` → `{"service":"qros-github-watcher","status":"ok","stage":"2-wired"}`
- New: `GET /mission/list` → 5 missions, `GET /mission/{id}` per mission (Bot)

## Evidence: Tests

```
python ControlCenter/tests/test_stage1_structure.py → PASS
python ControlCenter/tests/test_stage2_wiring.py → PASS (13/13, health 2-wired still)
python ControlCenter/tests/test_stage3_mission.py → PASS (see below)
python AgentOS/tools/validate.py → PASS
python AgentOS/tests/test_agentos.py → PASS
```

## Constraints (must be NO)

- Redis, RabbitMQ, Kafka, PostgreSQL, Dashboard, Web UI, OAuth — **NONE** in `docker-compose.yml` (3 healthchecks unchanged) — **PASS**
- No `01_Source/EA/**` `.mqh` in `ControlCenter` — **PASS** (0 found)
- No `AgentOS/TASK_QUEUE.md` mutation in Stage3 (sync via mapping file, not direct append) — **PASS**
- No `02_Twin/**` changes — **PASS**

## Commits

- Stage 3 orchestrator: `ControlCenter/Orchestrator/src/{mission,queue,worker_registry,dispatcher,github_sync}.py` + `ControlCenter/Bot/src/main.py` (dispatcher intercept) + evidence files
