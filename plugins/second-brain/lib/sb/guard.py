"""PreToolUse decisions for a second-brain vault (spec sections 5.4 and 6).

Deny writes to _raw/**, .claude/**, top-level CLAUDE.md and .second-brain.json.
Ask before deleting anything under wiki/. Decide Write/Edit/MultiEdit on notes by trust tier
(trust.py). Bash may not write a note under wiki/ at all (D33): notes change only through the
tools where the guard simulates the result. Bash matching is best effort (interpreter one-liners
such as python -c are not parsed): git is the real net.
"""
import glob
import itertools
import os
import re
import shlex
from pathlib import Path

from .frontmatter import parse
from .tree import folder_protected
from .trust import append_only, link_only, norm, tier, trust_key_lines, trust_fields_changed_text
from .vault import find_vault, is_note_rel

WRITE_TOOLS = {"Write": "file_path", "Edit": "file_path", "MultiEdit": "file_path",
               "NotebookEdit": "notebook_path"}
PROTECTED_DIRS = {"_raw", ".claude"}
PROTECTED_FILES = {"CLAUDE.md", ".second-brain.json"}
SEGMENT_SPLIT = re.compile(r"&&|\|\||;|\||\n")
ENV_ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
WRAPPERS = {"sudo", "command", "time", "nohup", "exec", "builtin", "!", "{", "}", "then",
            "do", "else", "elif", "if", "while", "until"}
DELETE_CMDS = {"rmdir", "rm", "unlink", "shred"}
ALL_OPERANDS_WRITE = {"mv", "touch", "tee", "sponge", "truncate", "ln", "chmod", "chown", "mkdir"}
LAST_OPERAND_WRITES = {"cp", "install", "rsync"}
NOTE_ALL_OPERANDS = {"mv", "touch", "tee", "sponge", "truncate", "ln"}  # chmod etc. keep v0.1
CD_CMDS = {"cd", "pushd"}
MAX_DEPTH = 5
MAX_VARIANTS = 50

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
NOTE_WRITE_REASON = ("Notes under wiki/ are written only with the Write/Edit tools, where the guard "
                     "checks trust tiers. Use Edit to append a \"> [!agent]\" block instead of "
                     "shell redirection.")
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
        if folder_protected(vault, rel):
            return _decision("ask", T2_REASON % rel)
        return None
    if trust_fields_changed_text(current, new):
        return _decision("deny", TRUST_REASON)
    if new == current:
        return None
    level = tier(parse(current).data, folder_protected(vault, rel))
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


# ---- Bash: a small shell lexer, then per-segment write detection --------------------------------

class Word(str):
    """A shell word with quotes removed; `glob` is True when it holds an unquoted * ? [."""
    glob = False


class Segment:
    def __init__(self, words, redirects):
        self.words = words          # command words (program first)
        self.redirects = redirects  # output redirection targets


def _match_paren(text, i):
    """Index of the `)` closing the `(` before text[i], quote aware; len(text) when unclosed."""
    depth, quote = 1, None
    while i < len(text):
        c = text[i]
        if quote:
            if c == "\\" and quote == '"':
                i += 1
            elif c == quote:
                quote = None
        elif c in "'\"":
            quote = c
        elif c == "\\":
            i += 1
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return len(text)


