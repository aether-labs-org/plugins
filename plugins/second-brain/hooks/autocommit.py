#!/usr/bin/env python3
"""SessionEnd hook entry point: local auto-commit. Always exits 0; status goes to stderr."""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "lib"))


def main():
    try:
        try:
            cwd = json.load(sys.stdin).get("cwd") or os.getcwd()
        except Exception:
            cwd = os.getcwd()
        from sb.autocommit import run
        status = run(cwd)
        if status.startswith("committed"):
            print("second-brain: " + status, file=sys.stderr)
    except Exception as exc:
        print("second-brain: auto-commit error: %s" % exc, file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
