#!/bin/zsh
# Starts the local server and opens the page in the default browser. Ctrl+C to stop.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ -x .venv/bin/python ]] || { echo "먼저 scripts/setup-mac.sh를 실행하세요."; exit 1; }
PORT=$(grep -E '^GQAI_PORT=' config.env 2>/dev/null | cut -d= -f2)
PORT="${GQAI_PORT:-${PORT:-7860}}"
( sleep 2; open "http://127.0.0.1:$PORT/" ) &
exec .venv/bin/python server/server.py