def _lex(command):
    """Items in order: Segment, "(" , ")" or ("sub", text) for `$(...)` and backtick bodies."""
    items, words, redirects = [], [], []
    cur, state = [], {"has": False, "glob": False, "pending": None}
    heredocs = []
    i, n = 0, len(command)

    def flush():
        if not state["has"]:
            return
        word = Word("".join(cur))
        word.glob = state["glob"]
        del cur[:]
        state["has"], state["glob"] = False, False
        mode, state["pending"] = state["pending"], None
        if mode is None:
            words.append(word)
        elif mode == "write":
            redirects.append(word)
        elif mode == "dup":
            if not (word.isdigit() or word == "-"):
                redirects.append(word)
        elif mode == "heredoc":
            heredocs.append(str(word))

    def end():
        flush()
        state["pending"] = None
        if words or redirects:
            items.append(Segment(list(words), list(redirects)))
        del words[:], redirects[:]

    def sub(body):
        items.append(("sub", body))

    while i < n:
        c = command[i]
        nxt = command[i + 1] if i + 1 < n else ""
        if c == "'":
            j = command.find("'", i + 1)
            j = n if j < 0 else j
            cur.append(command[i + 1:j])
            state["has"] = True
            i = j + 1
        elif c == '"':
            i += 1
            state["has"] = True
            while i < n and command[i] != '"':
                if command[i] == "\\" and i + 1 < n:
                    cur.append(command[i + 1])
                    i += 2
                elif command.startswith("$(", i):
                    j = _match_paren(command, i + 2)
                    sub(command[i + 2:j])
                    cur.append(command[i:j + 1])
                    i = j + 1
                elif command[i] == "`":
                    j = command.find("`", i + 1)
                    j = n if j < 0 else j
                    sub(command[i + 1:j])
                    cur.append(command[i:j + 1])
                    i = j + 1
                else:
                    cur.append(command[i])
                    i += 1
            i += 1
        elif c == "\\":
            if nxt == "\n":
                i += 2
                continue
            cur.append(nxt)
            state["has"] = True
            i += 2
        elif c == "$" and nxt == "(":
            j = _match_paren(command, i + 2)
            sub(command[i + 2:j])
            cur.append(command[i:j + 1])
            state["has"] = True
            i = j + 1
        elif c == "`":
            j = command.find("`", i + 1)
            j = n if j < 0 else j
            sub(command[i + 1:j])
            cur.append(command[i:j + 1])
            state["has"] = True
            i = j + 1
        elif c == "#" and not state["has"]:
            j = command.find("\n", i)
            i = n if j < 0 else j
        elif c in " \t":
            flush()
            i += 1
        elif c == "\n":
            end()
            i += 1
            for delimiter in heredocs:
                while i < n:
                    j = command.find("\n", i)
                    j = n if j < 0 else j
                    line = command[i:j].lstrip("\t")
                    i = min(j + 1, n)
                    if line == delimiter:
                        break
            del heredocs[:]
        elif c == ";":
            end()
            i += 1
        elif c == "&" and nxt == "&":
            end()
            i += 2
        elif c == "|":
            end()
            i += 2 if nxt in "|&" and nxt else 1
        elif c == "&" and nxt != ">":
            end()
            i += 1
        elif c in "()":
            end()
            items.append(c)
            i += 1
        elif c in "<>&":
            if c == ">" or c == "&":
                digits = "".join(cur)
                if state["has"] and not digits.isdigit():
                    flush()
                elif state["has"]:
                    del cur[:]
                    state["has"] = False
            else:
                digits = "".join(cur)
                if state["has"] and digits.isdigit():
                    del cur[:]
                    state["has"] = False
                else:
                    flush()
            if c == "<":
                if command.startswith("<<<", i):
                    state["pending"], i = "ignore", i + 3
                elif command.startswith("<<", i):
                    i += 3 if command.startswith("<<-", i) else 2
                    state["pending"] = "heredoc"
                else:
                    state["pending"], i = "ignore", i + 1
            else:
                j = i + 1 if c == ">" else i + 2
                mode = "write"
                if c == ">" and nxt == "&":
                    mode, j = "dup", i + 2
                elif c == ">" and nxt == ">":
                    j = i + 2
                elif c == ">" and nxt == "|":
                    j = i + 2
                elif c == "&" and command.startswith("&>>", i):
                    j = i + 3
                state["pending"], i = mode, j
        else:
            cur.append(c)
            state["has"] = True
            if c in "*?[":
                state["glob"] = True
            i += 1
    end()
    return items


ASSIGNMENT = re.compile(
    r"""(?:(?<![\w$.\-/])|^)(?:(?:export|local|declare|readonly|typeset)\s+(?:-\w+\s+)*)?"""
    r"""([A-Za-z_]\w*)=("(?:[^"\\]|\\.)*"|'[^']*'|[^\s;&|<>()"'`]*)""")
VAR_REF = re.compile(r"\$(?:([A-Za-z_]\w*)|\{([A-Za-z_]\w*)\})")
FOR_LOOP = re.compile(r"\bfor\s+([A-Za-z_]\w*)\s+in\s+([^;\n]*?)\s*(?:;|\n)\s*do\b")


