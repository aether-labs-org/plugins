"""SessionStart: folder tree and vault status for the model (spec 6.2)."""
import time
from typing import Optional

from . import tree
from .sanitize import clean_inline, escape_tags
from .trust import label
from .vault import VaultError, find_vault, load_config, load_notes

HEADER = ("<second-brain-vault>\n"
          "Folders under wiki/ (from _about.md; follow their conventions when filing notes):\n")
FOOTER = "</second-brain-vault>"


def _inbox_count(root):
    inbox = root / "_inbox"
    try:
        return sum(1 for p in inbox.iterdir() if p.is_file() and not p.name.startswith((".", "_")))
    except OSError:
        return 0


SLOW_PULL_SECONDS = 40     # past this the 90 s hook budget has no room left for a push


def _clock():
    return time.monotonic()


def _sync_status(root, config, session_id):
    """Pull, then retry a pending push (also after a crashed SessionEnd). Returns the status."""
    if config.get("sync") != "squad":
        return "local"
    from . import sync

    if not sync.enabled(root):
        return "local (squad sync skipped: the vault is not its own git repository)"
    started = _clock()
    result = sync.pull(root, session_id=session_id)
    if result != "ok":
        return result               # conflict: <files> or skipped: <why>; nothing to push over it
    if sync.pending(root) or sync.ahead(root):
        if _clock() - started > SLOW_PULL_SECONDS:
            return "push pending"   # no time left: the next session retries
        if sync.push(root).startswith("pending"):
            return "push pending"
    return "ok"


def start(event, cwd) -> Optional[dict]:
    root = find_vault(event.get("cwd") or cwd)
    if root is None:
        return None
    try:
        config = load_config(root)
    except VaultError:
        config = {}
    status = _sync_status(root, config, str(event.get("session_id") or ""))
    notes = load_notes(root)
    unreviewed = sum(1 for n in notes if label(n.data, n.body) == "unreviewed")
    compact = tree.render_compact(tree.load(root)) or "(no folders yet)"
    text = "%s%s\nStatus: inbox %d · unreviewed %d · sync %s\n%s" % (
        HEADER, compact, _inbox_count(root), unreviewed, escape_tags(clean_inline(status, 300)), FOOTER)
    return {"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": text}}
