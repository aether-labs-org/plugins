#!/usr/bin/env python3
"""PreToolUse hook: keep the agent read-only against cloud accounts (plan D13/D14).

Reads the hook event JSON on stdin. Prints a deny decision for any command or
MCP call that would mutate cloud state; prints nothing (allow) otherwise.
"""
import json
import re
import shlex
import sys

GUIDANCE = (
    "solutions-architect is read-only against cloud accounts (decision D13). "
    "Generate the IaC or the command, then a human or the pipeline applies it."
)

TF_MUTATING = {"apply", "destroy", "import", "taint", "untaint", "force-unlock", "refresh"}
TF_STATE_MUTATING = {"rm", "mv", "push", "replace-provider"}
TF_WORKSPACE_MUTATING = {"new", "delete"}
CDK_MUTATING = {"deploy", "destroy", "bootstrap", "import", "migrate"}
SAM_MUTATING = {"deploy", "delete", "sync"}
KUBECTL_MUTATING = {"apply", "create", "delete", "patch", "replace", "scale", "edit",
                    "annotate", "label", "cordon", "uncordon", "drain", "taint", "set", "expose", "autoscale"}
AWS_READ_PREFIXES = ("get-", "list-", "describe-", "search-", "lookup-", "batch-get-", "check-",
                     "validate-", "preview-", "estimate-", "simulate-", "filter-", "test-", "wait", "help")
AWS_READ_EXACT = {"get-caller-identity", "ls", "help"}
AWS_VALUE_FLAGS = {"--region", "--profile", "--output", "--endpoint-url", "--query", "--cli-read-timeout",
                   "--cli-connect-timeout", "--ca-bundle", "--color", "--cli-binary-format"}
MUTATING_VERBS = ("create|delete|put|update|modify|terminate|run|start|stop|attach|detach|associate|"
                  "disassociate|register|deregister|tag|untag|enable|disable|reboot|revoke|authorize|"
                  "replace|reset|restore|cancel|import|invoke|publish|send|copy|upload|remove|add|set|apply")
BOTO_CALL = re.compile(r"\.\s*(?:%s)_[a-z0-9_]+\s*\(" % MUTATING_VERBS)
BOTO_OP_STRING = re.compile(r"[\"'](?:%s)_[a-z0-9_]+[\"']" % MUTATING_VERBS)
SEGMENT_SPLIT = re.compile(r"&&|\|\||;|\||\n|\$\(|`")
SHELL_NAMES = frozenset(("bash", "sh", "zsh", "dash", "ksh"))
TARGET_PROGS = ("terraform", "tofu", "aws", "cdk", "sam", "kubectl")
MAX_RECURSION = 6


def deny(reason):
    json.dump({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                      "permissionDecision": "deny",
                                      "permissionDecisionReason": f"{reason} {GUIDANCE}"}}, sys.stdout)
    sys.exit(0)


def tokens(segment):
    try:
        return shlex.split(segment, posix=True)
    except ValueError:
        return segment.split()


def find_c_arg(tok, idx):
    """If the shell invocation at tok[idx] takes -c (bare, or inside a combined
    short-option cluster such as -lc, -ec, -xc, -fc), return the index of the
    token that holds the command string; else None.

    Walks the option tokens after the shell name, skipping long options
    (--login, ...), "--" (end of options), and "-o <opt>" (which takes a
    value), noting whether any short-option cluster seen along the way
    contains "c". The first non-option token after that is the command
    string shlex handed the shell as a single argument.
    """
    saw_c = False
    i = idx + 1
    while i < len(tok):
        t = tok[i]
        if t == "--":
            i += 1
            break
        if t == "-o":
            i += 2
            continue
        if t.startswith("--"):
            i += 1
            continue
        if t.startswith("-") and len(t) > 1:
            if "c" in t[1:]:
                saw_c = True
            i += 1
            continue
        break
    if saw_c and i < len(tok):
        return i
    return None


def is_redirect(t):
    """True for a token that redirects a shell's stdin (`<`, `<<EOF`, `<<<...`)."""
    return t == "<" or t.startswith("<<")


def find_first(tok):
    """Locate the first token whose basename is a recognised shell or CLI
    (bash/sh/..., terraform, aws, ...), scanning ALL positions.

    This is the single mechanism that lets check_tokens see through wrappers
    with their own options (timeout, xargs, find -exec, nice, sudo -u x,
    env, FOO=bar, a shell before -c, ...) without special-casing each one:
    whatever precedes the recognised name is ignored, and the check runs
    against that name and the tokens that follow it. Program match is
    case-insensitive (M3).
    """
    for i, t in enumerate(tok):
        base = t.rsplit("/", 1)[-1].lower()
        if base in SHELL_NAMES:
            return i, "shell"
        if base in TARGET_PROGS:
            return i, "prog"
    return None, None


def positional(tok, value_flags=frozenset()):
    out, skip = [], False
    for t in tok:
        if skip:
            skip = False
            continue
        if t.startswith("-"):
            if t in value_flags:
                skip = True
            continue
        out.append(t)
    return out


