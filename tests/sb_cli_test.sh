#!/usr/bin/env bash
# Runs every second-brain unit test (tests/python/test_sb_*.py).
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
python3 -m unittest discover -s tests/python -p 'test_sb_*.py' -q
status=$?
if [ "$status" -eq 0 ]; then echo "  ok   second-brain unit tests"; else echo "  FAIL second-brain unit tests"; fi
exit $status