def _substitute(text, env):
    return VAR_REF.sub(lambda m: env.get(m.group(1) or m.group(2), m.group(0)), text)


def _expand_vars(command):
    """Replace $NAME / ${NAME} by the value of a simple NAME=value assignment seen earlier."""
    env, out, pos = {}, [], 0
    for m in ASSIGNMENT.finditer(command):
        if m.start() < pos:
            continue
        out.append(_substitute(command[pos:m.start()], env))
        out.append(m.group(0))
        pos = m.end()
        raw = m.group(2)
        if "$(" in raw or "`" in raw or command[pos:pos + 1] == "(":
            env.pop(m.group(1), None)
        else:
            env[m.group(1)] = _substitute(raw[1:-1] if raw[:1] in "'\"" and len(raw) > 1 else raw, env)
    out.append(_substitute(command[pos:], env))
    return "".join(out)


def _braces(text):
    """Bash brace expansion of `{a,b}` (comma form only)."""
    start = text.find("{")
    while start >= 0:
        depth, commas, i = 0, [], start
        while i < len(text):
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
                if depth == 0:
                    break
            elif text[i] == "," and depth == 1:
                commas.append(i)
            i += 1
        if i < len(text) and commas:
            bounds = [start] + commas + [i]
            out = []
            for a, b in zip(bounds, bounds[1:]):
                out.extend(_braces(text[:start] + text[a + 1:b] + text[i + 1:]))
            return out[:MAX_VARIANTS]
        start = text.find("{", start + 1)
    return [text]


def _inside(vault, cwd, raw):
    path = os.path.normpath(os.path.join(cwd, os.path.expanduser(raw.strip())))
    return path if path == str(vault) or path.startswith(str(vault) + os.sep) else None


def _candidates(vault, cwd, word):
    """Vault-relative paths a word can name: brace alternatives and, for globs, existing matches."""
    rels = []
    for alternative in _braces(str(word)):
        rels.append(_rel(vault, cwd, alternative))
        if word.glob:
            path = _inside(vault, cwd, alternative)
            if path:
                for found in itertools.islice(glob.iglob(path, recursive=True), 200):
                    rels.append(_rel(vault, cwd, found))
    return [r for r in rels if r is not None]


def _target_verdict(vault, cwd, word, dir_sources=()):
    """('deny', reason) when writing `word` hits a protected path or a note. `dir_sources` are
    the names being placed when `word` is a directory (cp/mv/ln into it)."""
    for rel in _candidates(vault, cwd, word):
        if _is_protected(rel):
            return ("deny", DENY_REASON % rel)
        if _is_note(rel):
            return ("deny", NOTE_WRITE_REASON)
        if dir_sources and (str(word).endswith("/") or (vault / rel).is_dir()):
            for name in dir_sources:
                inner = rel.rstrip("/") + "/" + os.path.basename(str(name).rstrip("/"))
                if _is_protected(inner):
                    return ("deny", DENY_REASON % inner)
                if _is_note(inner):
                    return ("deny", NOTE_WRITE_REASON)
    return None


def _split_options(args):
    """(operands, directory from -t / --target-directory or None) of a command's arguments."""
    operands, directory, skip, plain = [], None, False, False
    for index, arg in enumerate(args):
        if skip:
            skip = False
        elif plain or not arg.startswith("-") or arg == "-":
            operands.append(arg)
        elif arg == "--":
            plain = True
        elif arg == "-t" and index + 1 < len(args):
            directory, skip = Word(args[index + 1]), True
        elif arg.startswith("--target-directory="):
            directory = Word(arg.split("=", 1)[1])
    return operands, directory


def _in_place(program, args):
    """sed -i / --in-place, perl -i / -pi, gawk -i inplace."""
    if program in ("sed", "perl"):
        return any(a.startswith("--in-place") or re.match(r"-[A-Za-z]*i", a) for a in args)
    return program in ("awk", "gawk") and "inplace" in args


