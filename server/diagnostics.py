"""JSON-line diagnostics log. Never records transcript text, prompts or credentials."""
import contextvars
import datetime
import json
import logging
from logging.handlers import RotatingFileHandler

import config

LOG_FILE = config.LOG_DIR / "server.log"
request_id = contextvars.ContextVar("gqai_request_id", default=None)
logger = logging.getLogger("gqai.diagnostics")
logger.addHandler(logging.NullHandler())
logger.propagate = False


def configure():
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    for handler in logger.handlers[:]:
        logger.removeHandler(handler)
        handler.close()
    handler = RotatingFileHandler(LOG_FILE, maxBytes=2_000_000, backupCount=3, encoding="utf-8")
    handler.setFormatter(logging.Formatter("%(message)s"))
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)


def event(name, **fields):
    record = {"time": datetime.datetime.now().astimezone().isoformat(timespec="milliseconds"),
              "event": name, "request": request_id.get(), **fields}
    logger.info(json.dumps(record, ensure_ascii=False))
