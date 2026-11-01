"""PreToolUse decisions for a second-brain vault (spec sections 5.4 and 6).

Deny writes to _raw/**, .claude/**, top-level CLAUDE.md and .second-brain.json.
Ask before deleting anything under wiki/. Decide Write/Edit/MultiEdit on notes by trust tier
(trust.py). A folder's _about.md is guarded too (D34): `protected` is human-only, other edits
ask. Bash may not write a note or an _about.md under wiki/ at all (D33, D34): they change only
through the tools where the guard simulates the result. Bash matching is best effort (interpreter one-liners
such as python -c are not parsed): git is the real net.
"""
import glob
import itertools
import os
import re
import shlex
from pathlib import Path

from .frontmatter import parse
from .tree import _is_true, folder_protected
from .trust import (append_only, hidden_trust_lines, link_only, norm, tier, trust_key_lines,
                    trust_fields_changed_text)
from .vault import find_vault, is_note_rel

WRITE_TOOLS = {"Write": "file_path", "Edit": "file_path", "MultiEdit": "file_path",
               "NotebookEdit": "notebook_path"}
PROTECTED_DIRS = {"_raw", ".claude"}
PROTECTED_FILES = {"CLAUDE.md", ".second-brain.json"}
SEGMENT_SPLIT = re.compile(r"&&|\|\||;|\||\n")
ENV_ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
WRAPPERS = {"command", "time", "nohup", "exec", "builtin", "!", "{", "}", "then",
            "do", "else", "elif", "if", "while", "until"}
DELETE_CMDS = {"rmdir", "rm", "unlink", "shred"}
ALL_OPERANDS_WRITE = {"mv", "touch", "tee", "sponge", "truncate", "ln", "chmod", "chown", "mkdir"}
LAST_OPERAND_WRITES = {"cp", "install", "rsync"}
NOTE_ALL_OPERANDS = {"mv", "touch", "tee", "sponge", "truncate", "ln"}  # chmod etc. keep v0.1
CD_CMDS = {"cd", "pushd"}
MAX_DEPTH = 5
MAX_VARIANTS = 50
MAX_FOUND = 400
MAX_ABSOLUTE = 6
# wrappers whose own options (and, for the value-taking ones, their values) precede the command
PEELERS = {"sudo": {"-u", "-g", "-C", "-h", "-p", "-r", "-t", "-T", "-U", "--user", "--group"},
           "doas": {"-u", "-C"}, "env": {"-u", "-C"}, "timeout": {"-s", "-k", "--signal", "--kill-after"},
           "nice": {"-n", "--adjustment"}, "stdbuf": {"-i", "-o", "-e"},
           "ionice": {"-c", "-n", "-p"}, "setsid": set(), "chrt": set()}
FIND_EXEC = {"-exec", "-execdir", "-ok", "-okdir"}
XARGS_VALUE_OPTIONS = {"-d", "-E", "-L", "-n", "-P", "-s", "-e", "-l", "--delimiter", "--max-args",
                       "--max-lines", "--max-procs", "--max-chars", "--eof"}
EDITORS = {"ex", "ed", "red"}
VIMS = {"vim", "vi", "nvim", "view", "vimdiff"}
INTERPRETER_RE = re.compile(r"^(?:python[0-9.]*|node(?:js)?|perl|ruby|deno|bun)$")
MENTION = re.compile(r"wiki/|_raw|\.claude|\.md\b|\.second-brain", re.IGNORECASE)

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
ABOUT_ASK_REASON = ("_about.md describes a folder and is edited by the human; confirm this change "
                    "with the user.")
ASK_REASON = ("%s is curated knowledge. Confirm the deletion with the user first; git can "
              "restore it.")
UNRESOLVED_REASON = "second-brain cannot resolve this write target; confirm with the user."
INTERPRETER_REASON = ("This interpreter command may modify notes; notes are written only with "
                      "Write/Edit. Confirm with the user.")
DIR_ASK_REASON = ("%s is inside wiki/ and this command may write notes there; confirm with the "
                  "user. Notes are written only with Write/Edit.")
SIMULATE_ASK_REASON = ("The guard could not apply this edit to %s to check it (the text to "
                       "replace was not found). Confirm with the user.")


