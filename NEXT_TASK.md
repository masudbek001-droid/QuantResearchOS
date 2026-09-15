# Next Task

Stage 15 + Chief Risk AI (ADR-0016) + Chief Research AI (ADR-0017) are **COMPLETE / PASS**.

**2026-09-15 Chief Risk AI PASS** — CAIRiskAdvisory (54 .mqh) + **Chief Research AI PASS** — CAIResearchAdvisory (55 .mqh), research_synthesis_report.json, RESEARCH_SYNTHESIS_REPORT.md, test_chief_research_ai PASS (OBSERVE_ONLY).

**Current Active Task**: **Chief Research AI DONE** — next priority per strict list is **Decision Bus (11)**. BLOCKED externally for compile verification: Linux sandbox has no MetaEditor to verify 55 .mqh 0/0 (requires Windows MT5 per RESTORE_GUIDE §4).

**Next authorized work** (strict priority):
1. **Decision Bus (Sprint 11)** — requires new ADR-0018 (advisory consensus routing), still advisory only.
2. On Windows/MT5 host (when available): `python 06_Tools/build.py` → verify 55 .mqh 0/0, then Strategy Tester regression.

AI remains **advisory only** (shadow + risk + research); no trading decision may consume predictions without ADR + tester gate.
