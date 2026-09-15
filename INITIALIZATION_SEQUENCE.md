# Initialization Sequence

1. `OnInit` validates inputs and initializes the logger.
2. `CTradeManager.Init` stores settings and initializes core trading services.
3. Feature builder and database manager are initialized before database-backed writers.
4. Market, trade, observation, label, dataset, quality and feature registry services are initialized.
5. Replay, experiment, benchmark, walk-forward and historical platform services are initialized dormant.
6. Dashboard and visual services are initialized before the manager returns success.
7. Shadow AI inference is not initialized by `CTradeManager`; it is validated only
   through isolated scripts and remains outside live decision flow.
8. `OnDeinit` invokes `CTradeManager.Deinit`, which shuts services down in reverse ownership order.

This sequence is compile-verified and validated by the staged terminal/runtime
evidence through Stage 15.
