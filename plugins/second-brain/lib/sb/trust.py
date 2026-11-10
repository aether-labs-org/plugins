"""Trust label of a note (spec 5.3)."""
import re

AGENT_BLOCK_RE = re.compile(r"^>[ \t]*\[!agent\]", re.IGNORECASE | re.MULTILINE)


def label(data, body):
    """`unreviewed` | `has-agent-blocks` | `reviewed`. A missing `origin` means human."""
    origin = str(data.get("origin") or "").strip().lower()
    reviewed = str(data.get("reviewed") or "").strip()
    if origin in ("agent", "mixed") and not reviewed:
        return "unreviewed"
    if AGENT_BLOCK_RE.search(body or ""):
        return "has-agent-blocks"
    return "reviewed"
