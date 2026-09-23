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


def skip_shell_opts(tok, idx):
    """Skip every option token after the shell name at tok[idx]: `-o <opt>`
    (consumes two tokens - the only flag that takes a value), and any other
    token starting with `-` (short clusters such as -e, -x, -s, -l, -c, ...,
    long options, and `--` itself) - all skipped alike, and none of them
    ends option-skipping. A real shell's exact getopt grammar (where `--`
    stops option parsing and `-s --  --yes` passes `--yes` as a positional
    parameter, not a filename) isn't safe to replicate here: this hook only
    needs to tell "a script FILE was named" from "nothing but flags was
    given, so the shell reads stdin", and treating every dash-prefixed token
    as a flag - never as a filename - is the conservative, correct call for
    a security gate (`bash -s -- --yes` must not be read as "run file
    --yes").

    Returns (saw_c, first_non_option_index_or_None). saw_c is True if any
    skipped short-option cluster contained "c" (bash/sh/zsh/dash/ksh's
    "run this string" flag; long options are never treated as containing
    it). first_non_option_index is the index of the first token that isn't
    itself an option - the command string when saw_c is True, the script
    file (or a redirect token) otherwise - or None when every remaining
    token was consumed as an option, meaning the shell reads stdin.
    """
    saw_c = False
    i = idx + 1
    while i < len(tok):
        t = tok[i]
        if t == "-o":
            i += 2
            continue
        if t.startswith("-") and t != "-":
            if not t.startswith("--") and "c" in t[1:]:
                saw_c = True
            i += 1
            continue
        break
    return saw_c, (i if i < len(tok) else None)


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
    stdin comes from the previous stage of a pipeline). One semantic rule
    handles every wrapper shape (C1/C3) and every shell shape (C4):

    - `eval ...`: recurse into the joined remainder.
    - A shell name found ANYWHERE in the tokens (not just tok[0], so any
      wrapper before it - sudo, nice, time, nohup, timeout N, env, FOO=bar,
      xargs -I{} - is transparently skipped): skip its option tokens
      (`skip_shell_opts`).
      - If a -c option was seen: the first non-option token is the command
        string it was handed - recurse into it.
      - Else, if a non-option token remains and it is not a redirect
        (`<`/`<<...`): it is a script FILE argument - allowed, and whatever
        follows it are the script's own arguments, not commands, so nothing
        more to check.
      - Else (nothing non-option remains, or it's a redirect token): this
        shell reads the command from stdin, which cannot be analysed.
        Denied only when that stdin is observably fed by something - a pipe
        (`piped`), or an explicit `<`/`<<...` redirect in this segment.
    - Otherwise, the first recognised terraform/aws/cdk/sam/kubectl token
      (found at any position) is checked directly.
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
    saw_c, file_idx = skip_shell_opts(tok, idx)
    if saw_c:
        if file_idx is not None:
            analyze(tok[file_idx], depth + 1)
        return
    if file_idx is not None and not is_redirect(tok[file_idx]):
        return
    if piped or (file_idx is not None and is_redirect(tok[file_idx])):
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
