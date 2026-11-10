"""PostToolUse: frontmatter feedback for a note the agent just wrote (spec 5.5)."""
import os
from pathlib import Path

from .lint import check_note
from .vault import find_vault, is_note_rel, load_note


def check(event, cwd):
    cwd = event.get("cwd") or cwd
    vault = find_vault(cwd)
    if vault is None:
        return None
    raw = (event.get("tool_input") or {}).get("file_path")
    if not raw or not raw.endswith(".md"):
        return None
    path = Path(os.path.realpath(os.path.join(cwd, raw)))
    try:
        inside = path.relative_to(vault / "wiki").as_posix()
    except ValueError:
        return None
    if not is_note_rel(inside) or not path.is_file():
        return None
    findings = check_note(load_note(vault, path))
    if not findings:
        return None
    lines = ["second-brain: %s has frontmatter problems:" % findings[0].path]
    lines += ["- %s (line %d): %s" % (f.code, f.line, f.message) for f in findings]
    lines.append("Fix them before continuing.")
    return {"hookSpecificOutput": {"hookEventName": "PostToolUse",
                                   "additionalContext": "\n".join(lines)}}

