# PROJECT PRINCIPLES

Non-negotiable rules of QuantResearchOS. Every human and every AI agent works
under these principles.

## 1. Trading logic is sacred

* The trading core (entry, exit, BreakEven, carry, profit-lock, momentum, risk
  sizing) implements **MIPS v1.0 and is FROZEN**.
* **No SL / no TP** on any trade or pending order — ever. The only regular exit
  is the H1 candle close; BreakEven is optional and **default OFF**.
* Entry logic is final; trade frequency is never reduced; entries are never
  blocked; never more than one extra carry candle.
* Log format, 16-column CSV format and `CBEA_<magic>_` object prefix are contracts
  — extended only, never changed.

## 2. Research never changes runtime

* Observation, labels, datasets, quality, replay, experiments, benchmarks,
  walk-forward and history subsystems are **dormant at init** and run only via
  explicit API calls. A research failure can never affect a trade.
* The DAL failure path never touches trading (init-time open, best-effort writes).

## 3. Everything must be reproducible

* Experiments pin dataset/feature/label/quality/replay versions and are sealed
  on finish; benchmarks are one-shot and deterministic; replay is database-only.
* Datasets are reproducible joins; exports are gated by a mandatory quality pass.
* Imports are audited (ImportHistory: source, timestamps, records, checksum).

## 4. Backward compatibility first

* Schema changes are **additive only**, through the versioned migration chain
  (currently 1→11). No column drops, no renames, no data rewrites.
* New capability is added beside old code (extend, don't replace) until a task
  explicitly migrates it — e.g. the Feature Builder was exposed before replacing
  any live calculation.

## 5. Architecture changes require an ADR

* The architecture is frozen at v1.0; the only lawful change path is a numbered
  ADR (0001…0013 so far) approved in a task/sprint.
* Every sprint respects its STOP CONDITION; "almost done" is not done.

## 6. Engineering hygiene

* Small functions, one responsibility per class/module, descriptive English
  names, comments only for important logic, **no duplicated business logic**.
* PATCH discipline: read the whole file before editing; minimal diffs; never
  rename classes/methods; never rewrite whole files.
* Every change ends with a real compile: **0 errors, 0 warnings** — not one
  warning is acceptable.
* Documentation (README + Uzbek manual PDF) always matches the shipped binary.