class Scope:
    """The vault a Bash command is checked against. `strict` is true when the cwd lies in that
    vault, so an expansion the guard cannot resolve may name a path inside it (D35)."""

    def __init__(self, vault, strict, text):
        self.vault, self.strict, self.text = vault, strict, text

    def rel(self, cwd, raw):
        return _rel(self.vault, cwd, raw)

    def strict_copy(self):
        return Scope(self.vault, True, self.text)


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


QUOTES = str.maketrans({"\u2018": "'", "\u2019": "'", "\u201a": "'", "\u201b": "'",
                        "\u201c": '"', "\u201d": '"', "\u201e": '"', "\u201f": '"'})


def _apply_edit(text, old, new, replace_all):
    """`text` with `old` replaced; a match that fails is retried with curly and straight quotes
    treated as the same character. None when `old` is not found either way."""
    if old in text:
        return text.replace(old, new) if replace_all else text.replace(old, new, 1)
    flat, flat_old = text.translate(QUOTES), old.translate(QUOTES)
    start = flat.find(flat_old)
    if start < 0:
        return None
    out, last = [], 0
    while start >= 0:
        out += [text[last:start], new]
        last = start + len(old)
        start = flat.find(flat_old, last) if replace_all else -1
    return "".join(out) + text[last:]


def simulate(tool, tool_input, current):
    """Text of the file after the tool runs, or None when an Edit/MultiEdit `old_string` is
    absent (the tool itself will fail). `current` is None for a file that does not exist. An
    empty `old_string` creates the content of a missing or empty file."""
    if tool == "Write":
        return str(tool_input.get("content") or "")
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
        if not old:
            if text:
                return None
            text = new
            continue
        if text is None:
            return None
        text = _apply_edit(text, old, new, bool(edit.get("replace_all")))
        if text is None:
            return None
    return text


def _is_note(rel):
    return rel is not None and rel.startswith("wiki/") and rel.endswith(".md") \
        and is_note_rel(rel[len("wiki/"):])


def _is_about(rel):
    return rel is not None and rel.startswith("wiki/") and rel.endswith("/_about.md")


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
    except UnicodeDecodeError:
        return _decision("ask", SIMULATE_ASK_REASON % rel)
    except OSError:
        return None                      # the tool itself will fail on an unreadable file
    new = simulate(tool, tool_input, current)
    if new is None:
        return None if current is None else _decision("ask", SIMULATE_ASK_REASON % rel)
    new = new.replace("\r\n", "\n")
    if current is None or not current.strip():
        data = parse(new).data
        if norm(data.get("origin")) != "agent":
            return _decision("deny", NEW_ORIGIN_REASON)
        lines = trust_key_lines(new)
        if any(lines[f] for f in lines if f != "origin") or len(lines["origin"]) != 1 \
                or hidden_trust_lines(new):
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


def _decide_about(vault, tool, tool_input, rel):
    """D34: the agent never changes `protected` in a folder's _about.md; other edits ask."""
    try:
        current = _read(vault / rel)
    except UnicodeDecodeError:
        return _decision("ask", SIMULATE_ASK_REASON % rel)
    except OSError:
        return None
    new = simulate(tool, tool_input, current)
    if new is None:
        return None if current is None else _decision("ask", SIMULATE_ASK_REASON % rel)
    new = new.replace("\r\n", "\n")
    if current is None:
        lines = trust_key_lines(new)["protected"]
        if _is_true(parse(new).data.get("protected")) or any(
                _is_true(line.split(":", 1)[1]) for line in lines) or any(
                field in ("protected", "*") for field, _line in hidden_trust_lines(new)):
            return _decision("deny", TRUST_REASON)
        return None
    if "protected" in trust_fields_changed_text(current, new):
        return _decision("deny", TRUST_REASON)
    if new == current:
        return None
    return _decision("ask", ABOUT_ASK_REASON)


def _is_protected(rel):
    return rel is not None and (rel.split("/")[0] in PROTECTED_DIRS or rel in PROTECTED_FILES)


def _strip_wrappers(tokens):
    i = 0
    while i < len(tokens) and (tokens[i] in WRAPPERS or ENV_ASSIGNMENT.match(tokens[i])):
        i += 1
    return tokens[i:]


