"""Trust label of a note (spec 5.3)."""
import re

AGENT_BLOCK_RE = re.compile(r"^>[ \t]*\[!agent\]", re.IGNORECASE | re.MULTILINE)


def label(data, body):
    """`unreviewed` when an agent wrote the note and nobody reviewed it, else `reviewed`.
    `mixed` counts as human; an `[!agent]` callout does not change the label."""
    origin = str(data.get("origin") or "").strip().lower()
    reviewed = str(data.get("reviewed") or "").strip()
    return "unreviewed" if origin == "agent" and not reviewed else "reviewed"
