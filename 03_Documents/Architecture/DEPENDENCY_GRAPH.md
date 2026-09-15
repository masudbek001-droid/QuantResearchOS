# DEPENDENCY GRAPH — Task 0002
Audit-only document. Includes were extracted by scanning `#include` lines; runtime edges were
verified against actual call sites. **Nothing was modified.**

## 1. Include DAG (compile-time)

```
CandleBreakoutEA.mq5
├── EASettings
├── EALogger ──────────────┐
└── EATradeManager         │
    ├── EAUtils ──┐        │
    ├── EALogger ─┤        │
    ├── EATradeHistory     │
    │   └── EAUtils        │
    ├── EARiskManager      │
    │   ├── EAUtils  (UNUSED — see TECHNICAL_DEBT D-02)
    │   ├── EALogger       │
    │   └── EATradeHistory │
    ├── EAOrderManager     │
    │   ├── <Trade\Trade.mqh>
    │   ├── EAUtils        │
    │   └── EALogger       │
    ├── EAPositionManager  │
    │   ├── <Trade\Trade.mqh>
    │   ├── EAUtils        │
    │   └── EALogger       │
    ├── EABreakEvenManager │
    │   ├── <Trade\Trade.mqh>
    │   ├── EAUtils        │
    │   └── EALogger       │
    ├── EAExitEngine       │
    │   ├── EASettings     │
    │   ├── EAUtils        │
    │   ├── EALogger       │
    │   └── EAMomentum     │
    │       ├── EASettings │
    │       └── EAUtils    │
    ├── EATradeContext     │
    │   └── EASettings     │
    ├── EAExitStats        │
    │   ├── EASettings     │
    │   ├── EALogger       │
    │   └── EAExitEngine   │
    ├── EADashboard        │
    │   ├── EASettings     │
    │   ├── EATradeContext │
    │   └── EAExitStats    │
    └── EAVisualManager    │
        ├── EAUtils        │
        └── EALogger ──────┘
```

* **Acyclic** — `EASettings` is the only universal leaf; no header includes a peer that includes
  it back. Include guards (`__EA_*_MQH__`) present in all 15 headers.
* External dependency: `<Trade\Trade.mqh>` (stock) used by Order/Position/BreakEven managers.

## 2. Per-module runtime dependencies

| Module | Reads | Writes / side effects |
|---|---|---|
| main .mq5 | inputs, `g_trade_manager` | `Print` (validation), logger init |
| CTradeManager | settings, all managers, `iTime/iHigh/iLow` | order/position actions via managers, log, dashboard, stats |
| COrderManager | `OrdersTotal/OrderGet*`, utils | `CTrade.BuyStop/SellStop/OrderDelete` |
| CPositionManager | `PositionsTotal/PositionGet*` | `CTrade.PositionClose` |
| CBreakEvenManager | `iTime/iLow/iHigh/Bars`, utils | `CTrade.PositionModify` (only SL writer) |
| CRiskManager | history, `TimeCurrent/TimeToStruct` | log only |
| CTradeHistory | `HistorySelect/HistoryDealGet*` | none (pure reads) |
| CExitEngine | `iTime`, series via CMomentumAnalyzer, utils | log only |
| CMomentumAnalyzer | `iOpen/iHigh/iLow/iClose` (M5) | internal cache |
| CExitStats | settings | `FileOpen/Write/Flush/Seek/Close` (CSV) |
| CDashboard | `STradeContext`, stats | `ObjectCreate/Set*/Delete`, `ChartRedraw` |
| CVisualManager | settings | `ObjectCreate/Set*`, prefix-based `ObjectDelete` |
| CLogger | `TimeCurrent` | `Print` |
| CEAUtils | `SymbolInfo*` | none |

## 3. Global variables / functions / objects

* **EA globals:** `g_logger`, `g_trade_manager` (main only). No header declares mutable globals.
* **Project global functions:** `ExitReasonToString`, `LotModeToString`, `HoursMaskToString`
  (EASettings); `CEAUtils::*` (17 statics). Used-by matrix in RUNTIME_INVENTORY §1.1 sources.
* **MQL built-ins touched:** series (`iTime/iOpen/iHigh/iLow/iClose/Bars`), market
  (`SymbolInfo*/PositionGet*/OrderGet*`), history (`History*`), files (`File*`), objects
  (`Object*/ChartRedraw`), time (`TimeCurrent/TimeToString/TimeToStruct/PeriodSeconds`),
  `Print`, `Math*`, `String*`.
* **Chart objects created:** Visual — `OBJ_HLINE` PrevHigh/PrevLow/BE, `OBJ_TREND` ×2 pending,
  `OBJ_ARROW` entry/exit (5 create sites); Dashboard — `OBJ_LABEL` × up to 13 (1 create site).
* **Objects referenced cross-module:** Dashboard labels are deleted by
  `CVisualManager::Cleanup` through the shared `CBEA_<magic>_` prefix (documented contract,
  see MIPS §3).

## 4. Coupling hotspots (report only)

1. `CTradeManager` depends on all 12 modules — intended orchestrator role; the only class with
   fan-out > 4.
2. Dashboard ↔ Visual cleanup via name-prefix convention (hidden coupling, documented).
3. `CTradeManager` broker-close classification depends on `CExitEngine::LastStop` freshness
   (requires at least one tick while the position is open).
4. `OnTradeTransaction` depends on `HistoryDealSelect` succeeding immediately after the broker
   event (platform timing assumption).