def _classify(scope, cwd, operands, deleting=True):
    """Verdict for deleting `operands`: protected paths deny, curated notes ask."""
    verdict = None
    for raw in operands:
        rel = scope.rel(cwd, raw)
        if rel is not None:
            if _is_protected(rel) or (deleting and rel == "."):
                return ("deny", DENY_REASON % rel)
            if deleting and (rel == "wiki" or rel.startswith("wiki/")):
                verdict = _merge(verdict, ("ask", ASK_REASON % rel))
            elif deleting and "/" not in rel and any(c in rel for c in "*?["):
                verdict = _merge(verdict, ("ask", ASK_REASON % rel))
        if scope.strict and _has_var(raw):
            verdict = _merge(verdict, ("ask", UNRESOLVED_REASON))
    return verdict


C_FLAG = re.compile(r"^-[A-Za-z]*c[A-Za-z]*$")


def _nested_bodies(words, heredoc=""):
    """Command strings a segment runs through a shell: `-c` bodies (`-lc`, `-ec`...), `eval`
    arguments and, for a shell reading stdin, the here-document."""
    bodies = []
    for i, word in enumerate(words):
        if os.path.basename(word) in SHELLS:
            for j in range(i + 1, len(words)):
                if C_FLAG.match(words[j]):
                    if j + 1 < len(words):
                        bodies.append(str(words[j + 1]))
                    break
            else:
                if heredoc:
                    bodies.append(heredoc)
        elif word == "eval" and i + 1 < len(words):
            bodies.append(" ".join(words[i + 1:]))
    return bodies


def _words_run_review(words):
    """True when a word whose basename is `sb` (or `-m sb` / `-m sb.cli`) is followed by the
    subcommand `review`, wherever the word sits behind wrappers such as timeout or xargs."""
    for i, word in enumerate(words):
        start = None
        if os.path.basename(word) == "sb":
            start = i + 1
        elif word == "-m" and words[i + 1:i + 2] and words[i + 1] in ("sb", "sb.cli"):
            start = i + 2
        if start is not None:
            operands = [w for w in words[start:] if not w.startswith("-")]
            if operands[:1] == ["review"]:
                return True
    return False


def _has_sb_review(command, depth=0):
    if depth > MAX_DEPTH:
        return False
    for item in _lex(_expand_vars(command)):
        if isinstance(item, tuple):
            if _has_sb_review(item[1], depth + 1):
                return True
        elif isinstance(item, Segment):
            words = [str(w) for w in item.words]
            if _words_run_review(words):
                return True
            if any(_has_sb_review(body, depth + 1) for body in _nested_bodies(words, item.heredoc)):
                return True
    return False


# ---- Bash: a small shell lexer, then per-segment write detection --------------------------------

class Word(str):
    """A shell word with quotes removed; `glob` is True when it holds an unquoted * ? [."""
    glob = False
    var = False


class Segment:
    def __init__(self, words, redirects):
        self.words = words          # command words (program first)
        self.redirects = redirects  # output redirection targets
        self.heredoc = ""           # text of its here-documents


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
    cur, state = [], {"has": False, "glob": False, "var": False, "pending": None}
    heredocs, new_heredocs = [], []
    i, n = 0, len(command)

    def flush():
        if not state["has"]:
            return
        word = Word("".join(cur))
        word.glob = state["glob"]
        word.var = state["var"]
        del cur[:]
        state["has"], state["glob"], state["var"] = False, False, False
        mode, state["pending"] = state["pending"], None
        if mode is None:
            words.append(word)
        elif mode == "write":
            redirects.append(word)
        elif mode == "dup":
            if not (word.isdigit() or word == "-"):
                redirects.append(word)
        elif mode == "heredoc":
            new_heredocs.append(str(word))

    def end():
        flush()
        state["pending"] = None
        segment = Segment(list(words), list(redirects))
        if words or redirects:
            items.append(segment)
        heredocs.extend((delimiter, segment) for delimiter in new_heredocs)
        del new_heredocs[:], words[:], redirects[:]

    def sub(body):
        state["var"] = True
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
                    if command[i] == "$":
                        state["var"] = True
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
            for delimiter, owner in heredocs:
                while i < n:
                    j = command.find("\n", i)
                    j = n if j < 0 else j
                    raw_line = command[i:j]
                    i = min(j + 1, n)
                    if raw_line.lstrip("\t") == delimiter:
                        break
                    owner.heredoc += raw_line + "\n"
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
            elif c == "$":
                state["var"] = True
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


