#!/usr/bin/env bash
# Runs every *_test.sh in this directory. Exit 0 only if all pass.
set -uo pipefail
# A git hook (pre-push -> the slow gate -> this suite) exports GIT_DIR, GIT_INDEX_FILE ... and every git command the suites
# run in a temporary directory would act on the repository being pushed. Clear them before anything runs.
# shellcheck disable=SC2046
unset $(git rev-parse --local-env-vars 2>/dev/null) BMAX_ROOT
cd "$(dirname "$0")"
status=0
for t in *_test.sh; do
  echo "== $t"
  bash "$t" || status=1
done
exit $status
