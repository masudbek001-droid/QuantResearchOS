# TECHNICAL DEBT — Task 0002
Report only. **Nothing was removed, renamed or refactored.** Severity: L = low (cosmetic),
M = medium (maintenance cost), H = high (risk). All items verified against call sites.

## 1. Duplicated logic

| ID | Item | Locations | Sev |
|---|---|---|---|
| DUP-01 | CTrade bootstrap triple (`SetExpertMagicNumber` + `SetDeviationInPoints(30)` + `SetTypeFilling(CEAUtils::FillingMode)`) copy-pasted | OrderManager:74-76, PositionManager:48-50, BreakEvenManager:104-106 | M |
| DUP-02 | magic+symbol filter scan loop pattern (`for total … ticket … magic … symbol`) | PositionManager::FindIndex, OrderManager::FindOrder/CountOrders, TradeHistory::CollectDeal/DailyProfit/DealProfitOfPosition (6 loops) | M |
| DUP-03 | Mirror-image swing scanners `LatestSwingLow` / `LatestSwingHigh` (identical structure, opposite comparison) | BreakEvenManager:38-65 / 67-94 | L |
| DUP-04 | Digits lookup `(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS)` repeated inline | 8+ call sites across 5 modules | L |
| DUP-05 | Side-price ternary `(type==BUY ? Bid : Ask)` repeated | BreakEvenManager, ExitEngine, TradeManager (5 sites) | L |
| DUP-06 | History window literals `TimeCurrent()-60*86400 … +60` repeated | TradeHistory:96 and :127 | L |
| DUP-07 | Infinite-loop guard `while(... && guard<10)` repeated | PositionManager:105, OrderManager:163 | L |
| DUP-08 | `EXIT_REASON_COUNT = 7` manually mirrors the enum cardinality; must be edited in lockstep with `ENUM_EXIT_REASON` | EAExitStats:14 vs EASettings enum | M |
| No duplication found in: logging format (single funnel), validation (single `ValidateInputs` + risk gate), normalization (single utils class). |

## 2. Dead code

| ID | Item | Evidence | Sev |
|---|---|---|---|
| DEAD-01 | `CEAUtils::PriceStep` | zero callers | M |
| DEAD-02 | `CEAUtils::VolumeStep` | zero callers | M |
| DEAD-03 | `CEAUtils::NormalizeVolume` | zero callers (`ClampVolume` is the live path) | M |

## 3. Unused includes

| ID | Item | Evidence | Sev |
|---|---|---|---|
| INC-01 | `EARiskManager.mqh` includes `EAUtils.mqh` but never calls `CEAUtils::` | grep count 0 | L |

## 4. Magic numbers / hardcoded values

| ID | Value | Location | Meaning | Sev |
|---|---|---|---|---|
| MAG-01 | `30` | 3× `SetDeviationInPoints(30)` | slippage deviation, should be a named constant or input | M |
| MAG-02 | `10` | guard loops ×2 | max delete/close attempts per cycle | L |
| MAG-03 | `point*0.5` | BreakEvenManager:234 | "no meaningful change" epsilon | L |
| MAG-04 | `+0.5` | EAUtils:70 volume rounding | standard rounding, acceptable | L |
| MAG-05 | `60*86400`, `+60` | TradeHistory ×2 | 60-day lookback / clock-skew slack | L |
| MAG-06 | `2.0`/`3.0` | EAMomentum score mapping | derived from the -200..+100 span; could be computed from the named weights | L |
| Named (not debt): momentum weights, dashboard geometry, `EXIT_SL_TOLERANCE_POINTS`, `EXIT_MIN_EVIDENCE_BARS`, input defaults. |

## 5. Structural observations

| ID | Item | Note | Sev |
|---|---|---|---|
| STR-01 | `CTradeManager` = 642 lines, fan-out 12 | intentional orchestrator (MIPS §2); candidate for future split only via ADR | M |
| STR-02 | Largest functions: `ArmCandle` ~75 ln, `CBreakEvenManager::Update` ~65 ln, `OnTick` ~45 ln | readable, single-purpose; flagged for size only | L |
| STR-03 | Circular dependencies | **none** (DAG verified) | — |
| STR-04 | Hidden coupling: dashboard labels rely on visual prefix cleanup; CSV filename embeds magic+symbol; close classification relies on `LastStop` freshness; `OnTradeTransaction` relies on immediate history visibility | all documented in MIPS/QOS; acceptable until an ADR replaces them | M |
| STR-05 | Unused globals | **none** | — |

## 6. Summary

* 3 dead public helpers (DEAD-01..03) — the only true dead code left.
* 1 unused include (INC-01).
* 8 duplication patterns, mostly boilerplate (DUP-01/02 are the only medium-cost ones).
* 6 magic-literal families; `30` slippage is the most worth naming.
* No circular includes, no unused globals, no duplicated enums beyond the deliberate
  `EXIT_REASON_COUNT` mirror (DUP-08).

All items are candidates for Task 0003+ **only through an ADR**, per the frozen architecture.