def _expand_vars(command, base=None):
    """Replace $NAME / ${NAME} by the value of a simple NAME=value assignment seen earlier (or
    by `base`, the values known up front such as PWD and HOME)."""
    env, out, pos = dict(base or {}), [], 0
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


def _w(text, like=None):
    """A Word with the text of `text` that keeps the variable flag of `like`."""
    word = Word(text)
    word.var = _has_var(like) if like is not None else False
    return word


def _has_var(word):
    """True when the word holds an unquoted or double-quoted `$` / backtick expansion."""
    flag = getattr(word, "var", None)
    return ("$" in word or "`" in word) if flag is None else flag


def _candidates(scope, cwd, word):
    """Vault-relative paths a word can name: brace alternatives and, for globs, existing matches."""
    rels = []
    for alternative in _braces(str(word)):
        rels.append(scope.rel(cwd, alternative))
        if getattr(word, "glob", False):
            path = _inside(scope.vault, cwd, alternative)
            if path:
                for found in itertools.islice(glob.iglob(path, recursive=True), 200):
                    rels.append(scope.rel(cwd, found))
    return [r for r in rels if r is not None]


def _target_verdict(scope, cwd, word, dir_sources=()):
    """('deny', reason) when writing `word` hits a protected path or a note; ('ask', reason) when
    the target holds an expansion that cannot be resolved. `dir_sources` are the names being
    placed when `word` is a directory (cp/mv/ln into it)."""
    for rel in _candidates(scope, cwd, word):
        if _is_protected(rel):
            return ("deny", DENY_REASON % rel)
        if _is_note(rel) or _is_about(rel):
            return ("deny", NOTE_WRITE_REASON)
        if dir_sources and (str(word).endswith("/") or (scope.vault / rel).is_dir()):
            for name in dir_sources:
                inner = rel.rstrip("/") + "/" + os.path.basename(str(name).rstrip("/"))
                if _is_protected(inner):
                    return ("deny", DENY_REASON % inner)
                if _is_note(inner) or _is_about(inner):
                    return ("deny", NOTE_WRITE_REASON)
    if scope.strict and _has_var(word):
        return ("ask", UNRESOLVED_REASON)
    return None


def _dir_verdict(scope, cwd, word):
    """Verdict for a directory that files are extracted or downloaded into."""
    for rel in _candidates(scope, cwd, word):
        if _is_protected(rel):
            return ("deny", DENY_REASON % rel)
        if rel == "wiki" or rel.startswith("wiki/"):
            return ("ask", DIR_ASK_REASON % rel)
    if scope.strict and _has_var(word):
        return ("ask", UNRESOLVED_REASON)
    return None


def _merge(current, verdict):
    """Combine verdicts: a deny wins, otherwise the first ask stays."""
    if verdict is None:
        return current
    if verdict[0] == "deny" or current is None:
        return verdict
    return current


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
            directory, skip = _w(args[index + 1], args[index + 1]), True
        elif arg.startswith("--target-directory="):
            directory = _w(arg.split("=", 1)[1], arg)
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
        return [(_w(a[3:], a), (), True) for a in args if a.startswith("of=")]
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


def _is_writer(program, args):
    return (program in DELETE_CMDS or program in ALL_OPERANDS_WRITE
            or program in LAST_OPERAND_WRITES or _in_place(program, args))


def _segment_verdict(scope, cwd, program, args):
    operands = [a for a in args if not a.startswith("-")]
    if program in DELETE_CMDS:
        return _classify(scope, cwd, operands, deleting=True)
    verdict = None
    for word, sources, notes in _segment_targets(program, args):
        found = _target_verdict(scope, cwd, word, sources)
        if found and found[0] == "deny" and not notes and found[1] == NOTE_WRITE_REASON:
            continue
        verdict = _merge(verdict, found)
        if verdict and verdict[0] == "deny":
            return verdict
    return verdict


def _peel(tokens):
    """The command behind env assignments and wrappers such as sudo -u x, timeout 5, nice -n 3."""
    while True:
        tokens = _strip_wrappers(tokens)
        if not tokens or os.path.basename(tokens[0]) not in PEELERS:
            return tokens
        program = os.path.basename(tokens[0])
        takes = PEELERS[program]
        i = 1
        while i < len(tokens):
            token = tokens[i]
            if token == "--":
                i += 1
                break
            if token in takes:
                i += 2
            elif token.startswith("-") and len(token) > 1:
                i += 1
            elif program == "env" and ENV_ASSIGNMENT.match(token):
                i += 1
            else:
                break
        if program == "timeout" and i < len(tokens):
            i += 1                                # the duration
        tokens = tokens[i:]


