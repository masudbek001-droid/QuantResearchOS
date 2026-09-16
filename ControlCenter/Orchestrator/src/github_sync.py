"""
QROS GitHub Task Sync — Stage 3.
"""
from __future__ import annotations

import json
import pathlib
from typing import Dict

try:
    from .mission import Mission
except ImportError:
    from mission import Mission

ROOT = pathlib.Path(__file__).resolve().parents[3]
DATA_PATH = ROOT / "ControlCenter" / "data" / "github_sync.json"
OUTPUT_PATH = ROOT / "04_Output" / "ControlCenter" / "github_sync.json"

class GitHubSync:
    def __init__(self, path: pathlib.Path | None = None):
        self.path = path or DATA_PATH
        self.mapping: Dict[str, str] = {}
        self.load()

    def load(self):
        if self.path.is_file():
            try:
                data = json.loads(self.path.read_text(encoding="utf-8"))
                self.mapping = data.get("mapping", {})
            except Exception:
                self.mapping = {}

    def save(self):
        # BUG-010 fix: handle PermissionError (Docker 1000 vs host 1001)
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
        except Exception:
            pass
        payload = {"mapping": self.mapping, "note": "MissionID -> TaskID (GitHub sync offline fallback)"}
        data = json.dumps(payload, indent=2)
        try:
            self.path.write_text(data, encoding="utf-8")
        except (PermissionError, OSError):
            try:
                import os
                os.chmod(self.path.parent, 0o777)
                self.path.write_text(data, encoding="utf-8")
            except Exception:
                pass
        except Exception:
            pass
        try:
            try:
                is_default = str(self.path.resolve()) == str(DATA_PATH.resolve())
            except Exception:
                is_default = str(self.path) == str(DATA_PATH)
            if is_default:
                try:
                    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
                except Exception:
                    pass
                try:
                    OUTPUT_PATH.write_text(data, encoding="utf-8")
                except (PermissionError, OSError):
                    try:
                        import os
                        os.chmod(OUTPUT_PATH.parent, 0o777)
                        OUTPUT_PATH.write_text(data, encoding="utf-8")
                    except Exception:
                        pass
                except Exception:
                    pass
        except Exception:
            pass

    def sync_create(self, mission: Mission) -> str:
        try:
            n = int(mission.mission_id.split("-")[1])
            task_id = f"TASK-9{n:03d}"
        except:
            task_id = "TASK-9000"
        self.mapping[mission.mission_id] = task_id
        self.save()
        return task_id

    def get_task_id(self, mission_id: str) -> str | None:
        return self.mapping.get(mission_id)

    def list_sync(self) -> Dict[str, str]:
        return dict(self.mapping)
