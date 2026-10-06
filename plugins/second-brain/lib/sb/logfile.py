"""Append-only _log.md (spec 4.3)."""
from datetime import date
from pathlib import Path

from .fsutil import write_atomic

EVENTS = ("init", "capture", "ingest", "update", "link", "lint")


def append(root, event, title, today=None):
    if event not in EVENTS:
        raise ValueError("unknown log event %r (expected one of %s)" % (event, ", ".join(EVENTS)))
    title = " ".join(str(title).split())
    line = "## [%s] %s | %s\n" % (today or date.today().isoformat(), event, title)
    path = Path(root) / "_log.md"
    try:
        existing = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        existing = ""
    if existing and not existing.endswith("\n"):
        existing += "\n"
    write_atomic(path, existing + line)
