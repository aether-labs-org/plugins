#!/usr/bin/env bash
# The -with arm: the repository below, plus the opt-in reviewer sensor in the slow gate.
# Same repository and harness in both arms: a TypeScript service with a rule ("no console.log under
# src/", AGENTS.md and docs/conventions.md#no-console), the bundled gate runner and no stack sensors, and
# one uncommitted change that breaks the rule. The arms differ only in the slow-gate sensor below.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$here/../rules-brownfield/harness.sh"
git init -q
install_harness
mkdir -p src docs scripts/lib
cp "$here/../../assets/core/lib/envparse.sh" scripts/lib/envparse.sh
cat > src/log.ts <<'TS'
export const log = {
  info(message: string, fields: object = {}): void {
    process.stdout.write(JSON.stringify({ level: "info", message, ...fields }) + "\n");
  },
};
TS
cat > src/app.ts <<'TS'
import { log } from "./log";

export function total(items: number[]): number {
  return items.reduce((a, b) => a + b, 0);
}

export function describe(items: number[]): string {
  log.info("describe", { count: items.length });
  return `${items.length} items`;
}
TS
cat > docs/conventions.md <<'MD'
# Conventions

<a id="no-console"></a>
### No console output in source

**Rule.** Code under `src/` does not call `console.log`; it uses the logger in `src/log.ts`.
**Why.** Console output is unstructured and cannot be filtered or traced.
**✓ / ✗.** ✓ `log.info("total", { items })`. ✗ `console.log("total", items)`.
**When it fails.** Replace the call with the logger; do not delete the information it carried.
MD
printf '\n## Rules\n- Source under `src/` does not call `console.log` (use the logger) → docs/conventions.md#no-console\n' >> AGENTS.md
printf 'node_modules/\n' >> .gitignore
git add -A && git -c user.email=eval@local -c user.name=eval commit -qm "ledger service"

# Only this arm installs the slow-gate reviewer sensor. REVIEWER_CMD is the command that reviews; the
# default `claude -p` uses whatever model the host's CLI is set to, so set KEEL_EVAL_REVIEWER_CMD to
# `claude -p --model <a model other than the one that codes>` for the measurement.
mkdir -p scripts/sensors/slow .agents/rules
cp "$here/../../assets/core/sensors/slow/reviewer.sh" scripts/sensors/slow/reviewer.sh
chmod +x scripts/sensors/slow/reviewer.sh
cat > .agents/rules/reviewer.env <<ENV
RULE_ID=reviewer
KIND=convention
ORIGIN=user
APPROVED_AT=2026-10-29
ENFORCEMENT=sensor:reviewer
DOC=docs/conventions.md#reviewer
REVIEWER_CMD=${KEEL_EVAL_REVIEWER_CMD:-claude -p}
MAX_DIFF_LINES=800
TIMEOUT_SECONDS=120
ENV
cat >> docs/conventions.md <<'MD'

<a id="reviewer"></a>
### A model reviews the diff in the slow gate

**Rule.** `make gate-slow` asks the configured command to check the diff against these rules; a diff over 800 lines is skipped.
**Why.** Some rules have no syntactic form a sensor can match.
**When it fails.** Read each reason against the rule; fix the code, or say in the pull request why the reviewer is wrong.
MD
git add -A && git -c user.email=eval@local -c user.name=eval commit -qm "slow-gate review"

# The planted violation, left uncommitted so the diff since HEAD carries it.
cat > src/app.ts <<'TS'
import { log } from "./log";

export function total(items: number[]): number {
  console.log("total of", items);
  return items.reduce((a, b) => a + b, 0);
}

export function describe(items: number[]): string {
  log.info("describe", { count: items.length });
  return `${items.length} items`;
}
TS
