"""Term dictionary (names, acronyms, jargon), stored in data/dictionary.json.

Used twice: as a Whisper recognition hint (initial prompt) and as spelling rules for the Claude cleanup.
"""
import json
import re
import threading
import time

import config

FILE = config.DATA_DIR / "dictionary.json"
MAX_TERMS, MAX_TERM_CHARS, MAX_NOTE_CHARS = 1000, 40, 100
WHISPER_PROMPT_CHARS = 150  # longer prompts make Whisper more likely to echo the hint on silence
_lock = threading.RLock()


def _read() -> list:
    try:
        data = json.loads(FILE.read_text(encoding="utf-8"))
        return data if isinstance(data, list) else []
    except (OSError, ValueError):
        return []


def _write(words: list) -> None:
    tmp = FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(words, ensure_ascii=False, indent=1), encoding="utf-8")
    tmp.replace(FILE)


def _clean(term) -> str:
    t = re.sub(r"\s+", " ", str(term or "")).strip()
    if not 1 <= len(t) <= MAX_TERM_CHARS:
        raise ValueError(f"용어는 1~{MAX_TERM_CHARS}자여야 합니다.")
    return t


def get() -> list:
    with _lock:
        return _read()


def add(term, note="") -> list:
    with _lock:
        words = _read()
        t, n = _clean(term), str(note or "").strip()[:MAX_NOTE_CHARS]
        for w in words:
            if w["term"] == t:
                w["note"] = n or w.get("note", "")
                break
        else:
            if len(words) >= MAX_TERMS:
                raise ValueError(f"사전은 최대 {MAX_TERMS}개입니다.")
            words.append({"term": t, "note": n, "added": time.time()})
        _write(words)
        return words


def delete(term) -> list:
    with _lock:
        words = [w for w in _read() if w["term"] != str(term)]
        _write(words)
        return words


def whisper_prompt() -> str:
    """Comma-separated terms, newest first, cut to a short hint."""
    out, size = [], 0
    for w in reversed(get()):
        if size + len(w["term"]) + 2 > WHISPER_PROMPT_CHARS:
            break
        out.append(w["term"])
        size += len(w["term"]) + 2
    return ", ".join(out)


def guide_lines() -> str:
    words = get()[:300]
    return "; ".join(w["term"] + (f" ({w['note']})" if w.get("note") else "") for w in words)
