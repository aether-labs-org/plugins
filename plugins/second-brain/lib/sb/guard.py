"""PreToolUse decisions for a second-brain vault (spec section 6).

Deny writes to _raw/**, .claude/**, top-level CLAUDE.md and .second-brain.json.
Ask before deleting anything under wiki/. Bash matching is best effort: git is the real net.
"""
import os
import re
import shlex
from pathlib import Path

from .vault import find_vault

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
        return _decision("deny", DENY_REASON % rel) if _is_protected(rel) else None
    if tool == "Bash":
        return _decide_bash(vault, cwd, tool_input.get("command", ""))
    return None
