#!/usr/bin/env python3
"""PreToolUse hook entry point. Any internal failure allows the call (exit 0, no output)."""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "lib"))


def main():
    try:
        event = json.load(sys.stdin)
        from sb.guard import decide
        decision = decide(event, os.getcwd())
    except Exception:
        return 0
    if decision:
        json.dump(decision, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
