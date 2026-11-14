# Notes for AI coding agents

GQAI Live: microphone → local Whisper (whisper.cpp) → Claude cleanup → (macOS app) paste into the front app.
Personal tool, built from source on macOS. User-facing text and docs are Korean.

## Read first
- Adding a feature? Check **docs/FEATURES-NOT-INCLUDED.md**. It describes features that existed in the original
  app (file transcription, history, Markdown view/edit, selection edit/ask, other cleanup styles, system audio,
  dictionary CSV/auto-learn) with the original behavior, prompts, API shapes and pitfalls. Follow it, and update
  that document when you add something.
- Windows work? **docs/WINDOWS.md** has the reviewed design (C# + WebView2, bridge contract, Win32 APIs, caveats).
  The repo contains no Windows code.

## Layout and flow
- `server/server.py` — routes. `/api/transcribe` takes one live segment as base64 16 kHz mono PCM16 WAV (≤21 s);
  the page does the resampling, so there is no ffmpeg dependency. `/api/organize` streams SSE `delta`/`progress`/`done`/`error`.
- `server/organizer.py` — one `ClaudeSDKClient` per recording session (`append` only), on a dedicated asyncio loop
  thread. Tools disabled, `setting_sources=[]`. Prompt rules live in `SYSTEM_PROMPT`; per-request options
  (output language, dictionary terms) go in a `<guide>` block, re-sent only when it changes.
- `server/whisper_server.py` — starts and talks to whisper.cpp `whisper-server` (model stays in memory).
- `server/config.py` — all settings (`config.env` + env vars, `GQAI_` prefix). Don't hardcode paths.
- `web/app.js` — capture (AudioWorklet), pause detection, segment queue, Claude trigger on pause, insert.
  Native bridge: page → app `Native.post({type: state|insert|insertPermission})`;
  app → page `window.gqaiNative.toggle() / inserted(msg) / insertPermission(ok)`.
- `mac/Sources/` — `main.swift` (menu bar, hotkey, message handling), `WebWindow.swift` (WKWebView + bridge
  `gqai`), `TextInserter.swift` (front app, clipboard + ⌘V, restore), `ServerManager.swift` (runs `.venv/bin/python
  server/server.py` from the path baked into Info.plist by `build.sh`), `HotKey.swift`.

## Conventions
- Python: standard library + `claude-agent-sdk` only. No web framework.
- Web: plain HTML/JS, no build step, no external scripts.
- Never log transcript text, prompts or credentials (`diagnostics.event` takes counts and timings only).
- The server binds to 127.0.0.1 and rejects POSTs from other origins; keep it that way.
- Keep the Native bridge contract in sync across `web/app.js`, `mac/`, and docs/WINDOWS.md.

## Run and check
```bash
scripts/setup-mac.sh                  # once
scripts/run.sh                        # browser at http://127.0.0.1:7860
mac/build.sh --no-install             # compile check for the app
```
There is no automated test suite. Check by speaking into the page, and for the app: ⌥⇧R in another app's text field.
