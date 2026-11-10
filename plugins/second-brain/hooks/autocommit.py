"""SessionEnd hook entry point: local auto-commit. Always exits 0; status goes to stderr."""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "lib"))


def main():
    try:
        try:
            event = json.load(sys.stdin)
            cwd = event.get("cwd") or os.getcwd()
            session_id = str(event.get("session_id") or "")
        except Exception:
            cwd, session_id = os.getcwd(), ""
        from sb.autocommit import run
        status = run(cwd, session_id=session_id)
        if status.startswith("committed"):
            print("second-brain: " + status, file=sys.stderr)
    except Exception as exc:
        print("second-brain: auto-commit error: %s" % exc, file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
