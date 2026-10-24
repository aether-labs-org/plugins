#!/usr/bin/env bash
# A scaffold can't drive the interactive `build` skill, so this case ships the
# harness as a fixture the same way gate-catches-defect does: lay down the same
# TypeScript repo build-typescript uses, overlay the pre-built harness fixture
# (Makefile, scripts/, .agents/ - already verified clean by gate-catches-defect),
# add an AGENTS.md of our own (the shared fixture ships none - each case that
# needs one writes it), then append 120 filler lines so exactly one of doctor's
# four conditions - AGENTS.md size - is broken. Commands and sensor tools
# are left untouched and clean, so only that one condition
# fires.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "$here/../build-typescript/scaffold.sh"

cp -r "$here/../gate-catches-defect/fixtures/harness/Makefile" \
      "$here/../gate-catches-defect/fixtures/harness/.agents" .

assets="$here/../../skills/build/assets"
mkdir -p scripts/lib scripts/sensors
cp "$assets/gate.sh" scripts/gate.sh
cp "$assets/gate.env" .agents/gate.env
cp "$assets/lib/baseline.sh" scripts/lib/baseline.sh
cp "$assets/lib/envparse.sh" scripts/lib/envparse.sh
for s in typecheck lint tests; do cp "$assets/sensors/typescript/$s.sh" "scripts/sensors/$s.sh"; done
cp "$assets/sensors/common/secrets.sh" scripts/sensors/secrets.sh
cp "$assets/sensors/common/guard.sh" scripts/sensors/guard.sh
chmod +x scripts/gate.sh scripts/sensors/*.sh

cat > AGENTS.md <<'MD'
# AGENTS.md — ledger
> Map/index for AI coding agents. Source of truth: `docs/`. Stack: TypeScript / Node. Last updated: 2026-09-20.

## Project Identity
- **Stack**: TypeScript, Node.js
- **Package manager / build**: npm
- **Entry points**: `src/posting.ts`, `src/config.ts`

---

## Computational Guides — feedforward you can rely on

### Build & run
```bash
make bootstrap      # npm install && npm run build
npm run build        # → dist/
```

---

## Computational Sensors — run these to verify your work
| Sensor     | Command          | Pass signal          |
| ---------- | ----------------- | --------------------- |
| Type check | `npm run build`   | `Found 0 errors`      |
| Lint       | `npm run lint`    | 0 problems reported   |
| Tests      | `npm test`        | all tests pass        |

---

## Quality Gates — Shift Quality Left
**Per step:**
```bash
make gate-fast
```

---

## Docs Index
| Topic | File |
| ----- | ---- |
| (none yet — no docs/ stubs installed) | |
MD

# Break condition 1 (AGENTS.md size) — and only that one; commands, sensor
# tools and model_baseline all stay clean. (A `yes | head` pipeline here would
# trip `pipefail`: `yes` is SIGPIPE-killed the moment `head` stops reading, and
# that non-zero exit aborts the script under `set -e`.)
for _ in $(seq 1 120); do printf -- '- filler pointer line\n'; done >> AGENTS.md
