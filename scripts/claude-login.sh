#!/bin/zsh
# Opens the Claude Code CLI bundled with the Agent SDK so you can log in with your Claude account.
# Type /login, finish in the browser, then /exit. Not needed if you already use Claude Code or set ANTHROPIC_API_KEY.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI=$("$ROOT/.venv/bin/python" -c 'import claude_agent_sdk, pathlib; print(pathlib.Path(claude_agent_sdk.__file__).parent / "_bundled" / "claude")')
[[ -x "$CLI" ]] || CLI=$(command -v claude || true)
[[ -n "$CLI" ]] || { echo "Claude CLI를 찾지 못했습니다. https://docs.claude.com/claude-code 에서 설치하세요."; exit 1; }
echo "Claude CLI가 열리면 /login 을 입력해 로그인한 뒤 /exit 로 나오세요."
exec "$CLI"
