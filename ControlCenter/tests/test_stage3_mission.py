#!/usr/bin/env python3
"""
QROS Control Center v1 — Stage 3 orchestration test (MISSION-005).

Validates that Stage 2 wiring + Stage 3 orchestration operational:

1. Telegram command dispatcher
2. Mission Queue
3. Mission lifecycle CREATED→QUEUED→ASSIGNED→RUNNING→REVIEW→DONE→ARCHIVED
4. GitHub Task synchronization
5. Arena Worker registration
6. Kilo Worker registration
7. Mission history
8. Mission retry
9. Mission timeout
10. Mission cancellation

Plus constraints: NO Redis/RabbitMQ/Kafka/Postgres/Dashboard, NO trading/AgentOS/Twin mutation.
Evidence required: Mission Queue PASS, Arena registered, Kilo registered, lifecycle PASS, Tests, Commit, Push.

Run: python ControlCenter/tests/test_stage3_mission.py -v
"""
import pathlib, re, unittest, sys, json, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
CC = ROOT / "ControlCenter"
ORCH_SRC = CC / "Orchestrator" / "src"
sys.path.insert(0, str(ORCH_SRC))

from mission import MissionStatus, Mission, can_transition, can_retry, can_cancel, ALLOWED
from worker_registry import WorkerRegistry
from queue import MissionQueue
from dispatcher import TelegramCommandDispatcher
from github_sync import GitHubSync


def read(p: pathlib.Path) -> str:
    return p.read_text(encoding="utf-8", errors="ignore")

