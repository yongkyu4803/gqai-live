"""GQAI Live local server (127.0.0.1 only, Python standard library + Claude Agent SDK).

Routes
  GET  /                      web page (web/index.html), /app.js, /mic-worklet.js
  GET  /api/status            Whisper and Claude readiness
  POST /api/transcribe        {audio: base64 16 kHz mono PCM16 WAV, language} -> {text}
  POST /api/organize          {session, text, context, lang} -> text/event-stream: delta / done / error
  POST /api/command           {session, instruction, selection, place, lang, app} -> event-stream, like organize
                              (instruction mode: carry out a spoken instruction on the selected text)
  POST /api/organize/warm     {session, kind}   pre-start the Claude session for a recording
  POST /api/organize/end      {session}   close it
  GET  /api/dictionary        {words}
  POST /api/dictionary        {action: add|delete, term, note}
"""
import base64
import io
import json
import queue
import re
import signal
import sys
import threading
import time
import uuid
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import config
import diagnostics
import dictionary
import organizer
import whisper_server

WEB = config.ROOT / "web"
STATIC = {"/": ("index.html", "text/html"), "/app.js": ("app.js", "text/javascript"),
          "/mic-worklet.js": ("mic-worklet.js", "text/javascript")}
ORIGINS = {f"http://127.0.0.1:{config.PORT}", f"http://localhost:{config.PORT}"}
LANGUAGES = ("auto", "ko", "en", "ja", "zh")
MAX_SEGMENT_SECONDS = 21
MAX_BODY = 4_000_000

# Phrases Whisper tends to invent on silence or noise. A live segment that is only one of these is dropped.
HALLUCINATIONS = {"thank you", "thanks for watching", "thank you for watching", "you", "bye",
                  "시청해주셔서 감사합니다", "시청해 주셔서 감사합니다", "구독과 좋아요 부탁드립니다",
                  "ご視聴ありがとうございました", "谢谢观看", "字幕由amara.org社区提供"}

ORGANIZER = organizer.Organizer()
whisper_lock = threading.Lock()


def is_hallucination(text: str) -> bool:
    return re.sub(r"[\s.,!?。！？…'\"]+", " ", text).strip().lower() in HALLUCINATIONS


def transcribe(d: dict) -> dict:
    language = d.get("language", "auto")
    if language not in LANGUAGES:
        raise ValueError("지원하지 않는 언어입니다.")
    try:
        audio = base64.b64decode(d.get("audio", ""), validate=True)
    except (ValueError, TypeError):
        raise ValueError("음성 데이터가 올바르지 않습니다.")
    try:  # the page resamples to 16 kHz mono PCM16, which is what whisper.cpp expects
        with wave.open(io.BytesIO(audio)) as w:
            ok = w.getframerate() == 16000 and w.getnchannels() == 1 and w.getsampwidth() == 2
            seconds = w.getnframes() / 16000
    except (wave.Error, EOFError):
        ok = False
    if not ok:
        raise ValueError("16kHz 모노 16비트 WAV만 받습니다.")
    if not 0 < seconds <= MAX_SEGMENT_SECONDS:
        raise ValueError(f"구간은 {MAX_SEGMENT_SECONDS}초 이하여야 합니다.")
    hint = dictionary.whisper_prompt()
    with whisper_lock:
        text = whisper_server.transcribe(audio, language, hint)
    if hint and text.replace(" ", "") == hint.replace(" ", ""):
        text = ""  # Whisper read the hint back on silence
    if is_hallucination(text):
        text = ""
    return {"text": text}


def status() -> dict:
    problem = whisper_server.problem()
    return {"whisper": {"ready": not problem, "message": problem, "model": config.WHISPER_MODEL.name},
            "claude": organizer.auth_status()}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, body, ctype="application/json"):
        if not isinstance(body, bytes):
            body = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype + "; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path in STATIC:
            name, ctype = STATIC[path]
            return self.send(200, (WEB / name).read_bytes(), ctype)
        if path == "/api/status":
            return self.send(200, status())
        if path == "/api/dictionary":
            return self.send(200, {"words": dictionary.get()})
        self.send(404, {"error": "not found"})

    def read_json(self):
        n = int(self.headers.get("Content-Length", 0))
        if n > MAX_BODY:
            raise ValueError("요청이 너무 큽니다.")
        data = json.loads(self.rfile.read(n) or b"{}")
        if not isinstance(data, dict):
            raise ValueError("요청 형식이 올바르지 않습니다.")
        return data

    def do_POST(self):
        origin = self.headers.get("Origin")
        if origin and origin not in ORIGINS:  # blocks other web pages from calling the local server
            return self.send(403, {"error": "허용되지 않은 Origin"})
        try:
            d = self.read_json()
            if self.path == "/api/transcribe":
                return self.send(200, transcribe(d))
            if self.path == "/api/organize":
                return self.organize(organizer.validate(d))
            if self.path == "/api/command":
                return self.organize(organizer.validate_command(d))
            if self.path == "/api/organize/warm":
                if organizer.auth_status()["loggedIn"]:
                    ORGANIZER.warm(str(uuid.UUID(str(d.get("session")))),
                                   "command" if d.get("kind") == "command" else "dictate")
                return self.send(200, {"ok": True})
            if self.path == "/api/organize/end":
                ORGANIZER.end(str(d.get("session") or ""))
                return self.send(200, {"ok": True})
            if self.path == "/api/dictionary":
                action = d.get("action")
                if action == "add":
                    return self.send(200, {"words": dictionary.add(d.get("term"), d.get("note"))})
                if action == "delete":
                    return self.send(200, {"words": dictionary.delete(d.get("term"))})
                raise ValueError("알 수 없는 사전 작업입니다.")
        except (ValueError, json.JSONDecodeError, TypeError) as e:
            return self.send(400, {"error": str(e)})
        except RuntimeError as e:
            return self.send(503, {"error": str(e)})
        self.send(404, {"error": "not found"})

    def organize(self, d):
        auth = organizer.auth_status()
        if not auth["loggedIn"]:
            return self.send(401, {"error": auth["message"]})
        q = queue.Queue()
        fut = ORGANIZER.start(d, lambda ev, data: q.put((ev, data)))
        fut.add_done_callback(lambda f: q.put(("_end", None)))
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "close")
        self.end_headers()
        alive, started, phase = True, time.monotonic(), {}

        def emit(event, data):
            nonlocal alive
            if not alive:
                return
            try:
                self.wfile.write(f"event: {event}\ndata: {json.dumps(data, ensure_ascii=False)}\n\n".encode())
                self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                alive = False  # keep the job running so the session state stays consistent

        while True:
            try:
                ev, data = q.get(timeout=2)
            except queue.Empty:
                emit("progress", {**phase, "seconds": int(time.monotonic() - started)})
                continue
            if ev == "_end":
                break
            if ev == "progress":
                phase = {k: v for k, v in data.items() if k != "seconds"}  # keep it in the heartbeat
            emit(ev, data)
        try:
            text = fut.result()
            emit("done", {"empty": text.strip() == organizer.EMPTY})
        except Exception as e:  # noqa: BLE001
            print(f"organize error: {e!r}", file=sys.stderr, flush=True)
            emit("error", {"message": f"정리 실패: {e or type(e).__name__}"})


if __name__ == "__main__":
    diagnostics.configure()
    diagnostics.event("server.start", port=config.PORT)
    print(f"GQAI Live: http://127.0.0.1:{config.PORT}", flush=True)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))  # let atexit stop whisper-server
    whisper_server.warm_async()
    ThreadingHTTPServer(("127.0.0.1", config.PORT), Handler).serve_forever()
