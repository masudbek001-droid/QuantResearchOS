# Next Task

Stage 15 + Risk (0016) + Research (0017) + Decision Bus (0018) + AI Council (0019) + Continuous Learning (0020) + AgentOS v1.0 (0021) + Market Digital Twin (0022, TASK-0005 via AgentOS) + **QROS Control Center Stage 1 (0023, MISSION-001)** are **COMPLETE / PASS**.

**Risk PASS** (54 .mqh) + **Research PASS** (55 .mqh) + **Decision Bus PASS** (56 .mqh) + **AI Council PASS** (57 .mqh) + **Continuous Learning PASS** (58 .mqh) + **AgentOS v1.0 PASS** (8-file bus, 11 workers) + **Market Digital Twin PASS** (64 .mqh, 6 MQL Twin, 100 bars FNV-1a 0 mismatches, 5 consumers identical) + **Control Center Stage 1 PASS** (Bot+Gateway+Watcher structure, 17 checks PASS).

**Current Active Task**: **Control Center Stage 1 DONE** — QROS Control Center structure LIVE (docker-compose.yml, .env.example, 3 services Bot+Gateway+Watcher stubs, 7 docs incl. ARCHITECTURE/SECURITY/INSTALL + 3 designs, 17-check structure PASS, no trading/AgentOS mutation). **Next:** Control Center Stage 2 — wire Telegram polling + Gateway OpenAI + Watcher forward + Redis dedup (confirm before write). **Also:** Twin consumer migration — make Replay/Training/Risk/Research/AI *default* to Twin (flag USE_TWIN=true). Both until MT5/secret blockers.

**Next authorized work** (strict priority):
1. **Control Center Stage 2** — wire `Bot/src/handlers` polling + `Gateway/src/openai_client` OpenAI call + `GithubWatcher` forward + Redis `X-GitHub-Delivery` dedup, requires `TELEGRAM_BOT_TOKEN`, `OPENAI_API_KEY`, `GITHUB_TOKEN`, `GITHUB_WEBHOOK_SECRET` + public `WATCHER_PUBLIC_URL` (external secret/webhook blocker if not provided).
2. **Twin consumer migration** — adapt `EAReplay/ReplayController`, `EAResearch`, `EAData/Training` dataset builder, `EAContext Risk/AI` to subscribe to `CMarketDigitalTwin` by default (USE_TWIN flag, Strategy Tester gate).
3. **Production promotion (future)** — wire advisory behind flag, checksum/rollback.
4. On Windows/MT5 host (when available): `python 06_Tools/build.py` → verify 64 .mqh 0/0, then Strategy Tester regression.

AI remains **advisory only** (shadow + 5 advisory layers); no trading decision may consume predictions without ADR + tester gate. Control Center is **project management only** (Telegram→Bot→Gateway→GitHub→AgentOS), no trading.
