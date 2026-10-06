#!/usr/bin/env python3
"""PostToolUse hook entry point. Any internal failure is silent (exit 0)."""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "lib"))


def main():
    try:
        event = json.load(sys.stdin)
        from sb.postcheck import check
        output = check(event, os.getcwd())
    except Exception:
        return 0
    if output:
        json.dump(output, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