def _git_parts(args, cwd):
    """(subcommand, its arguments, cwd) of a git command line, after the global options."""
    i = 0
    while i < len(args) and args[i].startswith("-"):
        option = args[i]
        if option == "-C" and i + 1 < len(args):
            cwd = os.path.realpath(os.path.join(cwd, os.path.expanduser(args[i + 1])))
            i += 2
        elif option in ("-c", "--git-dir", "--work-tree", "--namespace", "--exec-path") \
                and i + 1 < len(args):
            i += 2
        else:
            i += 1
    if i >= len(args):
        return "", [], cwd
    return args[i], list(args[i + 1:]), cwd


def _mentions(scope):
    return bool(MENTION.search(scope.text))


def _patch_verdict(scope, cwd, program, args):
    if any(a in ("--check", "--stat", "--numstat", "--summary", "--dry-run") for a in args):
        return None
    verdict = None
    if program == "patch":
        for operand in [a for a in args if not a.startswith("-")][:1]:
            verdict = _merge(verdict, _target_verdict(scope, cwd, operand))
    if verdict is None and scope.strict:
        verdict = ("ask", UNRESOLVED_REASON)
    return verdict


def _option_values(args, short, long_, attached_short=True):
    """Values of `-o VALUE`, `-oVALUE`, `--out VALUE`, `--out=VALUE` among args; `short` is a
    set of option letters, `long_` a set of long names."""
    found, i = [], 0
    while i < len(args):
        arg = args[i]
        if arg.startswith("--"):
            name, eq, value = arg.partition("=")
            if name in long_:
                if eq:
                    found.append(_w(value, arg))
                elif i + 1 < len(args):
                    found.append(args[i + 1])
                    i += 1
        elif arg.startswith("-") and len(arg) > 1:
            letters = arg[1:]
            for k, letter in enumerate(letters):
                if letter in short:
                    if k + 1 < len(letters):
                        if attached_short:
                            found.append(_w(letters[k + 1:], arg))
                    elif i + 1 < len(args):
                        found.append(args[i + 1])
                        i += 1
                    break
        i += 1
    return found


def _download_verdict(scope, cwd, program, args):
    verdict = None
    if program == "curl":
        files = _option_values(args, {"o"}, {"--output"})
        dirs = _option_values(args, set(), {"--output-dir"})
    else:
        files = _option_values(args, {"O"}, {"--output-document"})
        dirs = _option_values(args, {"P"}, {"--directory-prefix"})
    for word in files:
        if str(word) != "-":
            verdict = _merge(verdict, _target_verdict(scope, cwd, word))
    for word in dirs:
        verdict = _merge(verdict, _dir_verdict(scope, cwd, word))
    return verdict


def _extract_verdict(scope, cwd, program, args):
    if program == "tar":
        first = args[0] if args else ""
        extracting = any(a in ("--extract", "--get") or re.match(r"^-[A-Za-z]*x", a)
                         for a in args) or bool(re.match(r"^[A-Za-z]*x[A-Za-z]*$", first))
        dirs = _option_values(args, {"C"}, {"--directory"})
    else:
        if any(re.match(r"^-[A-Za-z]*[lvtpcZ]", a) for a in args):
            return None                           # listing, testing or piping, not extracting
        extracting = True
        dirs = _option_values(args, {"d"}, set())
    if not extracting:
        return None
    verdict = None
    for word in dirs or [cwd]:
        verdict = _merge(verdict, _dir_verdict(scope, cwd, word))
    return verdict


def _editor_verdict(scope, cwd, program, args):
    """ex, ed and vim -es edit files named in a script; the file operands are the targets."""
    if program in VIMS and not (any(a in ("-es", "-Es", "-s", "--headless") for a in args)):
        return None
    verdict = None
    for operand in [a for a in args if not a.startswith("-")]:
        verdict = _merge(verdict, _target_verdict(scope, cwd, operand))
        if verdict and verdict[0] == "deny":
            return verdict
    if verdict is None and _mentions(scope):
        verdict = ("ask", UNRESOLVED_REASON)
    return verdict


