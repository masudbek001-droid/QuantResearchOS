# Next Task

Stage 15 + Chief Risk AI (ADR-0016) + Chief Research AI (ADR-0017) + Decision Bus (ADR-0018) are **COMPLETE / PASS**.

**Chief Risk AI PASS** (54 .mqh) + **Chief Research AI PASS** (55 .mqh) + **Decision Bus PASS** (56 .mqh, decision_bus_report.json, DECISION_BUS_REPORT.md, test_decision_bus PASS).

**Current Active Task**: **Decision Bus DONE** — next priority per strict list is **AI Council (12)**. BLOCKED externally for compile verification: Linux sandbox has no MetaEditor to verify 56 .mqh 0/0 (requires Windows MT5 per RESTORE_GUIDE §4).

**Next authorized work** (strict priority):
1. **AI Council (Sprint 12)** — requires new ADR-0019 (multi-agent advisory), still advisory only.
2. On Windows/MT5 host (when available): `python 06_Tools/build.py` → verify 56 .mqh 0/0, then Strategy Tester regression.

AI remains **advisory only** (shadow + risk + research + bus); no trading decision may consume predictions without ADR + tester gate.
