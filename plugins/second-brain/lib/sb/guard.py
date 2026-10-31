"""PreToolUse decisions for a second-brain vault (spec sections 5.4 and 6).

Deny writes to _raw/**, .claude/**, top-level CLAUDE.md and .second-brain.json.
Ask before deleting anything under wiki/. Decide Write/Edit/MultiEdit on notes by trust tier
(trust.py). Bash matching is best effort: git is the real net.
"""
import os
import re
import shlex
from pathlib import Path

from .frontmatter import parse
from .trust import append_only, link_only, norm, tier, trust_key_lines, trust_fields_changed_text
from .vault import find_vault, is_note_rel

WRITE_TOOLS = {"Write": "file_path", "Edit": "file_path", "MultiEdit": "file_path",
               "NotebookEdit": "notebook_path"}
PROTECTED_DIRS = {"_raw", ".claude"}
PROTECTED_FILES = {"CLAUDE.md", ".second-brain.json"}
SEGMENT_SPLIT = re.compile(r"&&|\|\||;|\||\n")
REDIRECT = re.compile(r"\d*>>?\s*([^\s;&|<>]+)")
ENV_ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
WRAPPERS = {"sudo", "command", "time", "nohup", "exec", "builtin"}
DELETE_CMDS = {"rm", "rmdir", "unlink", "shred"}
ALL_OPERANDS_WRITE = {"mv", "touch", "tee", "truncate", "ln", "chmod", "chown", "mkdir"}
LAST_OPERAND_WRITES = {"cp", "install", "rsync"}

DENY_REASON = ("%s is protected in a second-brain vault: _raw/ is immutable, and CLAUDE.md, "
               ".claude/ and .second-brain.json are edited by the human. Ask the human to "
               "change it directly.")
TRUST_REASON = ("Only the human sets trust fields (reviewed, reviewed_hash, protected, origin). "
                "Leave them as they are and ask the user to edit them in Obsidian Properties.")
NEW_ORIGIN_REASON = ("New notes written by the agent must have origin: agent. Add "
                     "`origin: agent` to the frontmatter.")
T1_REASON = ('%s is a human or reviewed note (T1). Prefer appending a "> [!agent]" block; '
             "editing it in place needs the user's approval.")
T2_REASON = ("%s is protected (T2: protected, evergreen or protected folder). Every change "
             "needs the user's approval.")
REVIEW_REASON = ("`sb review` records a human review. The user runs it in a terminal or with "
                 "the ! prefix.")
SHELLS = {"bash", "sh", "zsh", "dash"}
ASK_REASON = ("%s is curated knowledge. Confirm the deletion with the user first; git can "
              "restore it.")


def _decision(kind, reason):
    return {"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                   "permissionDecision": kind,
                                   "permissionDecisionReason": reason}}


def _rel(vault, cwd, raw):
    raw = raw.strip().strip("'\"")
    path = os.path.realpath(os.path.join(cwd, os.path.expanduser(raw)))
    try:
        return Path(path).relative_to(vault).as_posix()
    except ValueError:
        return None


def simulate(tool, tool_input, current):
    """Text of the file after the tool runs, or None when an Edit/MultiEdit `old_string` is
    absent (the tool itself will fail). `current` is None for a file that does not exist."""
    if tool == "Write":
        return str(tool_input.get("content") or "")
    if current is None:
        return None
    if tool == "Edit":
        edits = [tool_input]
    elif tool == "MultiEdit":
        edits = tool_input.get("edits") or []
    else:
        return None
    text = current
    for edit in edits:
        old = str(edit.get("old_string") or "").replace("\r\n", "\n")
        new = str(edit.get("new_string") or "").replace("\r\n", "\n")
        if not old or old not in text:
            return None
        text = text.replace(old, new) if edit.get("replace_all") else text.replace(old, new, 1)
    return text


def _is_note(rel):
    return rel is not None and rel.startswith("wiki/") and rel.endswith(".md") \
        and is_note_rel(rel[len("wiki/"):])


def _read(path):
    """Current text (LF) of an existing file, or None when it does not exist."""
    try:
        return path.read_text(encoding="utf-8").replace("\r\n", "\n")
    except FileNotFoundError:
        return None


def _decide_note(vault, tool, tool_input, rel):
    path = vault / rel
    try:
        current = _read(path)
    except (OSError, UnicodeDecodeError):
        return None                      # the tool itself will fail on an unreadable file
    new = simulate(tool, tool_input, current)
    if new is None:
        return None
    new = new.replace("\r\n", "\n")
    if current is None:
        data = parse(new).data
        if norm(data.get("origin")).lower() != "agent":
            return _decision("deny", NEW_ORIGIN_REASON)
        lines = trust_key_lines(new)
        if any(lines[f] for f in lines if f != "origin") or len(lines["origin"]) != 1:
            return _decision("deny", TRUST_REASON)
        return None
    if trust_fields_changed_text(current, new):
        return _decision("deny", TRUST_REASON)
    if new == current:
        return None
    level = tier(parse(current).data)
    if level == "T0":
        return None
    if level == "T1":
        if append_only(current, new) or link_only(current, new):
            return None
        return _decision("ask", T1_REASON % rel)
    return _decision("ask", T2_REASON % rel)