def handle_prog(tok, idx):
    """Apply the terraform/aws/cdk/sam/kubectl mutating-call checks to the
    program found at tok[idx] and the tokens that follow it."""
    prog = tok[idx].rsplit("/", 1)[-1].lower()
    args = tok[idx + 1:]
    if prog in ("terraform", "tofu"):
        pos = positional(args)
        sub = pos[0] if pos else ""
        if sub in TF_MUTATING:
            deny(f"`{prog} {sub}` changes infrastructure or state.")
        if sub == "state" and len(pos) > 1 and pos[1] in TF_STATE_MUTATING:
            deny(f"`{prog} state {pos[1]}` rewrites state.")
        if sub == "workspace" and len(pos) > 1 and pos[1] in TF_WORKSPACE_MUTATING:
            deny(f"`{prog} workspace {pos[1]}` changes the backend.")
        if sub == "plan" and "-lock=false" not in args:
            deny(f"`{prog} plan` without -lock=false takes a state lock, which is a write. Use `{prog} plan -lock=false`.")
    elif prog == "aws":
        pos = positional(args, AWS_VALUE_FLAGS)
        if len(pos) < 2:
            return
        service, op = pos[0], pos[1]
        if service in ("configure", "help"):
            return
        if service == "s3":
            if op != "ls":
                deny(f"`aws s3 {op}` writes or moves objects.")
            return
        if op in AWS_READ_EXACT or op.startswith(AWS_READ_PREFIXES):
            return
        deny(f"`aws {service} {op}` is not a read-only operation.")
    elif prog in ("cdk", "sam", "kubectl"):
        pos = positional(args)
        sub = pos[0] if pos else ""
        table = {"cdk": CDK_MUTATING, "sam": SAM_MUTATING, "kubectl": KUBECTL_MUTATING}[prog]
        if sub in table:
            deny(f"`{prog} {sub}` changes cloud resources.")


def check_tokens(tok, depth, piped):
    """Recursively check one already-tokenised simple command.

    `piped` is True when this command is the receiving end of a `|` (its
    stdin comes from the previous stage of a pipeline). A single recursive
    design handles every wrapper shape (C1/C3) and every shell shape
    (bare program, -c string, positional script file, or nothing at all,
    piped/redirected or not - C4):

    - `eval ...`: recurse into the joined remainder.
    - A shell name found ANYWHERE in the tokens (not just tok[0], so any
      wrapper before it - sudo, nice, time, nohup, timeout N, env, FOO=bar,
      xargs -I{} - is transparently skipped) with a -c option: recurse into
      the command string it was handed.
    - The same shell with no -c: whatever follows its options is itself
      checked the same way, by recursing on it as a fresh token list - this
      is what lets `bash -x /path/to/terraform apply` still get caught, and
      what lets `bash scripts/check.sh` resolve to "nothing recognised" and
      stay allowed, without a separate special case for either.
    - The same shell with no -c and nothing usable following it (nothing at
      all, or a `<`/`<<...` redirection token): it will read the command
      from stdin, which cannot be analysed. Denied when that stdin comes
      from a pipe or an explicit redirection - never for a bare shell name
      sitting in an otherwise inert segment.
    - Otherwise, the first recognised terraform/aws/cdk/sam/kubectl token
      (again found at any position) is checked directly.
    """
    if depth > MAX_RECURSION or not tok:
        return
    head = tok[0].rsplit("/", 1)[-1].lower()
    if head == "eval":
        analyze(" ".join(tok[1:]), depth + 1)
        return
    idx, kind = find_first(tok)
    if idx is None:
        return
    if kind == "prog":
        handle_prog(tok, idx)
        return
    c_idx = find_c_arg(tok, idx)
    if c_idx is not None:
        analyze(tok[c_idx], depth + 1)
        return
    rest = tok[idx + 1:]
    if rest and not is_redirect(rest[0]):
        check_tokens(rest, depth + 1, piped=False)
        return
    if piped or (rest and is_redirect(rest[0])):
        deny(f"`{tok[idx]}` would read a command from stdin (pipe or redirection), which this hook cannot analyse. Run the command directly instead.")


def split_segments(text):
    """Split `text` on &&, ||, ;, |, newline, $( and ` , pairing each
    resulting segment with whether it directly follows a single `|` (i.e.
    receives stdin from a pipe, as opposed to ||/;/&&/newline/substitution,
    which don't)."""
    segments = []
    last = 0
    piped = False
    for m in SEGMENT_SPLIT.finditer(text):
        segments.append((text[last:m.start()], piped))
        piped = m.group() == "|"
        last = m.end()
    segments.append((text[last:], piped))
    return segments


def analyze(text, depth):
    for seg, piped in split_segments(text):
        check_tokens(tokens(seg.strip()), depth, piped)


def check_code(text, where):
    if BOTO_CALL.search(text) or BOTO_OP_STRING.search(text):
        if "boto3" in text or "call_boto3" in text or where == "run_script":
            deny(f"The {where} code calls a mutating AWS API.")


def strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for v in value.values():
            yield from strings(v)
    elif isinstance(value, list):
        for v in value:
            yield from strings(v)


def main():
    # Fail closed (C2): any unexpected input (non-JSON stdin, a non-dict
    # payload, a missing/malformed field) must still produce a deny decision
    # and exit 0, not an uncaught exception -> exit 1, which Claude Code
    # treats as a non-blocking hook error and lets the tool call proceed.
    try:
        data = json.load(sys.stdin)
        name = data.get("tool_name", "")
        tin = data.get("tool_input", {}) or {}
        if name == "Bash":
            cmd = tin.get("command", "")
            analyze(cmd, 0)
            check_code(cmd, "shell")
        elif "run_script" in name:
            for text in strings(tin):
                check_code(text, "run_script")
    except SystemExit:
        raise
    except Exception:
        deny("Could not verify this call is read-only (internal error in the read-only guard).")
    sys.exit(0)


if __name__ == "__main__":
    main()