class TestStage3Mission(unittest.TestCase):

    def test_mission_lifecycle_model(self):
        # MissionStatus 7 states
        self.assertEqual([s.value for s in MissionStatus], ["CREATED","QUEUED","ASSIGNED","RUNNING","REVIEW","DONE","ARCHIVED"])
        # ALLOWED forward
        self.assertIn(MissionStatus.QUEUED, ALLOWED[MissionStatus.CREATED])
        self.assertIn(MissionStatus.ASSIGNED, ALLOWED[MissionStatus.QUEUED])
        self.assertIn(MissionStatus.RUNNING, ALLOWED[MissionStatus.ASSIGNED])
        self.assertIn(MissionStatus.REVIEW, ALLOWED[MissionStatus.RUNNING])
        self.assertIn(MissionStatus.DONE, ALLOWED[MissionStatus.REVIEW])
        self.assertIn(MissionStatus.ARCHIVED, ALLOWED[MissionStatus.DONE])
        # can_transition
        self.assertTrue(can_transition(MissionStatus.CREATED, MissionStatus.QUEUED))
        self.assertTrue(can_transition(MissionStatus.QUEUED, MissionStatus.ASSIGNED))
        self.assertFalse(can_transition(MissionStatus.CREATED, MissionStatus.RUNNING), "strict forward only")
        self.assertFalse(can_transition(MissionStatus.DONE, MissionStatus.RUNNING))
        self.assertFalse(can_transition(MissionStatus.ARCHIVED, MissionStatus.CREATED))
        # can_retry only RUNNING/REVIEW
        self.assertTrue(can_retry(MissionStatus.RUNNING))
        self.assertTrue(can_retry(MissionStatus.REVIEW))
        self.assertFalse(can_retry(MissionStatus.QUEUED))
        self.assertFalse(can_retry(MissionStatus.DONE))
        # can_cancel any non-ARCHIVED
        self.assertTrue(can_cancel(MissionStatus.CREATED))
        self.assertTrue(can_cancel(MissionStatus.RUNNING))
        self.assertFalse(can_cancel(MissionStatus.ARCHIVED))
        # Mission dataclass defaults
        m = Mission(mission_id="MSQ-0001", title="Test")
        self.assertEqual(m.status, MissionStatus.CREATED)
        self.assertEqual(m.retry_count, 0)
        self.assertIsInstance(m.history, list)

    def test_worker_registry_arena_kilo(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "workers.json"
            wr = WorkerRegistry(path=path)
            wr.ensure_defaults()
            active = wr.list_active()
            ids = {w.worker_id for w in active}
            self.assertIn("worker-arena", ids, "Arena worker must be registered")
            self.assertIn("worker-kilo", ids, "Kilo worker must be registered")
            self.assertEqual(len(active), 2)
            for w in active:
                self.assertEqual(w.status, "ACTIVE")
                self.assertTrue(w.last_heartbeat)
            # heartbeat — force past timestamp then ensure heartbeat updates to newer time
            import datetime, time
            # set to past 5s ago so next heartbeat must be newer
            wr.get("worker-arena").last_heartbeat = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=5)).strftime("%Y-%m-%dT%H:%M:%SZ")
            hb_old = wr.get("worker-arena").last_heartbeat
            # ensure at least 1s difference (utcnow is second-granular)
            time.sleep(1.1)
            wr.heartbeat("worker-arena")
            hb_new = wr.get("worker-arena").last_heartbeat
            self.assertNotEqual(hb_old, hb_new)
            # also show ACTIVE
            self.assertEqual(wr.get("worker-arena").status, "ACTIVE")
            # persistence mirror check
            self.assertTrue(path.is_file())
            # also check real persistence
            real_workers = CC / "data" / "workers.json"
            if real_workers.is_file():
                data = json.loads(real_workers.read_text())
                workers = {w["worker_id"]: w for w in data.get("workers", [])}
                self.assertIn("worker-arena", workers, "real workers.json must have arena")
                self.assertIn("worker-kilo", workers, "real workers.json must have kilo")
                self.assertEqual(workers["worker-arena"]["status"], "ACTIVE")
                self.assertEqual(workers["worker-kilo"]["status"], "ACTIVE")

    def test_mission_queue_lifecycle(self):
        with tempfile.TemporaryDirectory() as tmp:
            qpath = pathlib.Path(tmp) / "mission_queue.json"
            wpath = pathlib.Path(tmp) / "workers.json"
            wr = WorkerRegistry(path=wpath)
            wr.ensure_defaults()
            q = MissionQueue(path=qpath, workers=wr)
            q.missions.clear()
            q.next_id = 1
            q.save()
            # create
            m = q.create(title="Lifecycle Test", module="MOD-TEST", priority="P1", created_by="tester")
            self.assertEqual(m.mission_id, "MSQ-0001")
            self.assertEqual(m.status, MissionStatus.CREATED)
            self.assertEqual(len(m.history), 1)
            # queue
            q.queue(m.mission_id, by="tester")
            self.assertEqual(q.get(m.mission_id).status, MissionStatus.QUEUED)
            self.assertEqual(len(q.get(m.mission_id).history), 2)
            # assign
            q.assign(m.mission_id, "worker-arena", by="tester")
            self.assertEqual(q.get(m.mission_id).status, MissionStatus.ASSIGNED)
            self.assertEqual(q.get(m.mission_id).assigned_to, "worker-arena")
            # start
            q.start(m.mission_id, by="tester")
            self.assertEqual(q.get(m.mission_id).status, MissionStatus.RUNNING)
            # review
            q.review(m.mission_id, by="tester")
            self.assertEqual(q.get(m.mission_id).status, MissionStatus.REVIEW)
            # done
            q.complete(m.mission_id, by="tester")
            self.assertEqual(q.get(m.mission_id).status, MissionStatus.DONE)
            # archive
            q.archive(m.mission_id, by="tester")
            self.assertEqual(q.get(m.mission_id).status, MissionStatus.ARCHIVED)
            self.assertEqual(len(q.get(m.mission_id).history), 7)
            # invalid transition must fail
            m2 = q.create(title="Bad Transition", created_by="tester")
            q.queue(m2.mission_id, by="tester")
            with self.assertRaises(ValueError):
                q.complete(m2.mission_id, by="tester")  # QUEUED -> DONE invalid
            # persistence reload
            q2 = MissionQueue(path=qpath, workers=wr)
            self.assertEqual(len(q2.missions), 2)
            self.assertEqual(q2.get(m.mission_id).status, MissionStatus.ARCHIVED)

    def test_mission_history(self):
        with tempfile.TemporaryDirectory() as tmp:
            qpath = pathlib.Path(tmp) / "mission_queue.json"
            wr = WorkerRegistry(path=pathlib.Path(tmp)/"workers.json")
            wr.ensure_defaults()
            q = MissionQueue(path=qpath, workers=wr)
            q.missions.clear()
            q.next_id = 1
            q.save()
            m = q.create(title="History Test", created_by="alice")
            q.queue(m.mission_id, by="alice")
            q.assign(m.mission_id, "worker-kilo", by="bob")
            h = q.get(m.mission_id).history
            self.assertEqual(h[0]["from_status"], "NONE")
            self.assertEqual(h[0]["to_status"], "CREATED")
            self.assertEqual(h[1]["from_status"], "CREATED")
            self.assertEqual(h[1]["to_status"], "QUEUED")
            self.assertEqual(h[2]["to_status"], "ASSIGNED")
            # each has at, by
            for entry in h:
                self.assertIn("at", entry)
                self.assertIn("by", entry)

    def test_mission_retry(self):
        with tempfile.TemporaryDirectory() as tmp:
            qpath = pathlib.Path(tmp) / "mission_queue.json"
            wr = WorkerRegistry(path=pathlib.Path(tmp)/"workers.json")
            wr.ensure_defaults()
            q = MissionQueue(path=qpath, workers=wr)
            q.missions.clear()
            q.next_id = 1
            m = q.create(title="Retry Test", created_by="tester", max_retries=2)
            q.queue(m.mission_id, by="tester")
            q.assign(m.mission_id, "worker-arena", by="tester")
            q.start(m.mission_id, by="tester")
            self.assertTrue(can_retry(q.get(m.mission_id).status))
            q.retry(m.mission_id, by="tester")
            self.assertEqual(q.get(m.mission_id).status, MissionStatus.QUEUED)
            self.assertEqual(q.get(m.mission_id).retry_count, 1)
            # retry from REVIEW as well
            q.assign(m.mission_id, "worker-kilo", by="tester")
            q.start(m.mission_id, by="tester")
            q.review(m.mission_id, by="tester")
            q.retry(m.mission_id, by="tester")
            self.assertEqual(q.get(m.mission_id).retry_count, 2)
            # exceed max_retries
            q.assign(m.mission_id, "worker-arena", by="tester")
            q.start(m.mission_id, by="tester")
            with self.assertRaises(ValueError):
                q.retry(m.mission_id, by="tester")
            # QUEUED not retriable
            m2 = q.create(title="Not retriable", created_by="tester")
            with self.assertRaises(ValueError):
                q.retry(m2.mission_id, by="tester")

    def test_mission_cancellation(self):
        with tempfile.TemporaryDirectory() as tmp:
            qpath = pathlib.Path(tmp) / "mission_queue.json"
            wr = WorkerRegistry(path=pathlib.Path(tmp)/"workers.json")
            wr.ensure_defaults()
            q = MissionQueue(path=qpath, workers=wr)
            q.missions.clear()
            q.next_id = 1
            m = q.create(title="Cancel CREATED", created_by="tester")
            q.cancel(m.mission_id, by="tester")
            self.assertEqual(q.get(m.mission_id).status, MissionStatus.ARCHIVED)
            m2 = q.create(title="Cancel RUNNING", created_by="tester")
            q.queue(m2.mission_id, by="tester")
            q.assign(m2.mission_id, "worker-arena", by="tester")
            q.start(m2.mission_id, by="tester")
            q.cancel(m2.mission_id, by="tester", reason="user abort")
            self.assertEqual(q2_status:=q.get(m2.mission_id).status, MissionStatus.ARCHIVED)
            # already archived cannot cancel
            with self.assertRaises(ValueError):
                q.cancel(m2.mission_id, by="tester")

    def test_mission_timeout(self):
        with tempfile.TemporaryDirectory() as tmp:
            qpath = pathlib.Path(tmp) / "mission_queue.json"
            wr = WorkerRegistry(path=pathlib.Path(tmp)/"workers.json")
            wr.ensure_defaults()
            q = MissionQueue(path=qpath, workers=wr)
            q.missions.clear()
            q.next_id = 1
            m = q.create(title="Timeout Test", created_by="tester", timeout_seconds=1)
            q.queue(m.mission_id, by="tester")
            q.assign(m.mission_id, "worker-arena", by="tester")
            q.start(m.mission_id, by="tester")
            # set updated_at to past
            import datetime
            past = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=5)).isoformat().replace("+00:00","Z")
            m.updated_at = past
            q.save()
            timed = q.check_timeouts()
            self.assertEqual(len(timed), 1)
            self.assertEqual(timed[0].mission_id, m.mission_id)
            self.assertEqual(q.get(m.mission_id).status, MissionStatus.REVIEW)
            self.assertEqual(q.get(m.mission_id).error, "timeout")
            # non-RUNNING not timed out
            m2 = q.create(title="Not running timeout", created_by="tester", timeout_seconds=1)
            m2.status = MissionStatus.QUEUED
            q.missions[m2.mission_id] = m2
            q.save()
            timed2 = q.check_timeouts()
            self.assertNotIn(m2, timed2)

    def test_github_sync(self):
        with tempfile.TemporaryDirectory() as tmp:
            spath = pathlib.Path(tmp) / "github_sync.json"
            gs = GitHubSync(path=spath)
            gs.mapping.clear()
            wr = WorkerRegistry(path=pathlib.Path(tmp)/"workers.json")
            wr.ensure_defaults()
            q = MissionQueue(path=pathlib.Path(tmp)/"mission_queue.json", workers=wr)
            q.missions.clear()
            q.next_id = 1
            m = q.create(title="Sync Test", created_by="tester")
            tid = gs.sync_create(m)
            self.assertTrue(tid.startswith("TASK-9"))
            self.assertEqual(gs.get_task_id(m.mission_id), tid)
            self.assertTrue(spath.is_file())
            # real persistence check
            real_sync = CC / "data" / "github_sync.json"
            if real_sync.is_file():
                data = json.loads(real_sync.read_text())
                self.assertIn("mapping", data)
                # At least one mapping exists from evidence generation
                self.assertTrue(len(data["mapping"]) >= 1)

    def test_dispatcher(self):
        with tempfile.TemporaryDirectory() as tmp:
            qpath = pathlib.Path(tmp) / "mission_queue.json"
            wpath = pathlib.Path(tmp) / "workers.json"
            spath = pathlib.Path(tmp) / "github_sync.json"
            wr = WorkerRegistry(path=wpath)
            wr.ensure_defaults()
            q = MissionQueue(path=qpath, workers=wr)
            gs = GitHubSync(path=spath)
            disp = TelegramCommandDispatcher(queue=q, workers=wr, github_sync=gs)
            # help
            h = disp.dispatch("/mission help", 123)
            self.assertIn("Lifecycle: CREATED", h)
            self.assertIn("/mission create", h)
            # create via dispatcher (auto QUEUED)
            r = disp.dispatch("/mission create Dispatcher Unit Test | module=MOD-TEST priority=P0", 123)
            self.assertIn("CREATED → QUEUED", r)
            self.assertIn("MSQ-0001", r)
            m = q.get("MSQ-0001")
            self.assertIsNotNone(m)
            self.assertEqual(m.status, MissionStatus.QUEUED)
            # show
            show = disp.dispatch("/mission show MSQ-0001", 123)
            self.assertIn("MSQ-0001", show)
            self.assertIn("QUEUED", show)
            # assign/start/review/done/archive via dispatcher
            self.assertIn("ASSIGNED", disp.dispatch("/mission assign MSQ-0001 worker-arena", 123))
            self.assertIn("RUNNING", disp.dispatch("/mission start MSQ-0001", 123))
            self.assertIn("REVIEW", disp.dispatch("/mission review MSQ-0001", 123))
            self.assertIn("DONE", disp.dispatch("/mission done MSQ-0001", 123))
            self.assertIn("ARCHIVED", disp.dispatch("/mission archive MSQ-0001", 123))
            # list
            disp.dispatch("/mission create List Test", 123)
            lst = disp.dispatch("/mission list", 123)
            self.assertIn("MSQ-", lst)
            # queue alias
            q_alias = disp.dispatch("/queue", 123)
            self.assertTrue("MSQ-" in q_alias or "empty" in q_alias.lower())
            # workers
            workers_out = disp.dispatch("/mission workers", 123)
            self.assertIn("worker-arena", workers_out)
            self.assertIn("worker-kilo", workers_out)
            # retry: create -> assign-> start -> retry
            disp.dispatch("/mission create Retry Disp", 123)
            mid = "MSQ-0003"
            disp.dispatch(f"/mission assign {mid} worker-kilo", 123)
            disp.dispatch(f"/mission start {mid}", 123)
            retry_out = disp.dispatch(f"/mission retry {mid}", 123)
            self.assertIn("RETRY → QUEUED", retry_out)
            # cancel
            disp.dispatch("/mission create Cancel Disp", 123)
            mid2 = "MSQ-0004"
            cancel_out = disp.dispatch(f"/mission cancel {mid2}", 123)
            self.assertIn("CANCELLED → ARCHIVED", cancel_out)
            # timeout check (no timeout yet)
            timeout_out = disp.dispatch("/mission timeout", 123)
            self.assertTrue("No timeouts" in timeout_out or "Timeouts" in timeout_out)
            # unknown command returns empty (so Bot would forward to gateway)
            self.assertEqual(disp.dispatch("/status", 123), "")
            self.assertEqual(disp.dispatch("hello world", 123), "")

    def test_queue_run_lifecycle_helper(self):
        with tempfile.TemporaryDirectory() as tmp:
            wr = WorkerRegistry(path=pathlib.Path(tmp)/"workers.json")
            wr.ensure_defaults()
            q = MissionQueue(path=pathlib.Path(tmp)/"mission_queue.json", workers=wr)
            q.missions.clear()
            q.next_id = 1
            m = q.create(title="Helper lifecycle", created_by="tester")
            q.run_lifecycle(m.mission_id)
            self.assertEqual(q.get(m.mission_id).status, MissionStatus.ARCHIVED)
            self.assertEqual(len(q.get(m.mission_id).history), 7)

    def test_bot_wired_dispatcher(self):
        bot_main = read(CC / "Bot" / "src" / "main.py")
        self.assertIn("dispatcher", bot_main.lower(), "Bot must wire dispatcher")
        self.assertIn("TelegramCommandDispatcher", bot_main, "Bot must import TelegramCommandDispatcher")
        self.assertIn("CommandHandler(\"mission\"", bot_main, "Bot must handle /mission")
        self.assertIn("handle_mission", bot_main, "Bot must have handle_mission")
        self.assertIn("/mission", bot_main, "Bot must mention mission commands")
        # Ensure intercept before gateway
        self.assertIn("dispatcher.dispatch", bot_main)
        # Check mission REST endpoints exist for health
        self.assertIn("/mission/list", bot_main)
        self.assertIn("/mission/create", bot_main)
        # Orchestrator import handling
        self.assertIn("Orchestrator", bot_main)

    def test_no_forbidden_and_constraints(self):
        compose = read(ROOT / "docker-compose.yml")
        cc_docs = read(CC / "docs" / "ARCHITECTURE.md")
        for forbidden in ["image: redis", "image: rabbitmq", "image: kafka", "image: postgres"]:
            self.assertNotIn(forbidden, compose.lower(), f"Forbidden {forbidden} must not be in compose")
        # Ensure still 3 healthchecks
        self.assertEqual(compose.count("healthcheck:"), 3)
        # No trading files in ControlCenter
        mqhs = list(CC.rglob("*.mqh"))
        self.assertEqual(len(mqhs), 0, "ControlCenter must not contain .mqh")
        # No AgentOS mutation beyond allowed: ensure TASK_QUEUE still valid (but not mutated by Stage3 mapping file)
        task_queue = ROOT / "AgentOS" / "TASK_QUEUE.md"
        if task_queue.is_file():
            txt = read(task_queue)
            # Stage3 should not append MSQ tasks directly to TASK_QUEUE; sync via github_sync.json
            self.assertNotIn("MSQ-", txt[:5000] if len(txt)>5000 else txt, "TASK_QUEUE should not contain MSQ direct (use mapping file)")

    def test_evidence_files(self):
        # Check file-based persistence exists
        for p in [CC / "data" / "mission_queue.json", CC / "data" / "workers.json", CC / "data" / "github_sync.json"]:
            self.assertTrue(p.is_file(), f"Evidence file missing: {p}")
        # Check 04_Output mirror
        for p in [ROOT / "04_Output" / "ControlCenter" / "mission_queue.json", ROOT / "04_Output" / "ControlCenter" / "workers.json", ROOT / "04_Output" / "ControlCenter" / "github_sync.json", ROOT / "04_Output" / "ControlCenter" / "stage3_evidence.json"]:
            self.assertTrue(p.is_file(), f"Output evidence missing: {p}")
        # Validate stage3_evidence content
        ev_path = ROOT / "04_Output" / "ControlCenter" / "stage3_evidence.json"
        ev = json.loads(ev_path.read_text())
        self.assertEqual(ev["checks"]["Mission Queue"], "PASS")
        self.assertEqual(ev["checks"]["Arena registered"], "PASS")
        self.assertEqual(ev["checks"]["Kilo registered"], "PASS")
        self.assertEqual(ev["checks"]["Mission lifecycle"], "PASS")
        self.assertEqual(ev["checks"]["Mission history"], "PASS")
        self.assertEqual(ev["checks"]["Mission retry"], "PASS")
        self.assertEqual(ev["checks"]["Mission timeout"], "PASS")
        self.assertEqual(ev["checks"]["Mission cancellation"], "PASS")
        self.assertEqual(ev["checks"]["Telegram dispatcher"], "PASS")
        self.assertEqual(ev["checks"]["GitHub Task sync"], "PASS")
        # workers in evidence
        self.assertEqual(len(ev["workers"]), 2)
        self.assertTrue(any(w["worker_id"]=="worker-arena" for w in ev["workers"]))
        self.assertTrue(any(w["worker_id"]=="worker-kilo" for w in ev["workers"]))
        # missions summary
        self.assertTrue(len(ev["missions_summary"]) >= 5)
        m1 = next((m for m in ev["missions_summary"] if m["mission_id"]=="MSQ-0001"), None)
        self.assertIsNotNone(m1)
        self.assertEqual(m1["status"], "ARCHIVED")
        self.assertEqual(m1["history_steps"], 7)
        # lifecycle string
        self.assertIn("CREATED→QUEUED", ev["lifecycle"])
        # docs — check evidence markdown contains mission evidence (table row + PASS)
        md = CC / "docs" / "STAGE3_EVIDENCE.md"
        self.assertTrue(md.is_file())
        md_txt = read(md)
        self.assertIn("Mission Queue", md_txt)
        self.assertIn("Arena Worker registration", md_txt)
        self.assertIn("Kilo Worker registration", md_txt)
        self.assertIn("PASS", md_txt)
        # Orchestrator src files exist
        for fname in ["mission.py","queue.py","worker_registry.py","dispatcher.py","github_sync.py"]:
            self.assertTrue((ORCH_SRC / fname).is_file(), f"Orchestrator src missing {fname}")

if __name__ == "__main__":
    unittest.main()