def _segment_targets(program, args):
    """(word, dir_sources, is_note_write) for each path a segment writes besides redirections.
    `dir_sources` are the names placed when the word is a directory."""
    if program == "dd":
        return [(Word(a[3:]), (), True) for a in args if a.startswith("of=")]
    operands, directory = _split_options(args)
    if _in_place(program, args):
        return [(a, (), True) for a in operands]
    if program in LAST_OPERAND_WRITES:           # cp, install, rsync: the destination
        if directory is not None:
            return [(directory, operands, True)]
        return [(a, operands[:-1], True) for a in operands[-1:]]
    if program in ALL_OPERANDS_WRITE:
        notes = program in NOTE_ALL_OPERANDS     # chmod, chown, mkdir only guard protected paths
        if directory is not None:
            return [(directory, operands, notes)]
        sources = operands[:-1] if program in ("mv", "ln") else ()
        return [(a, sources, notes) for a in operands]
    return []


def _segment_verdict(vault, cwd, tokens):
    program = os.path.basename(tokens[0])
    args = tokens[1:]
    operands = [a for a in args if not a.startswith("-")]
    if program == "git" and operands and operands[0] == "rm":
        program, operands = "rm", operands[1:]
    if program in DELETE_CMDS:
        verdict = _classify(vault, cwd, operands, deleting=True)
        return ("deny", DENY_REASON % verdict[1]) if verdict and verdict[0] == "deny" else verdict
    for word, sources, notes in _segment_targets(program, args):
        verdict = _target_verdict(vault, cwd, word, sources)
        if verdict and (notes or verdict[1] != NOTE_WRITE_REASON):
            return verdict
    return None


def _scan(vault, cwd, command, depth=0):
    """('deny', reason), ('ask', rel) or None for a command string; `cwd` follows `cd`."""
    if depth > MAX_DEPTH:
        return None
    ask, stack = None, []
    for item in _lex(_expand_vars(command)):
        if item == "(":
            stack.append(cwd)
            continue
        if item == ")":
            cwd = stack.pop() if stack else cwd
            continue
        if isinstance(item, tuple):
            verdict = _scan(vault, cwd, item[1], depth + 1)
        else:
            verdict = _segment(vault, cwd, item, depth)
            if isinstance(verdict, str):      # a `cd` moved us
                cwd, verdict = verdict, None
        if verdict and verdict[0] == "deny":
            return verdict
        ask = verdict or ask
    return ask


def _segment(vault, cwd, segment, depth):
    for word in segment.redirects:
        verdict = _target_verdict(vault, cwd, word)
        if verdict:
            return verdict
    tokens = _strip_wrappers(segment.words)
    if tokens and os.path.basename(tokens[0]) == "env":
        tokens = _strip_wrappers([t for t in tokens[1:] if not t.startswith("-")])
    if not tokens:
        return None
    program = os.path.basename(tokens[0])
    if program in CD_CMDS:
        target = [t for t in tokens[1:] if not t.startswith("-")][:1]
        if target and "$" not in target[0]:
            return os.path.realpath(os.path.join(cwd, os.path.expanduser(target[0])))
        return None
    if program in SHELLS and "-c" in tokens[1:]:
        body = tokens[tokens.index("-c") + 1:][:1]
        if body:
            return _scan(vault, cwd, body[0], depth + 1)
    return _segment_verdict(vault, cwd, tokens)


def _loop_variants(vault, cwd, command):
    """The command once per word of each `for NAME in words; do` loop (globs expanded)."""
    variants = [command]
    for m in FOR_LOOP.finditer(command):
        name = m.group(1)
        try:
            words = shlex.split(m.group(2))
        except ValueError:
            words = m.group(2).split()
        values = []
        for word in words:
            found = []
            if any(c in word for c in "*?["):
                path = _inside(vault, cwd, word)
                found = sorted(itertools.islice(glob.iglob(path, recursive=True), 20)) if path else []
            values.extend(found or [word])
        pattern = re.compile(r"\$(?:%s\b|\{%s\})" % (name, name))
        variants = [pattern.sub(lambda _m, v=v: v, text) for text in variants
                    for v in values[:20]][:MAX_VARIANTS] or variants
    return variants


def _decide_bash(vault, cwd, command):
    if _has_sb_review(command):
        return _decision("deny", REVIEW_REASON)
    ask = None
    for variant in _loop_variants(vault, cwd, command):
        verdict = _scan(vault, cwd, variant)
        if verdict and verdict[0] == "deny":
            return _decision("deny", verdict[1])
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
