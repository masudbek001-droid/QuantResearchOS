"""
QROS Mission Queue — shim for legacy import path.

This file exists for backward compatibility (import queue vs mission_queue shadowing).
All logic is in mission_queue.py — this shim re-exports it to avoid duplicate code.
It also ensures stdlib 'queue' is not shadowed for concurrent.futures.
"""
# Restore stdlib queue if this file was imported as 'queue'
import sys
if 'queue' in sys.modules and getattr(sys.modules['queue'], '__file__', '') and 'Orchestrator' in str(getattr(sys.modules['queue'], '__file__', '')):
    # This file is shadowing stdlib, restore stdlib
    try:
        import importlib.util as _ilu
        import sysconfig as _sysconfig
        import pathlib as _pl
        _stdlib_path = _pl.Path(_sysconfig.get_path('stdlib')) / "queue.py"
        if _stdlib_path.is_file():
            _spec = _ilu.spec_from_file_location("queue", _stdlib_path)
            _mod = _ilu.module_from_spec(_spec)
            sys.modules["queue"] = _mod
            _spec.loader.exec_module(_mod)
    except Exception:
        pass

try:
    from .mission_queue import MissionQueue, DATA_PATH, OUTPUT_PATH
except ImportError:
    try:
        from mission_queue import MissionQueue, DATA_PATH, OUTPUT_PATH  # type: ignore
    except ImportError:
        # Fallback: load via importlib
        import pathlib as _pl2
        import importlib.util as _ilu2
        _p = _pl2.Path(__file__).parent / "mission_queue.py"
        _spec2 = _ilu2.spec_from_file_location("_mission_queue", _p)
        _mod2 = _ilu2.module_from_spec(_spec2)
        _spec2.loader.exec_module(_mod2)
        MissionQueue = _mod2.MissionQueue
        DATA_PATH = _mod2.DATA_PATH
        OUTPUT_PATH = _mod2.OUTPUT_PATH