def _inline_code(program, args):
    """True when an interpreter runs code from -c / -e or stdin instead of a script file."""
    if program.startswith("python"):
        flags = any(re.match(r"^-[A-Za-z]*c$", a) for a in args)
    elif program in ("perl", "ruby"):
        flags = any(re.match(r"^-[A-Za-z]*[eE]$", a) for a in args)
    elif program in ("node", "nodejs"):
        flags = any(a in ("-e", "-p", "--eval", "--print", "-pe") for a in args)
    elif program == "deno":
        flags = args[:1] == ["eval"]
    else:
        flags = any(a in ("-e", "--eval") for a in args)
    if flags:
        return True
    if "-m" in args:
        return False
    return not args or all(a.startswith("-") for a in args) or "-" in args


def _interpreter_verdict(scope, program, args):
    if _inline_code(program, args) and _mentions(scope):
        return ("ask", INTERPRETER_REASON)
    return None


def _found_paths(scope, cwd, roots):
    """(paths under the find roots that lie in the vault, whether the list was cut)."""
    paths, cut = [], False
    for root in roots:
        real = os.path.realpath(os.path.join(cwd, os.path.expanduser(str(root))))
        if scope.rel(cwd, root) is None:
            continue
        paths.append(real)
        if os.path.isdir(real):
            for dirpath, dirs, files in os.walk(real):
                dirs[:] = [d for d in dirs if d != ".git"]
                for name in dirs + files:
                    if len(paths) >= MAX_FOUND:
                        return paths, True
                    paths.append(os.path.join(dirpath, name))
    return paths, cut


def _find_verdict(scope, cwd, args, depth):
    roots, i = [], 0
    while i < len(args) and not args[i].startswith("-") and args[i] not in ("(", ")", "!"):
        roots.append(args[i])
        i += 1
    roots = roots or [Word(".")]
    expr = list(args[i:])
    verdict = None
    index = 0
    while index < len(expr):
        token = str(expr[index])
        if token == "-delete":
            for root in roots:
                for rel in _candidates(scope, cwd, root):
                    if _is_protected(rel):
                        return ("deny", DENY_REASON % rel)
                    if rel in (".", "wiki") or rel.startswith("wiki/"):
                        verdict = _merge(verdict, ("ask", ASK_REASON % rel))
                if scope.strict and _has_var(root):
                    verdict = _merge(verdict, ("ask", UNRESOLVED_REASON))
        elif token in ("-fprint", "-fprint0", "-fls", "-fprintf") and index + 1 < len(expr):
            verdict = _merge(verdict, _target_verdict(scope, cwd, expr[index + 1]))
        elif token in FIND_EXEC:
            end = index + 1
            while end < len(expr) and str(expr[end]) not in (";", "+"):
                end += 1
            sub = list(expr[index + 1:end])
            index = end
            verdict = _merge(verdict, _find_exec(scope, cwd, roots, sub, depth))
        if verdict and verdict[0] == "deny":
            return verdict
        index += 1
    return verdict


def _find_exec(scope, cwd, roots, sub, depth):
    """Scan an -exec command with {} replaced by the paths found under the roots."""
    if not sub:
        return None
    if not any("{}" in str(t) for t in sub):
        return _run(scope, cwd, sub, depth)
    paths, cut = _found_paths(scope, cwd, roots)
    peeled = _peel(sub)
    per_path = bool(peeled) and (os.path.basename(peeled[0]) in LAST_OPERAND_WRITES
                                 or os.path.basename(peeled[0]) in ("mv", "ln"))
    batches = [[p] for p in paths] if per_path else [paths]
    verdict = None
    for batch in batches:
        words = []
        for token in sub:
            if "{}" in str(token):
                if str(token) == "{}":
                    words.extend(_w(p) for p in batch)
                else:
                    words.extend(_w(str(token).replace("{}", p), token) for p in batch)
            else:
                words.append(token)
        verdict = _merge(verdict, _run(scope, cwd, words, depth))
        if verdict and verdict[0] == "deny":
            return verdict
    if cut and verdict is None and _is_writer_tokens(peeled):
        verdict = ("ask", UNRESOLVED_REASON)
    return verdict


