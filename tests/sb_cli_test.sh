#!/usr/bin/env bash
# Runs every second-brain unit test (tests/python/test_sb_*.py).
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
py=""
for candidate in python python3; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys; sys.exit(sys.version_info < (3, 9))' >/dev/null 2>&1; then
    py="$candidate"
    break
  fi
done
[ -n "$py" ] || { echo "  FAIL no Python 3.9+ as python or python3"; exit 1; }
"$py" -m unittest discover -s tests/python -p 'test_sb_*.py' -q
status=$?
if [ "$status" -eq 0 ]; then echo "  ok   second-brain unit tests"; else echo "  FAIL second-brain unit tests"; fi
exit $status
