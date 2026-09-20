#!/usr/bin/env bash
# Runs every *_test.sh in this directory. Exit 0 only if all pass.
set -uo pipefail
cd "$(dirname "$0")"
status=0
for t in *_test.sh; do
  echo "== $t"
  bash "$t" || status=1
done
exit $status