def _is_writer_tokens(tokens):
    return bool(tokens) and _is_writer(os.path.basename(tokens[0]), tokens[1:])


def _xargs_verdict(scope, cwd, args, depth):
    i, placeholder, arg_file = 0, None, None
    while i < len(args) and args[i].startswith("-") and args[i] != "--":
        arg = args[i]
        if arg in ("-a", "--arg-file") and i + 1 < len(args):
            arg_file, i = args[i + 1], i + 2
        elif arg == "-I" and i + 1 < len(args):
            placeholder, i = str(args[i + 1]), i + 2
        elif arg.startswith("-I") and len(arg) > 2:
            placeholder, i = str(arg[2:]), i + 1
        elif arg.startswith("--replace"):
            placeholder, i = (arg.partition("=")[2] or "{}"), i + 1
        elif arg.startswith("-i"):
            placeholder, i = (arg[2:] or "{}"), i + 1
        elif arg in XARGS_VALUE_OPTIONS and i + 1 < len(args):
            i += 2
        else:
            i += 1
    if i < len(args) and args[i] == "--":
        i += 1
    inner = list(args[i:])
    if not inner:
        return None
    listed = []
    if arg_file:
        try:
            with open(os.path.join(cwd, os.path.expanduser(str(arg_file))), encoding="utf-8",
                      errors="replace") as handle:
                listed = [line.strip() for line in handle.read(65536).replace("\0", "\n").split("\n")
                          if line.strip()][:MAX_FOUND]
        except OSError:
            listed = []
    stdin = [_w(line) for line in listed] if arg_file and listed else [_w("$XARGS_INPUT", "$")]
    if placeholder:
        words = []
        for token in inner:
            text = str(token)
            if placeholder not in text:
                words.append(token)
            elif text == placeholder:
                words.extend(stdin)
            else:
                words.extend(_w(text.replace(placeholder, str(s)), s) for s in stdin)
    else:
        words = inner + stdin
    verdict = _run(scope.strict_copy(), cwd, words, depth)
    if verdict and verdict[0] == "ask" and verdict[1] == UNRESOLVED_REASON and not _mentions(scope):
        return None                     # the input is not known to hold notes
    return verdict


def _command(scope, cwd, tokens, depth):
    """Verdict of one command (wrappers already peeled): ('deny'|'ask', why), ('cd', path) or None."""
    program, args = os.path.basename(tokens[0]), list(tokens[1:])
    if program == "git":
        sub, args, cwd = _git_parts(args, cwd)
        if sub == "apply":
            return _patch_verdict(scope, cwd, "apply", args)
        program = sub if sub in ("rm", "mv") else "git"
    if program in CD_CMDS:
        target = [t for t in args if not t.startswith("-")][:1]
        if not target:
            return ("cd", os.path.expanduser("~"))
        if target[0] == "-" or _has_var(target[0]):
            return ("ask", UNRESOLVED_REASON) if scope.strict else None
        return ("cd", os.path.realpath(os.path.join(cwd, os.path.expanduser(target[0]))))
    if program == "find":
        return _find_verdict(scope, cwd, args, depth)
    if program == "xargs":
        return _xargs_verdict(scope, cwd, args, depth)
    if program == "patch":
        return _patch_verdict(scope, cwd, "patch", args)
    if program in ("curl", "wget"):
        return _download_verdict(scope, cwd, program, args)
    if program in ("tar", "unzip"):
        return _extract_verdict(scope, cwd, program, args)
    if program in EDITORS or program in VIMS:
        return _editor_verdict(scope, cwd, program, args)
    verdict = _segment_verdict(scope, cwd, program, args)
    if INTERPRETER_RE.match(program) and not (verdict and verdict[0] == "deny"):
        verdict = _merge(verdict, _interpreter_verdict(scope, program, args))
    return verdict


def _run(scope, cwd, words, depth):
    """Verdict of a command given as words, behind its wrappers; nested shells are scanned."""
    verdict = None
    for body in _nested_bodies([str(w) for w in words]):
        verdict = _merge(verdict, _scan(scope, cwd, body, depth + 1))
    tokens = _peel(words)
    if tokens:
        found = _command(scope, cwd, tokens, depth)
        if found and found[0] != "cd":
            verdict = _merge(verdict, found)
    return verdict


