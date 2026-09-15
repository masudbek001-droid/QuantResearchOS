# AGENT GUIDE — instructions for every future AI agent

You are continuing a long-running, disciplined engineering project. Read this
before touching anything.

## How to start work

1. Read `README.md` → `PROJECT_STATUS.md` → `NEXT_TASK.md`.
2. Read `PROJECT_PRINCIPLES.md` (binding) and `ARCHITECTURE_MAP.md`.
3. Read the ADRs relevant to your task (`03_Documents/ADR/`) — the latest ADR
   states what the most recent sprint froze and forbade.
4. Read the spec of the module you will touch (`03_Documents/Specifications/`)
   and the last sprint report (`03_Documents/SprintReports/`).
5. **Wait for the user's explicit task/sprint command.** Do not start Sprint 6B
   or any feature work on your own initiative.

## Which files must be read first (in order)

1. `QuantResearchOS/PROJECT_STATUS.md`
2. `QuantResearchOS/NEXT_TASK.md`
3. `QuantResearchOS/PROJECT_PRINCIPLES.md`
4. `QuantResearchOS/ARCHITECTURE_MAP.md`
5. `QuantResearchOS/03_Documents/ADR/ADR-0013_historical_data_platform.md`
   (latest frozen state)
6. The specification document for the module under work.

## What must NEVER be modified

* **Trading behaviour:** entry logic, H1-close exit, BreakEven, carry,
  profit-lock, momentum, risk sizing — MIPS v1.0 is frozen.
* **No SL / no TP** anywhere, ever. BreakEven default OFF.
* Log format `[CBEA <magic> <symbol>] [TAG]`, 16-column CSV, `CBEA_<magic>_`
  object prefix, `ENUM_EXIT_REASON` values — extend only, never change.
* Schema migrations already in the chain (1→11) — never edit, only append v12+.
* Class/method names of working modules; whole-file rewrites; business logic
  duplication.
* Sealed research rows (finished experiments, one-shot benchmarks).

## How to work

* PATCH discipline: read the entire file before editing; minimal diffs.
* Extend instead of replace; keep backward compatibility.
* One responsibility per module; small functions; English names; comment only
  important logic.
* Every architectural/schema change → new ADR.
* End every change with a real compile: `python3 06_Tools/build.py` under the
  Wine environment (see `RESTORE_GUIDE.md` §Build environment) — **0 errors,
  0 warnings**, then copy the binary to `04_Output/EX5/`.
* Sync documentation (manual PDF + relevant docs) with any behaviour change.
* Respect every STOP CONDITION literally. "Almost done" is not done.

## Where things live

| Need | Path |
|---|---|
| Compile the EA | `06_Tools/build.py` (needs Wine + MT5; see RESTORE_GUIDE) |
| Sources | `01_Source/EA/MQL5/` |
| Database contracts | `02_Databases/` (runtime files under MT5 `Files\CBEA\`) |
| ADRs / specs / reports | `03_Documents/` |
| Shipped binary | `04_Output/EX5/CandleBreakoutEA.ex5` |
| Uzbek user manual | `03_Documents/Manuals/CandleBreakoutEA_Qollanma.pdf` (+ `06_Tools/build_manual.py`) |
