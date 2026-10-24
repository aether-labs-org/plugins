#!/usr/bin/env bash
# A scaffold can't drive the interactive `build` skill, so this case ships the
# harness as a committed fixture instead (fixtures/harness/, produced once by
# actually running `build` against the build-typescript scaffold - see
# plugins/keel-harness/evals/gate-catches-defect/fixtures/harness/).
#
# Steps: build-typescript/scaffold.sh lays down the repo and commits a clean
# baseline itself; this script then overlays the harness fixture (metadata + Makefile) and the bundled assets and
# plants a single-line rounding regression on top, both left uncommitted so
# scripts/gate.sh's SCOPE (changes since the last commit) picks them up.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "$here/../build-typescript/scaffold.sh"

cp -r "$here/fixtures/harness/Makefile" "$here/fixtures/harness/.agents" .

# The gate runner, the baseline library and the TypeScript/secrets sensors are the plugin's own
# bundled assets (the same files `build` copies), not a second copy kept in this fixture.
assets="$here/../../assets/core"
mkdir -p scripts/lib scripts/sensors
cp "$assets/gate.sh" scripts/gate.sh
cp "$assets/gate.env" .agents/gate.env
cp "$assets/lib/baseline.sh" scripts/lib/baseline.sh
cp "$assets/lib/envparse.sh" scripts/lib/envparse.sh
for s in typecheck lint tests; do cp "$assets/sensors/typescript/$s.sh" "scripts/sensors/$s.sh"; done
cp "$assets/sensors/common/secrets.sh" scripts/sensors/secrets.sh
cp "$assets/sensors/common/guard.sh" scripts/sensors/guard.sh
chmod +x scripts/gate.sh scripts/sensors/*.sh

npm install --no-audit --no-fund --silent

# Plant the rounding regression from the Task 5 self-correction run: applyFee's
# test expects the 0.98 fee factor; changing it to 0.965 makes exactly the
# `tests` sensor fail while typecheck/lint/secrets stay green. Left uncommitted
# (like the harness files just copied in) so `scripts/gate.sh`'s SCOPE - files
# changed since the last commit - picks it up the same way a real edit would.
sed -i 's/cents \* 0.98/cents * 0.965/' src/posting.ts
