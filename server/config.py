"""Settings from environment variables, with `config.env` in the project root as defaults.

Every value can be overridden by a real environment variable. See config.example.env.
"""
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def _load_env_file(path: Path) -> None:
    """Reads KEY=VALUE lines (no shell expansion). Real environment variables win."""
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.removeprefix("export ").split("=", 1)
        key, value = key.strip(), value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


_load_env_file(ROOT / "config.env")


def _path(name: str, default: Path) -> Path:
    value = os.environ.get(name, "").strip()
    p = Path(value).expanduser() if value else default
    return p if p.is_absolute() else ROOT / p


def _default_log_dir() -> Path:
    if sys.platform == "darwin":
        return Path.home() / "Library/Logs/GQAILive"
    return ROOT / "data/logs"


PORT = int(os.environ.get("GQAI_PORT", "7860"))
DATA_DIR = _path("GQAI_DATA_DIR", ROOT / "data")
LOG_DIR = _path("GQAI_LOG_DIR", _default_log_dir())

_exe = ".exe" if os.name == "nt" else ""
WHISPER_BIN_DIR = _path("GQAI_WHISPER_BIN_DIR", ROOT / "vendor/whisper.cpp/build/bin")
WHISPER_SERVER = WHISPER_BIN_DIR / f"whisper-server{_exe}"
WHISPER_MODEL = _path("GQAI_WHISPER_MODEL", ROOT / "models/ggml-large-v3.bin")
WHISPER_SERVER_PORT = int(os.environ.get("GQAI_WHISPER_PORT", "8178"))

CLAUDE_MODEL = os.environ.get("GQAI_CLAUDE_MODEL", "claude-sonnet-5-5")
CLAUDE_EFFORT = os.environ.get("GQAI_CLAUDE_EFFORT", "low")
COMMAND_EFFORT = os.environ.get("GQAI_COMMAND_EFFORT", "medium")  # instruction mode thinks more

DATA_DIR.mkdir(parents=True, exist_ok=True)