def _scan(scope, cwd, command, depth=0):
    """('deny', reason), ('ask', reason) or None for a command string; `cwd` follows `cd`."""
    if depth > MAX_DEPTH:
        return None
    base = {"HOME": os.path.expanduser("~")}
    if not re.search(r"\b(?:cd|pushd|popd)\b", command):
        base["PWD"] = str(cwd)
    ask, stack = None, []
    for item in _lex(_expand_vars(command, base)):
        if item == "(":
            stack.append(cwd)
            continue
        if item == ")":
            cwd = stack.pop() if stack else cwd
            continue
        if isinstance(item, tuple):
            verdict = _scan(scope, cwd, item[1], depth + 1)
        else:
            verdict = _segment(scope, cwd, item, depth)
            if verdict and verdict[0] == "cd":
                cwd, verdict = verdict[1], None
        if verdict and verdict[0] == "deny":
            return verdict
        ask = _merge(ask, verdict)
    return ask


def _segment(scope, cwd, segment, depth):
    verdict = None
    for word in segment.redirects:
        verdict = _merge(verdict, _target_verdict(scope, cwd, word))
    words = list(segment.words)
    for body in _nested_bodies([str(w) for w in words], segment.heredoc):
        verdict = _merge(verdict, _scan(scope, cwd, body, depth + 1))
    tokens = _peel(words)
    if tokens:
        found = _command(scope, cwd, tokens, depth)
        if found and found[0] == "cd" and verdict is None:
            return found
        if found and found[0] != "cd":
            verdict = _merge(verdict, found)
    return verdict


def _loop_variants(scope, cwd, command):
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
                path = _inside(scope.vault, cwd, word)
                found = sorted(itertools.islice(glob.iglob(path, recursive=True), 20)) if path else []
            values.extend(found or [word])
        pattern = re.compile(r"\$(?:%s\b|\{%s\})" % (name, name))
        variants = [pattern.sub(lambda _m, v=v: v, text) for text in variants
                    for v in values[:20]][:MAX_VARIANTS] or variants
    return variants


ABSOLUTE_PATH = re.compile(r"(?:(?<=[\s='\"(<>:;|&,])|^)(~?/[^\s'\"<>|;&()`$]*)")


def _bash_vaults(cwd, command):
    """Vaults a command can touch: the one holding the cwd, then those named by absolute paths."""
    own = find_vault(cwd)
    vaults = [own] if own else []
    seen = set()
    for match in ABSOLUTE_PATH.finditer(command):
        directory = os.path.realpath(os.path.expanduser(match.group(1)))
        if directory in seen:
            continue
        seen.add(directory)
        found = find_vault(directory)
        if found and found not in vaults:
            vaults.append(found)
        if len(seen) >= MAX_ABSOLUTE:
            break
    return own, vaults


def _decide_bash(cwd, command):
    own, vaults = _bash_vaults(cwd, command)
    if not vaults:
        return None
    if _has_sb_review(command):
        return _decision("deny", REVIEW_REASON)
    ask = None
    for vault in vaults:
        scope = Scope(vault, vault == own, command)
        for variant in _loop_variants(scope, cwd, command):
            verdict = _scan(scope, cwd, variant)
            if verdict and verdict[0] == "deny":
                return _decision("deny", verdict[1])
            ask = _merge(ask, verdict)
    return _decision("ask", ask[1]) if ask else None


def decide(event, cwd):
    cwd = event.get("cwd") or cwd
    tool = event.get("tool_name", "")
    tool_input = event.get("tool_input") or {}
    if tool in WRITE_TOOLS:
        raw = tool_input.get(WRITE_TOOLS[tool])
        if not raw:
            return None
        target = os.path.realpath(os.path.join(cwd, os.path.expanduser(str(raw).strip().strip("'\""))))
        vault = find_vault(os.path.dirname(target))
        if vault is None:
            return None
        rel = _rel(vault, cwd, raw)
        if _is_protected(rel):
            return _decision("deny", DENY_REASON % rel)
        if tool != "NotebookEdit" and _is_note(rel):
            return _decide_note(vault, tool, tool_input, rel)
        if tool != "NotebookEdit" and _is_about(rel):
            return _decide_about(vault, tool, tool_input, rel)
        return None
    if tool == "Bash":
        return _decide_bash(cwd, tool_input.get("command", ""))
    return None
