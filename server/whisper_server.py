"""Keeps whisper.cpp `whisper-server` running with the model loaded in memory.

Loading a large model per request would take seconds for every live segment; a resident server answers
a short segment in about a second on Apple Silicon.
"""
import atexit
import json
import os
import subprocess
import threading
import time
import urllib.error
import urllib.request
import uuid

import config

URL = f"http://127.0.0.1:{config.WHISPER_SERVER_PORT}"
LOG = config.LOG_DIR / "whisper-server.log"

_proc = None
_lock = threading.Lock()
_failed_at = 0.0


def _alive() -> bool:
    try:
        with urllib.request.urlopen(URL + "/", timeout=1):
            return True
    except (urllib.error.URLError, OSError):
        return False


def problem() -> str:
    """Why Whisper can't run, or '' when the binary and model are in place."""
    if not config.WHISPER_SERVER.is_file():
        return f"whisper-server가 없습니다: {config.WHISPER_SERVER} (scripts/setup-mac.sh를 실행하세요)"
    if not config.WHISPER_MODEL.is_file():
        return f"Whisper 모델이 없습니다: {config.WHISPER_MODEL}"
    return ""


def ensure(wait: float = 90) -> bool:
    """Starts the server if needed. After a failure, returns False for a minute without retrying."""
    global _proc, _failed_at
    with _lock:
        if _proc is not None and _proc.poll() is None and _alive():
            return True
        if _proc is None and _alive():
            return True  # a server from an earlier run on the same port
        if time.time() - _failed_at < 60 or problem():
            return False
        LOG.parent.mkdir(parents=True, exist_ok=True)
        log = open(LOG, "ab")
        cmd = [str(config.WHISPER_SERVER), "-m", str(config.WHISPER_MODEL), "--host", "127.0.0.1",
               "--port", str(config.WHISPER_SERVER_PORT), "-l", "auto"]
        _proc = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT, start_new_session=(os.name != "nt"))
        deadline = time.time() + wait
        while time.time() < deadline:
            if _proc.poll() is not None:
                break
            if _alive():
                return True
            time.sleep(0.5)
        _failed_at = time.time()
        stop()
        return False


def warm_async():
    threading.Thread(target=ensure, daemon=True, name="whisper-warm").start()


def transcribe(wav: bytes, language: str, prompt: str = "", timeout: float = 120) -> str:
    """Transcribes one 16 kHz mono WAV. Raises RuntimeError when the server is unavailable."""
    if not ensure():
        raise RuntimeError(problem() or "whisper-server를 시작하지 못했습니다. 로그를 확인하세요: " + str(LOG))
    boundary = uuid.uuid4().hex
    fields = {"response_format": "json", "language": language, "temperature": "0.0"}
    if prompt:
        fields["prompt"] = prompt
    parts = [f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode() for k, v in fields.items()]
    parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="audio.wav"\r\n'
                 'Content-Type: audio/wav\r\n\r\n'.encode() + wav + b"\r\n")
    body = b"".join(parts) + f"--{boundary}--\r\n".encode()
    req = urllib.request.Request(URL + "/inference", data=body, method="POST",
                                 headers={"Content-Type": f"multipart/form-data; boundary={boundary}"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as res:
            data = json.loads(res.read().decode("utf-8", "replace"))
    except (urllib.error.URLError, OSError, ValueError) as e:
        raise RuntimeError(f"whisper-server 요청 실패: {e}") from e
    if "error" in data:
        raise RuntimeError(f"whisper-server 오류: {data['error']}")
    return str(data.get("text", "")).strip()


def stop():
    global _proc
    if _proc is not None and _proc.poll() is None:
        _proc.terminate()
        try:
            _proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            _proc.kill()
    _proc = None


atexit.register(stop)
