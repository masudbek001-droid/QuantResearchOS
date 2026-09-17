# Next Task

Stage 15 + Risk (0016) + Research (0017) + Decision Bus (0018) + AI Council (0019) + Continuous Learning (0020) + AgentOS v1.0 (0021) + Market Digital Twin (0022, TASK-0005 via AgentOS) + **QROS Control Center Stage 1 (0023, MISSION-001)** + **Stage 2 wired (0024, MISSION-003)** are **COMPLETE / PASS**.

**Risk PASS** (54 .mqh) + **Research PASS** (55 .mqh) + **Decision Bus PASS** (56 .mqh) + **AI Council PASS** (57 .mqh) + **Continuous Learning PASS** (58 .mqh) + **AgentOS v1.0 PASS** (8-file bus, 11 workers) + **Market Digital Twin PASS** (64 .mqh, 6 MQL Twin, 100 bars FNV-1a 0 mismatches, 5 consumers identical) + **Control Center Stage 1 PASS** (Bot+Gateway+Watcher structure, 17 checks PASS) + **Control Center Stage 2 PASS** (polling + OpenAI + webhook + parser + forwarding + health + logs + graceful, 13 checks PASS).

**Current Active Task**: **Control Center Stage 2 DONE** — wired pipeline ONLINE (health PASS stage 2-wired, logs JSON, docker healthchecks, webhook HMAC parser, AgentOS forwarding via Gateway→Bot). **Next:** LIVE — provide real secrets (`TELEGRAM_BOT_TOKEN`, `OPENAI_API_KEY`, `GITHUB_TOKEN`, `GITHUB_WEBHOOK_SECRET`, `WATCHER_PUBLIC_URL`) → `docker compose up -d --build` → `curl /health` 200, `curl /ready` true, Telegram `connected:true`, OpenAI `connected:true`, GitHub webhook 200. **Also:** Twin consumer migration — make Replay/Training/Risk/Research/AI *default* to Twin (flag USE_TWIN=true).

**Next authorized work** (strict priority):
1. **LIVE secrets wiring verification** — fill `.env` with real tokens, expose Watcher via tunnel/proxy, register GitHub webhook `https://<public>/github/webhook`, run `docker compose up -d`, verify `/health` 200 stage 2-wired, `/ready` true, send Telegram `/status` → Gateway → returns `PROJECT_STATUS.md`, push to `arena/01a0a3b5-quantresearchos` → Watcher 200 → Gateway → Bot notify.
2. **Twin consumer migration** — adapt `EAReplay/ReplayController`, `EAResearch`, `EAData/Training` dataset builder, `EAContext Risk/AI` to subscribe to `CMarketDigitalTwin` by default (USE_TWIN flag, Strategy Tester gate).
3. **Production promotion (future)** — wire advisory behind flag, checksum/rollback.
4. On Windows/MT5 host (when available): `python 06_Tools/build.py` → verify 64 .mqh 0/0, then Strategy Tester regression.

AI remains **advisory only** (shadow + 5 advisory layers); no trading decision may consume predictions without ADR + tester gate. Control Center is **project management only** (Telegram→Bot→Gateway→GitHub→AgentOS), no trading, no Redis/Dashboard.

**External blockers:** MT5 compile (64 .mqh Linux sandbox no MetaEditor), GitHub branch protection (403 admin), plus live secrets/webhook public URL for Stage 2 LIVE verification.
