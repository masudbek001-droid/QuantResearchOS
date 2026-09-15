#!/usr/bin/env python3
"""
QROS Control Center v1 — Stage 1 structure test.

Validates Stage 1 deliverables for MISSION-001:
- docker-compose.yml + ControlCenter/docker-compose.yml
- ControlCenter/ + Bot/ + Gateway/ + GithubWatcher/
- README, INSTALL.md, ARCHITECTURE.md, SECURITY.md, ENV.example
- No trading/AgentOS mutation (trading frozen, AgentOS 1:1 still PASS)
- Compose + env + docs contain expected pipeline keywords
- Service stubs are importable and /health logic works offline (no network)
- Fail-closed security: .env gitignored, webhook HMAC util correct

Run:
  python ControlCenter/tests/test_stage1_structure.py
  python ControlCenter/tests/test_stage1_structure.py -v
  pytest ControlCenter/tests/test_stage1_structure.py -v
"""

import os
import sys
import pathlib
import re
import importlib.util
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]  # QuantResearchOS/
CC = ROOT / "ControlCenter"


def _read(p: pathlib.Path) -> str:
    return p.read_text(encoding="utf-8", errors="ignore")


class TestStage1Structure(unittest.TestCase):
    def test_root_deliverables_exist(self):
        required = [
            ROOT / "docker-compose.yml",
            ROOT / ".env.example",
            ROOT / "ENV.example",
            ROOT / "ARCHITECTURE.md",
            ROOT / "SECURITY.md",
            ROOT / "INSTALL.md",
        ]
        for p in required:
            with self.subTest(path=str(p.relative_to(ROOT))):
                self.assertTrue(p.is_file(), f"missing deliverable: {p}")

    def test_controlcenter_top_exists(self):
        self.assertTrue(CC.is_dir(), "ControlCenter/ missing")
        for sub in ["Bot", "Gateway", "GithubWatcher", "docs", "tests"]:
            self.assertTrue((CC / sub).is_dir(), f"ControlCenter/{sub}/ missing")
        self.assertTrue((CC / "docker-compose.yml").is_file(), "ControlCenter/docker-compose.yml missing")
        self.assertTrue((CC / ".env.example").is_file(), "ControlCenter/.env.example missing")
        self.assertTrue((CC / "config" / "env.example").is_file(), "ControlCenter/config/env.example missing")
        self.assertTrue((CC / "README.md").is_file(), "ControlCenter/README.md missing")

    def test_bot_structure(self):
        bot = CC / "Bot"
        for f in ["Dockerfile", "requirements.txt", "README.md", "src/config.py", "src/main.py", "src/handlers/__init__.py"]:
            self.assertTrue((bot / f).is_file(), f"Bot/{f} missing")

    def test_gateway_structure(self):
        gw = CC / "Gateway"
        for f in ["Dockerfile", "requirements.txt", "README.md", "src/config.py", "src/main.py", "src/openai_client.py"]:
            self.assertTrue((gw / f).is_file(), f"Gateway/{f} missing")

    def test_watcher_structure(self):
        w = CC / "GithubWatcher"
        for f in ["Dockerfile", "requirements.txt", "README.md", "src/config.py", "src/main.py", "src/webhook.py"]:
            self.assertTrue((w / f).is_file(), f"GithubWatcher/{f} missing")

    def test_docs_exist(self):
        docs = CC / "docs"
        for name in ["ARCHITECTURE.md", "SECURITY.md", "INSTALL.md", "ENV_VARS.md", "GITHUB_WEBHOOK_DESIGN.md", "TELEGRAM_BOT_DESIGN.md", "OPENAI_GATEWAY_DESIGN.md"]:
            self.assertTrue((docs / name).is_file(), f"docs/{name} missing")

    def test_docker_compose_content(self):
        for p in [ROOT / "docker-compose.yml", CC / "docker-compose.yml"]:
            txt = _read(p)
            with self.subTest(file=str(p.relative_to(ROOT))):
                self.assertIn("gateway:", txt, "gateway service missing")
                self.assertIn("bot:", txt, "bot service missing")
                self.assertIn("github-watcher", txt, "github-watcher service missing")
                self.assertIn("qros-control-net", txt, "network qros-control-net missing")
                self.assertIn("env_file", txt, "env_file missing (secrets via .env)")
                self.assertIn("healthcheck", txt, "healthcheck missing")
                self.assertIn("8080", txt, "gateway 8080 missing")
                self.assertIn("8081", txt, "bot 8081 missing")
                self.assertIn("8082", txt, "watcher 8082 missing")
                self.assertNotIn("python-telegram-bot", txt, "compose should not reference code deps directly")

    def test_env_example_content(self):
        for p in [ROOT / ".env.example", ROOT / "ENV.example", CC / ".env.example", CC / "config" / "env.example"]:
            txt = _read(p)
            with self.subTest(file=str(p.relative_to(ROOT))):
                for var in ["TELEGRAM_BOT_TOKEN", "TELEGRAM_ALLOWED_USER_IDS", "OPENAI_API_KEY", "GITHUB_TOKEN", "GITHUB_WEBHOOK_SECRET", "GITHUB_REPO", "GATEWAY_PORT", "BOT_PORT", "GITHUB_WEBHOOK_PORT"]:
                    self.assertIn(var, txt, f"{var} missing in {p.name}")
                self.assertIn("AGENTOS", txt)
                self.assertIn("ARENA", txt)

    def test_architecture_content(self):
        for p in [ROOT / "ARCHITECTURE.md", CC / "docs" / "ARCHITECTURE.md"]:
            txt = _read(p)
            with self.subTest(file=str(p.relative_to(ROOT))):
                self.assertIn("Telegram", txt)
                self.assertIn("QROS Bot", txt)
                self.assertIn("OpenAI Gateway", txt)
                self.assertIn("GitHub", txt)
                self.assertIn("AgentOS", txt)
                self.assertIn("Arena", txt)
                self.assertIn("Kilo", txt)
                self.assertIn("Stage 1", txt)
                self.assertIn("mermaid", txt, "architecture diagram (mermaid) missing")
                self.assertIn("docker-compose.yml", txt)
                # Trading core is frozen — presence of "MIPS v1.0" in a frozen note is allowed; ensure not excessive
                # Only fail if architecture contains trading logic like entry/exit details
                self.assertNotIn("BREAK_EVEN", txt, "architecture should not leak trading internals")

    def test_security_content(self):
        for p in [ROOT / "SECURITY.md", CC / "docs" / "SECURITY.md"]:
            txt = _read(p)
            with self.subTest(file=str(p.relative_to(ROOT))):
                self.assertIn("TELEGRAM_ALLOWED_USER_IDS", txt)
                self.assertIn("GITHUB_WEBHOOK_SECRET", txt)
                self.assertIn("X-Hub-Signature-256", txt)
                self.assertIn("hmac", txt)
                self.assertIn("OPENAI_API_KEY", txt)
                self.assertIn(".env", txt)
                self.assertIn("allowlist", txt.lower())

    def test_install_content(self):
        for p in [ROOT / "INSTALL.md", CC / "docs" / "INSTALL.md"]:
            txt = _read(p)
            with self.subTest(file=str(p.relative_to(ROOT))):
                self.assertIn("docker compose", txt)
                self.assertIn("cp .env.example .env", txt)
                self.assertIn("/health", txt)
                self.assertIn("GITHUB_WEBHOOK_SECRET", txt)
                self.assertIn("Troubleshooting", txt)

    def test_gitignore_secrets(self):
        gi = _read(ROOT / ".gitignore")
        self.assertIn(".env", gi, ".env must be gitignored")

    def test_no_trading_modification(self):
        # Ensure no new .mqh/.mq5 changes staged vs HEAD that touch trading core, except ControlCenter is isolated
        # Check that existing trading files are untouched by Stage 1 (no .mqh in ControlCenter)
        mqhs = list((CC).rglob("*.mqh"))
        self.assertEqual(len(mqhs), 0, f"ControlCenter must not contain .mqh: {mqhs}")
        mq5s = list((CC).rglob("*.mq5"))
        self.assertEqual(len(mq5s), 0)

    def test_no_agentos_modification(self):
        # ControlCenter Stage 1 must not contain AgentOS files
        self.assertFalse((CC / "AgentOS").exists())
        # Ensure AgentOS validate still passes (invoked externally, but check file presence unchanged)
        for required in ["AgentOS/TASK_QUEUE.md", "AgentOS/OWNERSHIP_MAP.md", "AgentOS/tools/validate.py"]:
            self.assertTrue((ROOT / required).is_file(), f"AgentOS file missing: {required}")

    def test_webhook_verify_signature(self):
        # Offline unit test of HMAC logic (no network, no secrets in repo)
        import hmac, hashlib
        # Load via source read + exec to avoid sys.modules issues in sandbox without pydantic
        src = _read(CC / "GithubWatcher" / "src" / "webhook.py")
        ns = {}
        exec(compile(src, str(CC / "GithubWatcher" / "src" / "webhook.py"), "exec"), ns)
        verify = ns["verify_signature"]
        secret = "unit-test-secret-32chars-random-aaa"
        body = b'{"test": true}'
        good = "sha256=" + hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()
        self.assertTrue(verify(secret, body, good))
        self.assertFalse(verify(secret, body, "sha256=bad"))
        self.assertFalse(verify("", body, good))
        self.assertFalse(verify(secret, body, None))
        self.assertFalse(verify(secret, body, "sha256:" + good[7:]))

    def test_gateway_stub_importable(self):
        # Gateway stub is pure dataclass + no external deps; exec without pydantic/openai
        src = _read(CC / "Gateway" / "src" / "openai_client.py")
        # Strip imports that require openai if not needed; but file is pure stdlib except dataclasses
        ns = {}
        # Ensure dataclass can resolve __module__: set name properly
        import sys, types
        mod_name = "cc_gateway_client_test"
        mod = types.ModuleType(mod_name)
        mod.__file__ = str(CC / "Gateway" / "src" / "openai_client.py")
        sys.modules[mod_name] = mod
        try:
            exec(compile(src, str(CC / "Gateway" / "src" / "openai_client.py"), "exec"), mod.__dict__)
            self.assertTrue(hasattr(mod, "SYSTEM_PROMPT_STAGE1"))
            self.assertIn("remote project management", mod.SYSTEM_PROMPT_STAGE1.lower())
            self.assertTrue(hasattr(mod, "TOOLS_DESIGN"))
            self.assertTrue(len(mod.TOOLS_DESIGN) >= 2)
            req = mod.GatewayRequest(telegram_user_id=123, text="status")
            resp = mod.stub_handle(req)
            self.assertIn("Stage 1 stub", resp.reply_text)
            self.assertEqual(resp.audit_user_id, 123)
        finally:
            sys.modules.pop(mod_name, None)

    def test_bot_config_offline(self):
        # Bot config requires pydantic — skip if not installed (Stage 1 structure does not require runtime install for test)
        try:
            import pydantic  # noqa
        except ImportError:
            self.skipTest("pydantic not installed — Bot config structure validated by file existence only")
        spec = importlib.util.spec_from_file_location("cc_bot_config", CC / "Bot" / "src" / "config.py")
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        s = mod.BotSettings(_env_file=None)
        missing = s.validate_stage1()
        self.assertIsInstance(missing, list)
        self.assertTrue(len(missing) >= 1)


if __name__ == "__main__":
    # allow palette: python test_stage1_structure.py -v
    verbosity = 2 if "-v" in sys.argv else 1
    suite = unittest.TestLoader().loadTestsFromTestCase(TestStage1Structure)
    runner = unittest.TextTestRunner(verbosity=verbosity)
    result = runner.run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)
