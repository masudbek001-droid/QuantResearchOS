# Memory and Resource Audit

Static ownership review found module objects owned by `CTradeManager` and
database ownership centralized in `CDatabaseManager`/`SQLiteProvider`. Compile
diagnostics are clean.

Runtime leak evidence from the early Stage 2 database-open failure was addressed
by repairing database open/schema handling; later validation runs through Stage
14 completed without reported leaked dynamic objects in the supplied terminal
evidence.

ONNX handle ownership:

- `QuantResearchOS_OnnxValidation` explicitly releases handles.
- `QuantResearchOS_ReplayOnnxValidation` explicitly releases handles.
- `CAIShadowInference.Release()` releases the owned ONNX handle and is validated
  by the Stage 13/14 flow.

Remaining rule: any future live EA integration must release ONNX handles on
deinitialization and preserve AI-disabled rollback.