def _is_protected(rel):
    return rel is not None and (rel.split("/")[0] in PROTECTED_DIRS or rel in PROTECTED_FILES)


def _strip_wrappers(tokens):
    i = 0
    while i < len(tokens) and (tokens[i] in WRAPPERS or ENV_ASSIGNMENT.match(tokens[i])):
        i += 1
    return tokens[i:]


def _classify(vault, cwd, operands, deleting):
    ask = None
    for raw in operands:
        rel = _rel(vault, cwd, raw)
        if rel is None:
            continue
        if _is_protected(rel) or (deleting and rel == "."):
            return ("deny", rel)
        if deleting and (rel == "wiki" or rel.startswith("wiki/")):
            ask = ("ask", rel)
        elif deleting and "/" not in rel and any(c in rel for c in "*?["):
            ask = ("ask", rel)
    return ask


def _is_sb_review(program, args):
    operands = [a for a in args if not a.startswith("-")]
    if program == "sb":
        return operands[:1] == ["review"]
    if program.startswith("python"):
        if "-m" in args:
            module = args[args.index("-m") + 1:][:1]
            return module in (["sb"], ["sb.cli"]) and operands[1:2] == ["review"]
        return bool(operands) and operands[0].endswith("/bin/sb") and operands[1:2] == ["review"]
    return False


def _has_sb_review(command):
    for segment in SEGMENT_SPLIT.split(command):
        try:
            tokens = shlex.split(segment)
        except ValueError:
            tokens = segment.split()
        tokens = _strip_wrappers(tokens)
        if tokens and os.path.basename(tokens[0]) == "env":
            tokens = _strip_wrappers([t for t in tokens[1:] if not t.startswith("-")])
        if not tokens:
            continue
        program = os.path.basename(tokens[0])
        if _is_sb_review(program, tokens[1:]):
            return True
        if program in SHELLS and "-c" in tokens[1:]:
            rest = tokens[tokens.index("-c") + 1:][:1]
            if rest and _has_sb_review(rest[0]):
                return True
    return False


def _segment_verdict(vault, cwd, tokens):
    program = os.path.basename(tokens[0])
    args = tokens[1:]
    operands = [a for a in args if not a.startswith("-")]
    if program == "git" and operands and operands[0] == "rm":
        program, operands = "rm", operands[1:]
    if program in DELETE_CMDS:
        return _classify(vault, cwd, operands, deleting=True)
    if program == "sed" and any(a == "--in-place" or a.startswith("-i") for a in args):
        return _classify(vault, cwd, operands, deleting=False)
    if program in ALL_OPERANDS_WRITE:
        return _classify(vault, cwd, operands, deleting=False)
    if program in LAST_OPERAND_WRITES:
        return _classify(vault, cwd, operands[-1:], deleting=False)
    return None


def _decide_bash(vault, cwd, command):
    if _has_sb_review(command):
        return _decision("deny", REVIEW_REASON)
    for match in REDIRECT.finditer(command):
        rel = _rel(vault, cwd, match.group(1))
        if _is_protected(rel):
            return _decision("deny", DENY_REASON % rel)
    ask = None
    for segment in SEGMENT_SPLIT.split(command):
        try:
            tokens = shlex.split(segment)
        except ValueError:
            tokens = segment.split()
        tokens = _strip_wrappers(tokens)
        if not tokens:
            continue
        verdict = _segment_verdict(vault, cwd, tokens)
        if verdict and verdict[0] == "deny":
            return _decision("deny", DENY_REASON % verdict[1])
        ask = verdict or ask
    return _decision("ask", ASK_REASON % ask[1]) if ask else None


def decide(event, cwd):
    cwd = event.get("cwd") or cwd
    vault = find_vault(cwd)
    if vault is None:
        return None
    tool = event.get("tool_name", "")
    tool_input = event.get("tool_input") or {}
    if tool in WRITE_TOOLS:
        raw = tool_input.get(WRITE_TOOLS[tool])
        rel = _rel(vault, cwd, raw) if raw else None
        if _is_protected(rel):
            return _decision("deny", DENY_REASON % rel)
        if tool != "NotebookEdit" and _is_note(rel):
            return _decide_note(vault, tool, tool_input, rel)
        return None
    if tool == "Bash":
        return _decide_bash(vault, cwd, tool_input.get("command", ""))
    return None
