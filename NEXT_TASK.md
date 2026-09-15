# Next Task

Stage 15 + Risk (0016) + Research (0017) + Decision Bus (0018) + AI Council (0019) + Continuous Learning (0020) + AgentOS v1.0 (0021) + Market Digital Twin (0022, TASK-0005 via AgentOS) are **COMPLETE / PASS**.

**Risk PASS** (54 .mqh) + **Research PASS** (55 .mqh) + **Decision Bus PASS** (56 .mqh) + **AI Council PASS** (57 .mqh) + **Continuous Learning PASS** (58 .mqh) + **AgentOS v1.0 PASS** (8-file bus, 11 workers) + **Market Digital Twin PASS** (64 .mqh, 6 MQL Twin, 100 bars FNV-1a 0 mismatches, 5 consumers identical).

**Current Active Task**: **Market Digital Twin DONE** — Single source Twin LIVE (EAMarketDigitalTwin 5 MQL + Adapters, 100 bars exact, 5 consumers Replay/Training/Risk/Research/AI identical via TwinEventBus). **Next:** Twin consumer migration — make Replay/Training/Risk/Research/AI *default* to Twin (flag USE_TWIN=true). **BLOCKED externally** for MT5 compile (64 .mqh 0/0) — Linux sandbox no MetaEditor; GitHub branch protection (403) still.

**Next authorized work** (strict priority):
1. **Twin consumer migration** — adapt `EAReplay/ReplayController`, `EAResearch`, `EAData/Training` dataset builder, `EAContext Risk/AI` to subscribe to `CMarketDigitalTwin` by default (USE_TWIN flag, Strategy Tester gate).
2. **Production promotion (future)** — wire advisory behind flag, checksum/rollback.
3. On Windows/MT5 host (when available): `python 06_Tools/build.py` → verify 64 .mqh 0/0, then Strategy Tester regression.

AI remains **advisory only** (shadow + 5 advisory layers); no trading decision may consume predictions without ADR + tester gate.
