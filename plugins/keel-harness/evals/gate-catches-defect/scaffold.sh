#!/usr/bin/env bash
# A scaffold can't drive the interactive `build` skill, so this case ships the
# harness as a committed fixture instead (fixtures/harness/, produced once by
# actually running `build` against the build-typescript scaffold - see
# plugins/keel-harness/evals/gate-catches-defect/fixtures/harness/).
#
# Steps: lay down the same TypeScript repo build-typescript uses, overlay the
# pre-built harness fixture, install dependencies, commit a clean baseline, then
# plant a single-line rounding regression so exactly one sensor (tests) fails.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "$here/../build-typescript/scaffold.sh"

cp -r "$here/fixtures/harness/Makefile" "$here/fixtures/harness/scripts" "$here/fixtures/harness/.agents" .

npm install --no-audit --no-fund --silent

# Plant the rounding regression from the Task 5 self-correction run: applyFee's
# test expects the 0.98 fee factor; changing it to 0.965 makes exactly the
# `tests` sensor fail while typecheck/lint/secrets stay green. Left uncommitted
# (like the harness files just copied in) so `scripts/gate.sh`'s SCOPE - files
# changed since the last commit - picks it up the same way a real edit would.
sed -i 's/cents \* 0.98/cents * 0.965/' src/posting.ts
