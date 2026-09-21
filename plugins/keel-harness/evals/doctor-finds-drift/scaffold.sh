#!/usr/bin/env bash
# A scaffold can't drive the interactive `build` skill, so this case ships the
# harness as a fixture the same way gate-catches-defect does: lay down the same
# TypeScript repo build-typescript uses, overlay the pre-built harness fixture
# (Makefile, scripts/, .agents/ - already verified clean by gate-catches-defect),
# add an AGENTS.md of our own (the shared fixture ships none - each case that
# needs one writes it), then append 120 filler lines so exactly one of doctor's
# four conditions - AGENTS.md size - is broken. Commands, sensor tools and
# model_baseline are all left untouched and clean, so only that one condition
# fires.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "$here/../build-typescript/scaffold.sh"

cp -r "$here/../gate-catches-defect/fixtures/harness/Makefile" \
      "$here/../gate-catches-defect/fixtures/harness/scripts" \
      "$here/../gate-catches-defect/fixtures/harness/.agents" .

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
