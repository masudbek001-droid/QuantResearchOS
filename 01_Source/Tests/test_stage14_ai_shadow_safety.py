"""
Stage 14 — AI shadow safety audit.

This test is intentionally source-level and conservative: the shadow adapter may
load ONNX and write CAIContext prediction fields only. It must not depend on or
call trading managers, risk gates, orders, positions, or exits.
"""
from pathlib import Path
import re


ROOT = Path(r"C:\QuantResearchOS")
AI_CONTEXT = ROOT / "01_Source/EA/MQL5/Include/CandleBreakoutEA/EAContext/EAContextAI.mqh"
AI_SHADOW = ROOT / "01_Source/EA/MQL5/Include/CandleBreakoutEA/EAContext/EAContextAIShadowInference.mqh"
TRADE_MANAGER = ROOT / "01_Source/EA/MQL5/Include/CandleBreakoutEA/EATradeManager.mqh"


FORBIDDEN_IN_SHADOW = [
    "CTradeManager",
    "COrderManager",
    "CPositionManager",
    "CRiskManager",
    "CExitEngine",
    "OrderSend",
    "OrderDelete",
    "PositionClose",
    "BuyStop",
    "SellStop",
    "Close(",
    "Check(",
]


def read(path: Path) -> str:
    if not path.exists():
        raise AssertionError(f"missing file: {path}")
    return path.read_text(encoding="utf-8", errors="ignore")


def main() -> None:
    ai = read(AI_CONTEXT)
    shadow = read(AI_SHADOW)
    trade_manager = read(TRADE_MANAGER)

    assert "SetPrediction" in ai, "CAIContext must expose explicit prediction writer"
    assert "PredictionAvailable" in ai, "CAIContext must keep availability flag"
    assert "ProbabilityFakeBreakout" in ai, "CAIContext must expose full 4-class probability vector"
    assert "OnnxCreate" in shadow and "OnnxRun" in shadow and "OnnxRelease" in shadow, "shadow adapter must manage ONNX lifecycle"

    violations = []
    for token in FORBIDDEN_IN_SHADOW:
        if token in shadow:
            violations.append(token)
    assert not violations, f"shadow adapter contains forbidden trading tokens: {violations}"

    assert "EAContextAIShadowInference.mqh" not in trade_manager, "TradeManager must not consume shadow AI yet"
    assert not re.search(r"\bPredict\s*\(", trade_manager), "TradeManager must not call AI Predict"
    assert "ai.Update()" in read(ROOT / "01_Source/EA/MQL5/Include/CandleBreakoutEA/EAContext/EAContextLayer.mqh"), "ContextLayer update path remains inert"

    print("[QROS_STAGE14] STATUS=PASS | shadow_adapter=OBSERVE_ONLY | trade_manager_ai_calls=0 | forbidden_tokens=0")


if __name__ == "__main__":
    main()
