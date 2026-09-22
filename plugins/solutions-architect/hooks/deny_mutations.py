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


def strip_wrappers(tok):
    while tok and (re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", tok[0]) or tok[0] in ("sudo", "env", "time", "nice", "nohup", "command", "exec")):
        tok = tok[1:]
    return tok


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


def check_segment(segment):
    tok = strip_wrappers(tokens(segment.strip()))
    if not tok:
        return
    prog = tok[0].rsplit("/", 1)[-1]
    args = tok[1:]
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
    data = json.load(sys.stdin)
    name = data.get("tool_name", "")
    tin = data.get("tool_input", {}) or {}
    if name == "Bash":
        cmd = tin.get("command", "")
        for seg in SEGMENT_SPLIT.split(cmd):
            check_segment(seg)
        check_code(cmd, "shell")
    elif "run_script" in name:
        for text in strings(tin):
            check_code(text, "run_script")
    sys.exit(0)


if __name__ == "__main__":
    main()
