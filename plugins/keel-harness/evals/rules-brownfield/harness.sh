#!/usr/bin/env bash
# Sourced by the rules-* scaffolds. install_harness copies the plugin's bundled build assets into the
# current repository exactly the way the build skill does, plus a minimal AGENTS.md and CLAUDE.md.
# Usage: install_harness [--typescript]   (run from the repository root)
install_harness() {
  local assets="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../skills/build/assets" && pwd)"
  mkdir -p scripts/lib scripts/sensors .agents/baselines
  cp "$assets/gate.sh" scripts/gate.sh
  cp "$assets/gate.env" .agents/gate.env
  cp "$assets/lib/baseline.sh" scripts/lib/baseline.sh
  if [ "${1:-}" = "--typescript" ]; then
    for s in typecheck lint tests; do cp "$assets/sensors/typescript/$s.sh" "scripts/sensors/$s.sh"; done
    cp "$assets/sensors/common/secrets.sh" scripts/sensors/secrets.sh
    printf '# measured_at: 2026-10-20 review_by: 2027-04-20\n' > .agents/baselines/lint.tsv
  fi
  chmod +x scripts/gate.sh scripts/sensors/*.sh 2>/dev/null || true
  cat > Makefile <<'MK'
.PHONY: bootstrap gate-fast gate-slow

bootstrap:
	npm install

gate-fast:
	@bash scripts/gate.sh fast

gate-slow:
	@bash scripts/gate.sh slow
MK
  cat > .agents/state.yml <<'YML'
schema_version: 2
installed_at: 2026-10-20
harness_review_by: 2027-04-20
mode: brownfield
layers: { bootstrap: installed, guides: installed, fast_gate: installed, slow_gate: not_installed, hook: not_installed, rules: not_installed }
not_installed:
  slow_gate: "no mutation or coverage tool configured"
  hook: "eval fixture drives the gate by hand"
  rules: "run /keel-harness:rules"
YML
  cat > AGENTS.md <<'MD'
# AGENTS.md — ledger
TypeScript / Node ledger service, npm. Last updated: 2026-10-20.

## Commands
| Purpose | Command | Pass signal |
| --- | --- | --- |
| Install and build | `make bootstrap` | exit 0 |
| Fast gate | `make gate-fast` | `gate: fast - PASSED` |
| Slow gate | `make gate-slow` | `gate: slow - PASSED` |

## Before you finish
Run `make gate-fast` and read it before you say you are done:
- Line 1 of each sensor is `id  class  status  summary`; fix every `fail`, top to bottom.
- Follow the `guidance:` block under a failure; it says what to do here and what not to do.
- Never edit a test, `.agents/baselines/` or `.agents/state.yml` to make the gate pass.
Before opening a pull request, also run `make gate-slow`.
MD
  printf '@AGENTS.md\n' > CLAUDE.md
  printf '.agents/last-run.log\n.agents/last-run-slow.log\n.agents/last-green\n.agents/last-seen\n.agents/last-fail\n.agents/.gate-lock/\n' >> .gitignore
}

# install_rule_sensors <id>...  copies rule sensors from the rules skill (slow ones into slow/)
install_rule_sensors() {
  local rassets="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../skills/rules/assets" && pwd)" id
  mkdir -p scripts/sensors/stoplists .agents/rules
  for id in "$@"; do cp "$rassets/sensors/$id.sh" "scripts/sensors/$id.sh"; done
  cp "$rassets/sensors/stoplists/pt.txt" scripts/sensors/stoplists/pt.txt
  chmod +x scripts/sensors/*.sh
}
