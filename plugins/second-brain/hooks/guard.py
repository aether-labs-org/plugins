#!/usr/bin/env python3
"""PreToolUse hook entry point. Fail-closed inside a vault: any internal failure exits 2 with
the error on stderr. Outside a vault it stays silent (exit 0)."""
import json
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "lib"))
MARKER = ".second-brain.json"


def in_vault(start):
    """Marker walk with no dependency on the sb package, which may be what failed."""
    here = os.path.realpath(start)
    while True:
        if os.path.isfile(os.path.join(here, MARKER)):
            return True
        parent = os.path.dirname(here)
        if parent == here:
            return False
        here = parent


def starts(event, cwd):
    """Directories that may place the call in a vault: the cwd and the paths it names."""
    found = [cwd]
    if not isinstance(event, dict):
        return found
    if isinstance(event.get("cwd"), str) and event["cwd"]:
        found.append(event["cwd"])
    tool_input = event.get("tool_input")
    if isinstance(tool_input, dict):
        base = found[-1]
        for key in ("file_path", "notebook_path"):
            path = tool_input.get(key)
            if isinstance(path, str) and path:
                found.append(os.path.dirname(os.path.join(base, os.path.expanduser(path))))
        command = tool_input.get("command")
        if isinstance(command, str):
            found.extend(os.path.expanduser(m) for m in re.findall(r"~?/[^\s'\"<>|;&()`$]+", command)[:8])
    return found


def main():
    event = None
    try:
        event = json.load(sys.stdin)
        from sb.guard import decide
        decision = decide(event, os.getcwd())
    except Exception as exc:  # noqa: BLE001 - every failure is handled the same way
        try:
            inside = any(in_vault(s) for s in starts(event, os.getcwd()))
        except Exception:  # noqa: BLE001
            inside = True              # cannot tell: stay closed
        if inside:
            print("second-brain guard error: %s" % exc, file=sys.stderr)
            return 2
        return 0
    if decision:
        json.dump(decision, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
