"""SessionStart: one status line for the model; git work only on startup and resume (spec 6.2)."""
from typing import Optional

from . import autocommit
from .sanitize import clean_inline, escape_tags
from .trust import label
from .vault import (LEGACY_MESSAGE, VaultError, find_legacy_vault, find_vault, load_config,
                    load_notes, sync_mode)

HEAD = "<second-brain-vault>\n"
FOOT = "\n</second-brain-vault>"
MAX_CHARS = 300
GIT_SOURCES = ("startup", "resume")      # clear, compact, fork and anything else: no git (D58)


def _inbox_count(root):
    inbox = root / "_inbox"
    try:
        return sum(1 for p in inbox.iterdir() if p.is_file() and not p.name.startswith((".", "_")))
    except OSError:
        return 0


def _wrap(line):
    return {"hookSpecificOutput": {"hookEventName": "SessionStart",
                                   "additionalContext": HEAD + line + FOOT}}


def start(event, cwd, env=None) -> Optional[dict]:
    where = event.get("cwd") or cwd
    root = find_vault(where)
    if root is None:
        if find_legacy_vault(where) is not None:
            return _wrap(escape_tags(clean_inline("second-brain: " + LEGACY_MESSAGE, MAX_CHARS - 60)))
        return None
    try:
        config = load_config(root)
    except VaultError:
        config = {}
    source = event.get("source") or "startup"
    pull_vault = sync_mode(config) == "pull"
    sync_text, unpushed = "local", 0
    if source in GIT_SOURCES:
        autocommit.run(root, env=env, outside=True)
        if pull_vault:
            from . import sync

            if sync.enabled(root):
                sync_text = sync.pull(root)
                unpushed = sync.ahead(root)
            else:
                sync_text = "skipped: not a pull vault"
    elif pull_vault:
        sync_text = "not checked"
    unreviewed = sum(1 for n in load_notes(root) if label(n.data, n.body) == "unreviewed")
    head = "Status: inbox %d · unreviewed %d · sync " % (_inbox_count(root), unreviewed)
    tail = " · unpushed %d" % unpushed if unpushed else ""
    room = MAX_CHARS - len(HEAD) - len(head) - len(tail) - len(FOOT)
    return _wrap(head + escape_tags(clean_inline(sync_text, room)) + tail)
