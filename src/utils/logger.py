import json
import logging
import os
import sys
import uuid
from datetime import datetime, timezone
from typing import Any


class StructuredLogger:
    """Cloud Logging structured logger with trace ID propagation."""

    def __init__(self, name: str):
        self._name = name
        self._base_logger = logging.getLogger(name)

    def _emit(self, severity: str, message: str, **extra: Any) -> None:
        entry = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "severity": severity,
            "logger": self._name,
            "message": message,
        }
        # Prefix any field named 'severity' in extra to avoid collision with the top-level key
        for k, v in extra.items():
            safe_key = f"field_{k}" if k == "severity" else k
            entry[safe_key] = v
        # Cloud Logging picks up JSON lines written to stdout
        print(json.dumps(entry), flush=True)

    def info(self, message: str, **extra: Any) -> None:
        self._emit("INFO", message, **extra)

    def warning(self, message: str, **extra: Any) -> None:
        self._emit("WARNING", message, **extra)

    def error(self, message: str, **extra: Any) -> None:
        self._emit("ERROR", message, **extra)

    def debug(self, message: str, **extra: Any) -> None:
        if os.getenv("LOG_LEVEL", "INFO").upper() == "DEBUG":
            self._emit("DEBUG", message, **extra)


def get_logger(name: str) -> StructuredLogger:
    return StructuredLogger(name)


def generate_trace_id() -> str:
    return str(uuid.uuid4())
