#!/usr/bin/env bash
set -uo pipefail
qgrep() { grep "$@" >/dev/null; } # reads all its input: `| grep -q` can SIGPIPE the writer under pipefail
. "$(dirname "$0")/keel_helpers.sh"
HC="$KEEL/assets/core/harness-check.sh"
[ -f "$HC" ]; check "harness-check.sh exists" $?

# mkclean -> a clean harness repo (committed)
mkclean() {
  local r; r="$(new_repo)"
  install_asset "$r" assets/core/harness-check.sh scripts/harness-check.sh
  install_asset "$r" assets/core/gate.sh scripts/gate.sh
  install_asset "$r" assets/core/lib/baseline.sh scripts/lib/baseline.sh
  install_asset "$r" assets/core/lib/envparse.sh scripts/lib/envparse.sh
  install_asset "$r" assets/core/sensors/common/guard.sh scripts/sensors/guard.sh
  install_asset "$r" assets/adapters/claude/claude-stop.sh scripts/hooks/claude-stop.sh
  mkdir -p "$r/.agents/baselines" "$r/.agents/rules" "$r/.claude" "$r/docs/decisions" "$r/scripts/sensors/slow" "$r/src"
  cp "$KEEL/assets/core/gate.env" "$r/.agents/gate.env"
  cp "$KEEL/assets/adapters/claude/settings-stop.json" "$r/.claude/settings.json"
  printf '.agents/run/\n' > "$r/.gitignore"
  cat > "$r/Makefile" <<'MK'
bootstrap:
	npm install

gate-fast:
	@bash scripts/gate.sh fast

gate-slow:
	@bash scripts/gate.sh slow

harness-check:
	@bash scripts/harness-check.sh
MK
  printf '{ "scripts": { "build": "tsc", "test": "vitest run" } }\n' > "$r/package.json"
  cat > "$r/scripts/sensors/lint.sh" <<'S'
#!/usr/bin/env bash
# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.
id=lint
class=heuristic
printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "0 problems"
S
  chmod +x "$r/scripts/sensors/lint.sh"
  cat > "$r/AGENTS.md" <<'MD'
# AGENTS.md — demo
Demo repo. Last updated: 2026-10-20.

## Commands
| Purpose | Command | Pass signal |
| --- | --- | --- |
| Install | `make bootstrap` | exit 0 |
| Fast gate | `make gate-fast` | `gate: fast - PASSED` |
| Slow gate | `make gate-slow` | `gate: slow - PASSED` |
| Build | `npm run build` | exit 0 |
| Validate | `make harness-check` | `harness is clean` |

## Before you finish
Run `make gate-fast` and read it.
MD
  printf '@AGENTS.md\n' > "$r/CLAUDE.md"
  cat > "$r/.agents/state.yml" <<'Y'
schema_version: 2
installed_at: 2026-10-20
harness_review_by: 2027-04-20
mode: brownfield
layers: { bootstrap: installed, guides: installed, fast_gate: installed, slow_gate: not_installed, hook: installed, rules: not_installed }
not_installed: {}
Y
  echo 1 > "$r/src/a.ts"
  (cd "$r" && git add -A && git commit -q -m h)
  printf '%s\n' "$r"
}
hc() { out="$(cd "$1" && env "${@:2}" bash scripts/harness-check.sh 2>&1)"; rc=$?; }
warns() { printf '%s\n' "$out" | grep -c '^warn	'; }
only() { # only <id> <file-substring>: exactly one warn, with that id and file
  [ "$rc" -eq 1 ] && [ "$(warns)" = 1 ] && printf '%s\n' "$out" | qgrep "^warn	$1	[^	]*$2"
}
commit() { (cd "$1" && git add -A && git commit -q -m c); }

r="$(mkclean)"
hc "$r"; [ $rc -eq 0 ] && printf '%s\n' "$out" | tail -1 | qgrep -x 'harness-check: harness is clean'; check "clean fixture: rc 0 and 'harness is clean'" $?
before="$(cd "$r" && git status --porcelain)"; hc "$r"; [ "$before" = "$(cd "$r" && git status --porcelain)" ]; check "read-only: git status unchanged" $?

# no state
r2="$(mkclean)"; rm "$r2/.agents/state.yml"; hc "$r2"; [ $rc -eq 2 ] && printf '%s\n' "$out" | qgrep 'harness-check: no harness installed - run /keel-harness:build'; check "no state -> rc 2" $?

# agents-size
r="$(mkclean)"; for i in $(seq 1 100); do echo "- line $i" >> "$r/AGENTS.md"; done; hc "$r"; only agents-size AGENTS.md; check "agents-size" $?
# nested AGENTS.md
r="$(mkclean)"; mkdir -p "$r/src/api"; for i in $(seq 1 101); do echo "- line $i"; done > "$r/src/api/AGENTS.md"; commit "$r"; hc "$r"; only agents-size src/api/AGENTS.md; check "agents-size on a nested AGENTS.md" $?

# stale-command
r="$(mkclean)"; printf '| Lint | `make lint-all` | exit 0 |\n' >> "$r/AGENTS.md"; hc "$r"; only stale-command AGENTS.md && printf '%s\n' "$out" | qgrep 'make lint-all'; check "stale-command: missing make target" $?
r="$(mkclean)"; printf '| Dev | `npm run dev` | up |\n' >> "$r/AGENTS.md"; hc "$r"; only stale-command AGENTS.md; check "stale-command: missing npm script" $?
r="$(mkclean)"; printf '| Dev | `pnpm build` | ok |\n| Gradle | `./gradlew test` | ok |\n' >> "$r/AGENTS.md"; hc "$r"; [ "$(warns)" = 1 ] && printf '%s\n' "$out" | qgrep 'gradlew'; check "stale-command: pnpm script exists, ./gradlew missing" $?
r="$(mkclean)"; printf '| Py | `.venv/bin/pytest` | ok |\n| uv | `uv run nonexistent-tool-xyz` | ok |\n' >> "$r/AGENTS.md"; hc "$r"; [ "$(warns)" = 2 ]; check "stale-command: .venv/bin and uv run" $?
r="$(mkclean)"; printf '| Ok | `make bootstrap && make gate-fast` | ok |\n' >> "$r/AGENTS.md"; hc "$r"; [ $rc -eq 0 ]; check "stale-command: chained existing commands are fine" $?

# agents-not-loaded
r="$(mkclean)"; printf '# Notes\nuse npm\n' > "$r/CLAUDE.md"; hc "$r"; only agents-not-loaded CLAUDE.md; check "agents-not-loaded: CLAUDE.md" $?
r="$(mkclean)"; rm "$r/CLAUDE.md"; mkdir -p "$r/.claude"; printf '# Notes\n' > "$r/.claude/CLAUDE.md"; hc "$r"; only agents-not-loaded '.claude/CLAUDE.md'; check "agents-not-loaded: .claude/CLAUDE.md" $?

# dangling-pointer
r="$(mkclean)"; printf '\n## Rules\n- Files stay small → docs/conventions.md#file-size\n' >> "$r/AGENTS.md"; hc "$r"; only dangling-pointer AGENTS.md; check "dangling-pointer: target file missing" $?
printf '# Conventions\n' > "$r/docs/conventions.md"; hc "$r"; only dangling-pointer AGENTS.md; check "dangling-pointer: anchor missing" $?
printf '# Conventions\n<a id="file-size"></a>\n### Small\n' > "$r/docs/conventions.md"; hc "$r"; [ $rc -eq 0 ]; check "dangling-pointer: file and anchor present -> clean" $?
r="$(mkclean)"; printf '# Conventions\n\nTODO\n' > "$r/docs/conventions.md"; printf '\n- See → docs/conventions.md\n' >> "$r/AGENTS.md"; hc "$r"; only dangling-pointer AGENTS.md; check "dangling-pointer: TODO stub target" $?
r="$(mkclean)"; printf '\n- See -> docs/missing.md\n' >> "$r/AGENTS.md"; hc "$r"; only dangling-pointer AGENTS.md; check "dangling-pointer: an ASCII -> pointer is checked too" $?

# hook-missing
r="$(mkclean)"; rm "$r/.claude/settings.json"; hc "$r"; only hook-missing settings.json; check "hook-missing: no settings" $?
r="$(mkclean)"; chmod -x "$r/scripts/hooks/claude-stop.sh"; hc "$r"; only hook-missing ''; check "hook-missing: script not executable" $?
r="$(mkclean)"; printf '{ "hooks": { "PostToolUse": [] } }\n' > "$r/.claude/settings.json"; hc "$r"; only hook-missing settings.json; check "hook-missing: no Stop entry" $?
r="$(mkclean)"; sed -i 's/hook: installed/hook: not_installed/' "$r/.agents/state.yml"; rm "$r/.claude/settings.json"; hc "$r"; [ $rc -eq 0 ]; check "hook-missing: skipped when the hook layer was declined" $?

# run-state
r="$(mkclean)"; printf 'x\n' > "$r/.agents/last-green"; hc "$r"; only run-state .agents; check "run-state: v0.2 run state outside .agents/run/" $?
r="$(mkclean)"; : > "$r/.gitignore"; commit "$r"; hc "$r"; only run-state .gitignore; check "run-state: .agents/run/ not ignored" $?
r="$(mkclean)"; mkdir -p "$r/.agents/run"; printf 'x\n' > "$r/.agents/run/last-green"; hc "$r"; [ $rc -eq 0 ]; check "run-state: ignored .agents/run/ is clean" $?

# enforcement-drift
r="$(mkclean)"; sed -i 's/rules: not_installed }/rules: not_installed, ci: installed }/' "$r/.agents/state.yml"; commit "$r"; hc "$r"; only enforcement-drift .github/workflows; check "enforcement-drift: ci installed, no workflow runs the gate" $?
r="$(mkclean)"; sed -i 's/rules: not_installed }/rules: not_installed, ci: installed }/' "$r/.agents/state.yml"; mkdir -p "$r/.github/workflows"; cp "$KEEL/assets/core/ci/keel.yml" "$r/.github/workflows/keel.yml"; commit "$r"; hc "$r"; [ $rc -eq 0 ]; check "enforcement-drift: keel.yml installed is clean" $?
r="$(mkclean)"; sed -i 's/rules: not_installed }/rules: not_installed, precommit: installed }/' "$r/.agents/state.yml"; printf 'pre-commit:\n  commands:\n    lint:\n      run: npx eslint .\n' > "$r/lefthook.yml"; commit "$r"; hc "$r"; only enforcement-drift state.yml; check "enforcement-drift: precommit installed, hook lost the gate" $?
r="$(mkclean)"; sed -i 's/rules: not_installed }/rules: not_installed, precommit: installed }/' "$r/.agents/state.yml"; cp "$KEEL/assets/core/precommit/lefthook.yml" "$r/lefthook.yml"; commit "$r"; hc "$r"; [ $rc -eq 0 ]; check "enforcement-drift: lefthook entry is clean" $?
r="$(mkclean)"; sed -i 's/rules: not_installed }/rules: not_installed, ci: not_installed, precommit: not_installed }/' "$r/.agents/state.yml"; commit "$r"; hc "$r"; [ $rc -eq 0 ]; check "enforcement-drift: declined layers are not checked" $?

# protect-missing (F3c-1: the authority layer)
mkauth() { # mkauth -> a clean harness with the authority layer installed
  local r; r="$(mkclean)"
  sed -i 's/rules: not_installed }/rules: not_installed, authority: installed }/' "$r/.agents/state.yml"
  install_asset "$r" assets/adapters/claude/claude-protect.sh scripts/hooks/claude-protect.sh
  cp "$KEEL/assets/core/consequence.yml" "$r/.agents/consequence.yml"
  printf '{ "hooks": { "Stop": [ { "hooks": [ { "type": "command", "command": "\\"${CLAUDE_PROJECT_DIR}\\"/scripts/hooks/claude-stop.sh" } ] } ], "PreToolUse": [ { "matcher": "Write|Edit|NotebookEdit", "hooks": [ { "type": "command", "command": "\\"${CLAUDE_PROJECT_DIR}\\"/scripts/hooks/claude-protect.sh", "timeout": 10 } ] } ] } }\n' > "$r/.claude/settings.json"
  commit "$r"
  printf '%s\n' "$r"
}
r="$(mkauth)"; hc "$r"; [ $rc -eq 0 ]; check "protect-missing: a complete authority layer is clean" $?
r="$(mkauth)"; rm "$r/.agents/consequence.yml"; commit "$r"; hc "$r"; only protect-missing claude-protect.sh && printf '%s\n' "$out" | qgrep 'consequence.yml'; check "protect-missing: no consequence map" $?
r="$(mkauth)"; rm "$r/scripts/hooks/claude-protect.sh"; commit "$r"; hc "$r"; only protect-missing claude-protect.sh; check "protect-missing: no hook script" $?
r="$(mkauth)"; chmod -x "$r/scripts/hooks/claude-protect.sh"; hc "$r"; only protect-missing claude-protect.sh; check "protect-missing: hook script not executable" $?
r="$(mkauth)"; cp "$KEEL/assets/adapters/claude/settings-stop.json" "$r/.claude/settings.json"; commit "$r"; hc "$r"; only protect-missing claude-protect.sh; check "protect-missing: settings.json has no PreToolUse entry for it" $?
r="$(mkauth)"; rm "$r/.claude/settings.json"; hc "$r"; printf '%s\n' "$out" | grep -c '^warn	protect-missing	' | qgrep -x 1; check "protect-missing: no settings.json -> exactly one protect-missing warning" $?
r="$(mkauth)"; rm "$r/.agents/consequence.yml" "$r/scripts/hooks/claude-protect.sh"; commit "$r"; hc "$r"; [ "$(printf '%s\n' "$out" | grep -c '^warn	protect-missing	')" = 1 ]; check "protect-missing: several things gone is still one warning" $?
r="$(mkclean)"; hc "$r"; [ $rc -eq 0 ]; check "protect-missing: a harness without the authority key is not checked" $?
r="$(mkclean)"; sed -i 's/rules: not_installed }/rules: not_installed, authority: not_installed }/' "$r/.agents/state.yml"; commit "$r"; hc "$r"; [ $rc -eq 0 ]; check "protect-missing: authority: not_installed is not checked" $?

# guard-missing
r="$(mkclean)"; rm "$r/scripts/sensors/guard.sh"; commit "$r"; hc "$r"; only guard-missing scripts/sensors/guard.sh; check "guard-missing: no guard sensor" $?
r="$(mkclean)"; rm "$r/scripts/lib/envparse.sh"; commit "$r"; hc "$r"; printf '%s\n' "$out" | qgrep '^warn	guard-missing	'; check "guard-missing: no envparse lib" $?

# sensor-malformed
r="$(mkclean)"; sed -i 's/^id=lint/id=other/' "$r/scripts/sensors/lint.sh"; hc "$r"; only sensor-malformed scripts/sensors/lint.sh; check "sensor-malformed: id differs from file name" $?
r="$(mkclean)"; sed -i 's/^class=heuristic/class=fuzzy/' "$r/scripts/sensors/lint.sh"; hc "$r"; only sensor-malformed lint.sh; check "sensor-malformed: bad class" $?
r="$(mkclean)"; chmod -x "$r/scripts/sensors/lint.sh"; hc "$r"; only sensor-malformed lint.sh; check "sensor-malformed: not executable" $?
r="$(mkclean)"; cp "$r/scripts/sensors/lint.sh" "$r/scripts/sensors/_helper.sh"; chmod -x "$r/scripts/sensors/_helper.sh"; echo x > "$r/scripts/sensors/README.md"; commit "$r"; hc "$r"; [ $rc -eq 0 ]; check "sensor-malformed: _helper.sh and README.md are ignored" $?

# two broken conditions -> two lines
r="$(mkclean)"; printf '| X | `make nope` | x |\n' >> "$r/AGENTS.md"; printf 'nothing\n' > "$r/CLAUDE.md"; hc "$r"; [ $rc -eq 1 ] && [ "$(warns)" = 2 ] && printf '%s\n' "$out" | tail -1 | qgrep -x 'harness-check: 2 warning(s)'; check "two broken conditions -> two warn lines and a count" $?
printf '%s\n' "$out" | grep '^warn' | head -1 | awk -F'\t' 'NF == 5 { ok = 1 } END { exit !ok }'; check "warn line has 5 tab-separated fields" $?
# ================= Task 22: rule and baseline checks
addrule() { # addrule REPO -> a consistent rule, sensor, doc and baseline (committed)
  local r="$1"
  cat > "$r/scripts/sensors/file-size.sh" <<'S'
#!/usr/bin/env bash
# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.
id=file-size
class=heuristic
if [ "${KEEL_MEASURE:-}" = 1 ]; then printf '# measured_at: 2026-10-20 review_by: 2027-04-20\nsrc/a.ts\t%s\n' "${MEASURED:-3}"; exit 0; fi
printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "ok"
S
  chmod +x "$r/scripts/sensors/file-size.sh"
  cat > "$r/.agents/rules/file-size.env" <<'E'
# Managed by keel-harness - see .agents/README.md
RULE_ID=file-size
KIND=metric
ORIGIN=proposed
APPROVED_AT=2026-10-20
ENFORCEMENT=sensor:file-size
DOC=docs/conventions.md#file-size
DECISION=docs/decisions/0003-file-size-limit.md
PLAN=.agents/plans/2026-10-20-file-size.md
LIMIT=300
INCLUDE='src'
E
  printf '# 3. File size\n' > "$r/docs/decisions/0003-file-size-limit.md"
  cat > "$r/docs/conventions.md" <<'D'
# Conventions

<a id="file-size"></a>
### Source files stay under 300 lines

**Rule.** Source files under `src/` have at most 300 lines.
**Why.** Because.
D
  printf '# measured_at: 2026-10-20 review_by: 2027-04-20\nsrc/a.ts\t3\n' > "$r/.agents/baselines/file-size.tsv"
  (cd "$r" && git add -A && git commit -q -m rule)
}
r="$(mkclean)"; addrule "$r"; hc "$r"; [ $rc -eq 0 ]; check "consistent rule (missing PLAN file) -> clean" $?

r="$(mkclean)"; addrule "$r"; sed -i '/^KIND=/d' "$r/.agents/rules/file-size.env"; hc "$r"; only rule-inconsistent file-size.env; check "rule-inconsistent: missing KIND" $?
r="$(mkclean)"; addrule "$r"; rm "$r/docs/conventions.md"; hc "$r"; only rule-inconsistent file-size.env; check "rule-inconsistent: DOC file missing" $?
r="$(mkclean)"; addrule "$r"; sed -i 's/<a id="file-size"><\/a>//' "$r/docs/conventions.md"; hc "$r"; only rule-inconsistent file-size.env; check "rule-inconsistent: anchor missing" $?
r="$(mkclean)"; addrule "$r"; rm "$r/scripts/sensors/file-size.sh"; hc "$r"; [ "$(warns)" -ge 1 ] && printf '%s\n' "$out" | qgrep '^warn	rule-inconsistent'; check "rule-inconsistent: sensor file missing" $?
r="$(mkclean)"; addrule "$r"; rm "$r/docs/decisions/0003-file-size-limit.md"; hc "$r"; only rule-inconsistent file-size.env; check "rule-inconsistent: DECISION file missing" $?
r="$(mkclean)"; addrule "$r"; sed -i 's/300 lines/200 lines/' "$r/docs/conventions.md"; hc "$r"; only rule-inconsistent file-size.env && printf '%s\n' "$out" | qgrep 'LIMIT=300'; check "rule-inconsistent: numeric parameter absent from the section" $?
r="$(mkclean)"; addrule "$r"; mkdir -p "$r/scripts/sensors/slow"; mv "$r/scripts/sensors/file-size.sh" "$r/scripts/sensors/slow/file-size.sh"; hc "$r"; [ $rc -eq 0 ]; check "rule-inconsistent: a slow sensor satisfies sensor:<id>" $?
r="$(mkclean)"; addrule "$r"; sed -i 's/^ENFORCEMENT=.*/ENFORCEMENT=inferential/' "$r/.agents/rules/file-size.env"; rm "$r/scripts/sensors/file-size.sh" "$r/.agents/baselines/file-size.tsv"; hc "$r"; [ $rc -eq 0 ]; check "rule-inconsistent: inferential rules need no sensor" $?

r="$(mkclean)"; mkdir -p "$r/docs"; seq 1 301 | sed 's/.*/x/' > "$r/docs/testing.md"; commit "$r"; hc "$r"; only topic-size docs/testing.md; check "topic-size" $?

# codemap-stale (F2d, D42): a backticked path in the "## Code map" of docs/architecture.md that no longer exists
cm() { # cm <repo> <body of docs/architecture.md>
  mkdir -p "$1/docs/api" "$1/docs/domain"; : > "$1/docs/api/.keep"; : > "$1/docs/domain/.keep"
  printf '%s\n' "$2" > "$1/docs/architecture.md"; commit "$1"
}
r="$(mkclean)"; cm "$r" '# Architecture

## Code map

How the code is shaped.

- `src/` — the source
- `docs/api/` — the API notes
- `src/gone/` — removed last month

## Invariants
- `src/never-existed/` is only cited outside the Code map'
hc "$r"; only codemap-stale docs/architecture.md && printf '%s\n' "$out" | qgrep 'src/gone/' && printf '%s\n' "$out" | qgrep 'update the Code map in docs/architecture.md (rules)'; check "codemap-stale: a missing path warns, with the fix" $?
printf '%s\n' "$out" | qgrep 'never-existed'; [ $? -ne 0 ]; check "codemap-stale: only the Code map section is read" $?
r="$(mkclean)"; cm "$r" '# Architecture

## Code map
- `src/` — the source
- `docs/api/` — the API notes
- `docs/domain/` — the domain notes
- `scripts/gate.sh` — the gate
- `src/a.ts:1` — a file with a line number
- `ArchUnit` and `{{path/}}` and `a b/c` and `src/*.ts` and `https://example.com/x/y` are not paths'
hc "$r"; [ $rc -eq 0 ]; check "codemap-stale: every cited path exists -> clean (non-paths ignored)" $?
r="$(mkclean)"; cm "$r" '# Architecture

Some prose about `src/gone/` without a Code map section.'
hc "$r"; [ $rc -eq 0 ]; check "codemap-stale: no Code map section -> silent" $?
r="$(mkclean)"; hc "$r"; [ ! -f "$r/docs/architecture.md" ] && [ $rc -eq 0 ]; check "codemap-stale: no docs/architecture.md -> silent" $?
r="$(mkclean)"; cm "$r" '# Architecture

## Code map
- `src/gone/` — removed
- `lib/gone/` — removed
- `src/gone/` — cited twice'
hc "$r"; [ "$(printf '%s\n' "$out" | grep -c '^warn	codemap-stale	')" = 2 ] && [ "$(warns)" = 2 ]; check "codemap-stale: one warning per missing path, a repeated path counts once" $?
r="$(mkclean)"; cm "$r" '# Architecture

## Code map
```text
src/gone/
```
- `src/` — the source'
hc "$r"; [ $rc -eq 0 ]; check "codemap-stale: a fenced block is not read" $?

r="$(mkclean)"; addrule "$r"; printf 'src/a.ts\t3\n' > "$r/.agents/baselines/file-size.tsv"; hc "$r"; only baseline-malformed file-size.tsv; check "baseline-malformed: no header" $?
r="$(mkclean)"; addrule "$r"; printf '# measured_at: 2026-10-20 review_by: 2027-04-20\nsrc/a.ts\tmany\n' > "$r/.agents/baselines/file-size.tsv"; hc "$r"; only baseline-malformed file-size.tsv; check "baseline-malformed: non-integer count" $?

r="$(mkclean)"; addrule "$r"; hc "$r" KEEL_TODAY=2027-05-01
[ $rc -eq 1 ] && [ "$(warns)" = 2 ] && printf '%s\n' "$out" | qgrep '^warn	baseline-stale	' && printf '%s\n' "$out" | qgrep '^warn	review-due	.agents/state.yml'; check "KEEL_TODAY=2027-05-01 -> baseline-stale and review-due" $?
hc "$r" KEEL_TODAY=2027-05-01 MEASURED=2; [ "$(warns)" = 1 ] && printf '%s\n' "$out" | qgrep '^warn	review-due'; check "baseline past review_by but shrunk -> only review-due" $?
r="$(mkclean)"; addrule "$r"; printf '# measured_at: 2026-10-20 review_by: 2027-04-20\n' > "$r/.agents/baselines/file-size.tsv"; hc "$r" KEEL_TODAY=2027-05-01
[ "$(warns)" = 1 ] && printf '%s\n' "$out" | qgrep '^warn	review-due'; check "an empty baseline past review_by is not stale" $?
hc "$r" KEEL_TODAY=2027-01-01; [ $rc -eq 0 ]; check "before review dates -> clean" $?

# ================= F3b: plan-stale, progress-size, acceptance-untested
# mkplan REPO NAME STATUS [DATE] -> .agents/plans/NAME.md, committed at DATE (or left uncommitted when DATE is "-")
mkplan() {
  local r="$1" n="$2" st="$3" d="${4:-2026-10-01}"
  mkdir -p "$r/.agents/plans"
  printf '# Plan: %s\nStatus: %s\nCreated: 2026-09-01\n\n## Acceptance\n- `file-size` reports 0 files over 300 lines\n\n## Steps\n1. split\n' "$n" "$st" > "$r/.agents/plans/$n.md"
  [ "$d" = "-" ] || (cd "$r" && git add -A && GIT_AUTHOR_DATE="${d}T12:00:00" GIT_COMMITTER_DATE="${d}T12:00:00" git commit -q -m "plan $n")
}
T=KEEL_TODAY=2026-10-29

# plan-stale
r="$(mkclean)"; mkplan "$r" p active 2026-09-01; hc "$r" $T; only plan-stale .agents/plans/p.md && printf '%s\n' "$out" | qgrep 'keel plan-close'; check "plan-stale: an active plan untouched for 58 days warns, fix names keel plan-close" $?
r="$(mkclean)"; mkplan "$r" p active 2026-10-10; hc "$r" $T; [ $rc -eq 0 ]; check "plan-stale: an active plan touched 19 days ago is clean" $?
r="$(mkclean)"; mkplan "$r" p active 2026-09-29; hc "$r" $T; [ $rc -eq 0 ]; check "plan-stale: exactly 30 days is not older than the limit" $?
r="$(mkclean)"; mkplan "$r" p active 2026-09-28; hc "$r" $T; only plan-stale p.md; check "plan-stale: 31 days warns" $?
r="$(mkclean)"; mkplan "$r" p "done" 2026-08-01; mkplan "$r" q abandoned 2026-08-01; hc "$r" $T; [ $rc -eq 0 ]; check "plan-stale: done and abandoned plans are not stale" $?
r="$(mkclean)"; mkplan "$r" p active -; hc "$r" $T; [ $rc -eq 0 ]; check "plan-stale: an uncommitted plan counts as fresh" $?
r="$(mkclean)"; mkplan "$r" p active 2026-08-01; printf 'edit\n' >> "$r/.agents/plans/p.md"; hc "$r" $T; [ $rc -eq 0 ]; check "plan-stale: a plan with uncommitted edits counts as fresh" $?
r="$(mkclean)"; mkdir -p "$r/.agents/plans"; printf '# Plan\nnothing\n' > "$r/.agents/plans/n.md"; commit "$r"; hc "$r" $T; [ $rc -eq 0 ]; check "plan-stale: a file with no Status: line is not an active plan" $?
r="$(mkclean)"; mkplan "$r" p active 2026-09-01; mkplan "$r" q active 2026-08-01; hc "$r" $T; [ $rc -eq 1 ] && [ "$(warns)" = 2 ]; check "plan-stale: one warning per stale plan" $?
r="$(mkclean)"; mkplan "$r" p active 2026-09-01; printf 'CEILING_SECONDS=30\nPLAN_STALE_DAYS=100\n' > "$r/.agents/gate.env"; commit "$r"; hc "$r" $T; [ $rc -eq 0 ]; check "plan-stale: PLAN_STALE_DAYS=100 in gate.env raises the limit" $?
r="$(mkclean)"; mkplan "$r" p active 2026-10-10; printf 'PLAN_STALE_DAYS=10\n' > "$r/.agents/gate.env"; commit "$r"; hc "$r" $T; only plan-stale p.md; check "plan-stale: PLAN_STALE_DAYS=10 in gate.env lowers the limit" $?
r="$(mkclean)"; mkplan "$r" p active 2026-10-10; printf 'PLAN_STALE_DAYS=10\r\n' > "$r/.agents/gate.env"; commit "$r"; hc "$r" $T; only plan-stale p.md; check "plan-stale: a CRLF gate.env is read" $?
r="$(mkclean)"; mkplan "$r" p active 2026-09-01; printf 'PLAN_STALE_DAYS=soon\n' > "$r/.agents/gate.env"; commit "$r"; hc "$r" $T; only plan-stale p.md; check "plan-stale: a non-numeric limit falls back to 30" $?
grep -q '^PLAN_STALE_DAYS=30' "$KEEL/assets/core/gate.env"; check "gate.env carries PLAN_STALE_DAYS=30" $?
grep -q '^PROGRESS_MAX_LINES=200' "$KEEL/assets/core/gate.env"; check "gate.env carries PROGRESS_MAX_LINES=200" $?
r="$(mkclean)"; hc "$r" $T; [ $rc -eq 0 ]; check "plan-stale: silent without a plans directory" $?

# progress-size
r="$(mkclean)"; seq 1 201 | sed 's/.*/2026-10-01 done p.md abc/' > "$r/.agents/progress.md"; hc "$r"; only progress-size .agents/progress.md && printf '%s\n' "$out" | qgrep 'summarise older entries into an ADR'; check "progress-size: 201 lines warns, fix says summarise into an ADR" $?
r="$(mkclean)"; seq 1 200 | sed 's/.*/2026-10-01 done p.md abc/' > "$r/.agents/progress.md"; hc "$r"; [ $rc -eq 0 ]; check "progress-size: 200 lines is clean" $?
r="$(mkclean)"; seq 1 60 | sed 's/.*/x/' > "$r/.agents/progress.md"; printf 'PROGRESS_MAX_LINES=50\n' > "$r/.agents/gate.env"; commit "$r"; hc "$r"; only progress-size progress.md; check "progress-size: PROGRESS_MAX_LINES=50 in gate.env lowers the limit" $?
r="$(mkclean)"; seq 1 300 | sed 's/.*/x/' > "$r/.agents/progress.md"; printf 'PROGRESS_MAX_LINES=400\n' > "$r/.agents/gate.env"; commit "$r"; hc "$r"; [ $rc -eq 0 ]; check "progress-size: PROGRESS_MAX_LINES=400 raises the limit" $?
r="$(mkclean)"; hc "$r"; [ $rc -eq 0 ]; check "progress-size: silent without a progress file" $?

# acceptance-untested
mkspec() { mkdir -p "$(dirname "$1")"; cat > "$1"; }
r="$(mkclean)"; mkspec "$r/docs/specs/login.md" <<'S'
# Login
## Goals
- Something vague that is not a criterion
## Acceptance criteria
- A user can log in
- A user can log out
S
commit "$r"; hc "$r"; only acceptance-untested docs/specs/login.md && printf '%s\n' "$out" | qgrep '2 acceptance' && printf '%s\n' "$out" | qgrep 'name the test that proves each criterion'; check "acceptance-untested: two untested bullets -> one warning with the count, bullets under Goals not counted" $?
mkdir -p "$r/tests"; echo t > "$r/tests/login.test.ts"
mkspec "$r/docs/specs/login.md" <<'S'
# Login
## Acceptance criteria
- A user can log in (`tests/login.test.ts`)
- A user can log out
S
commit "$r"; hc "$r"; only acceptance-untested login.md && printf '%s\n' "$out" | qgrep '1 acceptance'; check "acceptance-untested: a backticked existing test path passes the bullet" $?
mkspec "$r/docs/specs/login.md" <<'S'
# Login
## Acceptance criteria
- A user can log in, test: tests/login.test.ts
- A user can log out, test: `tests/login.test.ts`
S
commit "$r"; hc "$r"; [ $rc -eq 0 ]; check "acceptance-untested: a test: marker with a path passes (backticked or not)" $?
mkspec "$r/docs/specs/login.md" <<'S'
# Login
## Acceptance criteria
- A user can log in (`tests/nosuch.test.ts`)
- A user can log out (`src/login.ts`)
- A user can reset (`make test`)
S
echo x > "$r/src/login.ts"; commit "$r"; hc "$r"; only acceptance-untested login.md && printf '%s\n' "$out" | qgrep '3 acceptance'; check "acceptance-untested: a missing path, a path without test or spec in its name and a command do not pass" $?
mkspec "$r/docs/specs/login.md" <<'S'
# Login
## Acceptance criteria
- A user can log in
  covered by `tests/login.test.ts`
- A user can log out
  - nested detail without a test
S
commit "$r"; hc "$r"; only acceptance-untested login.md && printf '%s\n' "$out" | qgrep '1 acceptance'; check "acceptance-untested: continuation lines belong to their bullet; nested bullets are not extra criteria" $?
mkdir -p "$r/spec"; echo s > "$r/spec/login_spec.rb"
mkspec "$r/docs/specs/login.md" <<'S'
# Login
### Acceptance
1. A user can log in (`spec/login_spec.rb`)

### Out of scope
- Not a criterion
S
commit "$r"; hc "$r"; [ $rc -eq 0 ]; check "acceptance-untested: any heading level, numbered items, spec in the name, section ends at the next heading" $?
r="$(mkclean)"; mkdir -p "$r/tests"; echo t > "$r/tests/a.test.ts"
mkspec "$r/specs/001-login/spec.md" <<'S'
# Feature
### Acceptance Scenarios
1. **Given** a user, **When** they log in, **Then** they see the home page
S
commit "$r"; hc "$r"; only acceptance-untested specs/001-login/spec.md; check "acceptance-untested: Spec Kit's specs/*/spec.md is read" $?
mkspec "$r/docs/specs/a.md" <<'S'
## Acceptance
- one
S
mkspec "$r/docs/specs/b.md" <<'S'
## Acceptance
- two
S
commit "$r"; hc "$r"; [ $rc -eq 1 ] && [ "$(warns)" = 3 ]; check "acceptance-untested: one warning per spec file" $?
r="$(mkclean)"; mkspec "$r/docs/specs/n.md" <<'S'
# No criteria here
## Goals
- vague
S
commit "$r"; hc "$r"; [ $rc -eq 0 ]; check "acceptance-untested: a spec with no Acceptance section is silent" $?
r="$(mkclean)"; hc "$r"; [ $rc -eq 0 ]; check "acceptance-untested: silent when there are no specs" $?

r="$(mkclean)"; sed -i 's/^printf .*/exit 2/' "$r/scripts/sensors/lint.sh"; commit "$r"; hc "$r"; only sensor-unavailable lint.sh; check "sensor-unavailable: fast sensor exits 2 for a tracked file" $?
r="$(mkclean)"; : > "$r/stub.marker"; sed -i 's|^printf .*|printf "%s" "${SCOPE:-}" > "$PWD/scope.seen"; printf "%s\\t%s\\t%s\\t%s\\n" "$id" "$class" pass ok|' "$r/scripts/sensors/lint.sh"; commit "$r"; hc "$r"; [ "$(cat "$r/scope.seen" 2>/dev/null)" = "src/a.ts" ]; check "sensor-unavailable runs the sensor with SCOPE set to one tracked file" $?
rm -f "$r/scope.seen"

# exemplar-missing (F3d-1: C1b)
r="$(mkclean)"; addrule "$r"; mkdir -p "$r/src/good"; echo 1 > "$r/src/good/Best.ts"
printf "EXEMPLAR=src/good/Best.ts\nLEGACY='src/old/\nsrc/legacy-*.ts'\n" >> "$r/.agents/rules/file-size.env"; commit "$r"
hc "$r"; [ $rc -eq 0 ]; check "exemplar-missing: an existing EXEMPLAR (and a LEGACY list) is clean" $?
r="$(mkclean)"; addrule "$r"; printf 'EXEMPLAR=src/good/Gone.ts\n' >> "$r/.agents/rules/file-size.env"; commit "$r"
hc "$r"; only exemplar-missing file-size.env && printf '%s\n' "$out" | qgrep -F 'src/good/Gone.ts'; check "exemplar-missing: an EXEMPLAR path that does not exist warns, naming it" $?
r="$(mkclean)"; addrule "$r"; printf "EXEMPLAR='src/good/Gone.ts'  # the canonical one\n" >> "$r/.agents/rules/file-size.env"; commit "$r"
hc "$r"; only exemplar-missing file-size.env; check "exemplar-missing: a quoted EXEMPLAR with a trailing comment is read" $?
r="$(mkclean)"; addrule "$r"; hc "$r"; [ $rc -eq 0 ]; check "exemplar-missing: a rule with no EXEMPLAR is silent" $?
r="$(mkclean)"; addrule "$r"; printf 'EXEMPLAR=\n' >> "$r/.agents/rules/file-size.env"; commit "$r"; hc "$r"; [ $rc -eq 0 ]; check "exemplar-missing: an empty EXEMPLAR is silent" $?
r="$(mkclean)"; addrule "$r"; printf 'EXEMPLAR=src/a.ts\n' >> "$r/.agents/rules/file-size.env"; commit "$r"
cp "$r/.agents/rules/file-size.env" "$r/.agents/rules/second.env"; sed -i 's/RULE_ID=file-size/RULE_ID=second/; s/^EXEMPLAR=.*/EXEMPLAR=nope.ts/' "$r/.agents/rules/second.env"; commit "$r"
hc "$r"; printf '%s\n' "$out" | grep '^warn	exemplar-missing	' | qgrep 'second.env' && [ "$(printf '%s\n' "$out" | grep -c '^warn	exemplar-missing	')" = 1 ]; check "exemplar-missing: one warning per env file with a missing exemplar" $?

# mandatory-unsensored and exception-expired (D43)
# mandrule REPO [EXTRA_LINES] -> the consistent file-size rule made mandatory, its baseline removed
mandrule() {
  addrule "$1"; rm -f "$1/.agents/baselines/file-size.tsv"
  printf 'ENFORCEMENT_LEVEL=mandatory\n%s\n' "${2:-}" >> "$1/.agents/rules/file-size.env"
  (cd "$1" && git add -A && git commit -q -m mandatory)
}
has() { printf '%s\n' "$out" | qgrep "^warn	$1	"; } # has <check-id>
r="$(mkclean)"; mandrule "$r"; hc "$r"; [ $rc -eq 0 ]; check "mandatory-unsensored: a mandatory rule with its sensor -> clean" $?
r="$(mkclean)"; mandrule "$r"; sed -i 's/^ENFORCEMENT=.*/ENFORCEMENT=inferential/' "$r/.agents/rules/file-size.env"; hc "$r"
[ $rc -eq 1 ] && has mandatory-unsensored && printf '%s\n' "$out" | qgrep '^warn	mandatory-unsensored	[^	]*file-size.env'; check "mandatory-unsensored: ENFORCEMENT=inferential" $?
r="$(mkclean)"; mandrule "$r"; sed -i 's/^ENFORCEMENT=.*/ENFORCEMENT=sensor:nope/' "$r/.agents/rules/file-size.env"; hc "$r"
has mandatory-unsensored; check "mandatory-unsensored: names a sensor that has no file" $?
r="$(mkclean)"; mandrule "$r"; sed -i 's/^ENFORCEMENT=.*/ENFORCEMENT=sensor:file-size,sensor:nope/' "$r/.agents/rules/file-size.env"; hc "$r"
has mandatory-unsensored; check "mandatory-unsensored: one of several sensors has no file" $?
r="$(mkclean)"; mandrule "$r"; rm "$r/scripts/sensors/file-size.sh"; hc "$r"; has mandatory-unsensored; check "mandatory-unsensored: the sensor file was removed" $?
r="$(mkclean)"; mandrule "$r"; mkdir -p "$r/scripts/sensors/slow"; mv "$r/scripts/sensors/file-size.sh" "$r/scripts/sensors/slow/file-size.sh"; hc "$r"
! has mandatory-unsensored; check "mandatory-unsensored: a sensor under slow/ counts" $?
r="$(mkclean)"; addrule "$r"; sed -i 's/^ENFORCEMENT=.*/ENFORCEMENT=inferential/' "$r/.agents/rules/file-size.env"; hc "$r"
! has mandatory-unsensored; check "mandatory-unsensored: a ratchet rule may be inferential" $?
r="$(mkclean)"; mandrule "$r"; sed -i 's/^ENFORCEMENT_LEVEL=.*/ENFORCEMENT_LEVEL=Mandatory/' "$r/.agents/rules/file-size.env"; hc "$r"
has mandatory-unsensored && printf '%s\n' "$out" | qgrep "ENFORCEMENT_LEVEL is 'Mandatory'"; check "mandatory-unsensored: a misspelt ENFORCEMENT_LEVEL would silently be ratchet -> warn" $?

r="$(mkclean)"; mandrule "$r" "EXCEPTIONS='src/a.ts 2026-12-31'"; hc "$r" KEEL_TODAY=2026-10-29; [ $rc -eq 0 ]; check "exception-expired: a future deadline -> clean" $?
hc "$r" KEEL_TODAY=2026-12-31; [ $rc -eq 0 ]; check "exception-expired: the deadline day itself -> clean" $?
hc "$r" KEEL_TODAY=2027-01-01
[ $rc -eq 1 ] && [ "$(warns)" = 1 ] && printf '%s\n' "$out" | qgrep '^warn	exception-expired	[^	]*file-size.env	.*src/a.ts.*2026-12-31'; check "exception-expired: past its date -> one warning naming path and date" $?
r="$(mkclean)"; mandrule "$r" "EXCEPTIONS='src/a.ts 2026-10-01
src/with space.ts 2026-09-01
src/later.ts 2027-06-01'"; hc "$r" KEEL_TODAY=2026-10-29
[ "$(printf '%s\n' "$out" | grep -c '^warn	exception-expired	')" = 2 ] && printf '%s\n' "$out" | qgrep 'src/with space.ts'; check "exception-expired: one warning per expired line, a path may contain spaces" $?
r="$(mkclean)"; mandrule "$r" "EXCEPTIONS='src/a.ts soon'"; hc "$r" KEEL_TODAY=2026-10-29; has exception-expired; check "exception-expired: a line without a valid date -> warn" $?
r="$(mkclean)"; mandrule "$r"; hc "$r"; ! has exception-expired; check "exception-expired: no EXCEPTIONS -> silent" $?
before="$(cd "$r" && git status --porcelain)"; hc "$r" KEEL_TODAY=2027-01-01; [ "$before" = "$(cd "$r" && git status --porcelain)" ]; check "mandatory checks are read-only" $?

# --- F6: checks that read .agents/run/history/ (sensor-always-green, sensor-always-red, sensor-flaky, failure-recurring)
# mkhist REPO MODE SENSOR STATUS... -> appends one history line per status (p=pass, f=fail, s=skip), oldest first
mkhist() {
  local r="$1" mode="$2" id="$3" i=0 c st; shift 3
  mkdir -p "$r/.agents/run/history"
  for c in "$@"; do
    case "$c" in p) st=pass ;; f) st=fail ;; *) st=skip ;; esac
    i=$((i + 1))
    printf '2026-10-%02dT10:%02d:00Z\t%s\t%s\t%s\n' "$((i / 60 + 1))" "$((i % 60))" "$id" "$st" 7 >> "$r/.agents/run/history/$mode.tsv"
  done
}
rep() { # rep CHAR COUNT -> CHAR repeated COUNT times, space separated
  local i out=""
  for ((i = 0; i < $2; i++)); do out="$out $1"; done
  printf '%s' "$out"
}
has() { printf '%s\n' "$out" | qgrep "^warn	$1	"; } # has <check-id>

# sensor-always-green
r="$(mkclean)"; mkhist "$r" fast lint $(rep p 30); hc "$r"; only sensor-always-green scripts/sensors/lint.sh && printf '%s\n' "$out" | qgrep 'carry load'; check "sensor-always-green: 30 passes in a row warns" $?
printf '%s\n' "$out" | grep "^warn	sensor-always-green" | qgrep "review it; remove it or move it to the slow gate$"; check "sensor-always-green: the fix is review, remove or move to the slow gate" $?
r="$(mkclean)"; mkhist "$r" fast lint $(rep p 29); hc "$r"; [ $rc -eq 0 ]; check "sensor-always-green: 29 passes is below the threshold, silent" $?
r="$(mkclean)"; mkhist "$r" fast lint $(rep p 15) f $(rep p 20); hc "$r"; ! has sensor-always-green; check "sensor-always-green: a single failure in the window silences it" $?
r="$(mkclean)"; mkhist "$r" fast lint $(rep p 15) s $(rep p 20); hc "$r"; ! has sensor-always-green; check "sensor-always-green: a skipped run is not a pass" $?
r="$(mkclean)"; mkhist "$r" fast guard $(rep p 40); hc "$r"; [ $rc -eq 0 ]; check "sensor-always-green: a security sensor that always passes is doing its job, silent" $?
r="$(mkclean)"; mkhist "$r" fast gone-sensor $(rep p 40); hc "$r"; [ $rc -eq 0 ]; check "history: a sensor with no script left is ignored" $?
r="$(mkclean)"; cp "$r/scripts/sensors/lint.sh" "$r/scripts/sensors/slow/mut.sh"; sed -i 's/^id=lint/id=mut/' "$r/scripts/sensors/slow/mut.sh"; mkhist "$r" slow mut $(rep p 30); commit "$r"; hc "$r"; only sensor-always-green scripts/sensors/slow/mut.sh; check "sensor-always-green: slow.tsv maps to scripts/sensors/slow/" $?

# sensor-always-red
r="$(mkclean)"; mkhist "$r" fast lint $(rep f 10); hc "$r"; only sensor-always-red scripts/sensors/lint.sh; check "sensor-always-red: 10 failures in a row is one warning (not also failure-recurring)" $?
printf '%s\n' "$out" | grep "^warn	sensor-always-red" | qgrep "fix the cause or re-baseline with an ADR$"; check "sensor-always-red: the fix is the cause or an ADR" $?
r="$(mkclean)"; mkhist "$r" fast lint $(rep f 9); hc "$r"; ! has sensor-always-red; check "sensor-always-red: 9 failures is below the threshold" $?
r="$(mkclean)"; mkhist "$r" fast lint p $(rep f 9); hc "$r"; ! has sensor-always-red; check "sensor-always-red: a pass inside the last 10 silences it" $?
r="$(mkclean)"; mkhist "$r" fast lint $(rep p 12) $(rep f 10); hc "$r"; only sensor-always-red lint.sh; check "sensor-always-red: only the last 10 runs count" $?

# sensor-flaky
r="$(mkclean)"; mkhist "$r" fast lint p f p f p f p f p f; hc "$r"; only sensor-flaky scripts/sensors/lint.sh && printf '%s\n' "$out" | qgrep 'heuristic'; check "sensor-flaky: alternating pass and fail warns and says it is a heuristic" $?
printf '%s\n' "$out" | grep "^warn	sensor-flaky" | qgrep "make it deterministic$"; check "sensor-flaky: the fix is make it deterministic" $?
r="$(mkclean)"; mkhist "$r" fast lint p p p f f f p p p f; hc "$r"; only sensor-flaky lint.sh; check "sensor-flaky: exactly 3 flips in the last 10 warns" $?
r="$(mkclean)"; mkhist "$r" fast lint p p p p f f f p p p; hc "$r"; [ $rc -eq 0 ]; check "sensor-flaky: 2 flips is below the threshold" $?
r="$(mkclean)"; mkhist "$r" fast lint p f p f p f p f p; hc "$r"; [ $rc -eq 0 ]; check "sensor-flaky: fewer than 10 runs is silent" $?
r="$(mkclean)"; mkhist "$r" fast lint p f p f p f p f p f p p p p p p p p p p; hc "$r"; ! has sensor-flaky; check "sensor-flaky: only the last 10 runs count" $?

# failure-recurring
mkrule_env() { # mkrule_env REPO SENSOR -> a rule that names the sensor, with its doc section
  mkdir -p "$1/docs" "$1/.agents/rules"
  printf '# Conventions\n<a id="lint-clean"></a>\n### Lint clean\n' > "$1/docs/conventions.md"
  printf 'RULE_ID=lint-clean\nKIND=convention\nORIGIN=user\nAPPROVED_AT=2026-10-20\nENFORCEMENT=sensor:%s\nDOC=docs/conventions.md#lint-clean\n' "$2" > "$1/.agents/rules/lint-clean.env"
  printf -- '- Lint stays clean → docs/conventions.md#lint-clean\n' >> "$1/AGENTS.md"
}
r="$(mkclean)"; mkrule_env "$r" lint
sed -i 's/^class=heuristic/class=heuristic\nGUIDANCE="Run the linter and fix every reported problem"/' "$r/scripts/sensors/lint.sh"
mkhist "$r" fast lint $(rep p 8) $(rep f 5) $(rep p 7); commit "$r"; hc "$r"
only failure-recurring scripts/sensors/lint.sh; check "failure-recurring: 5 failures in the last 20 runs is one warning" $?
printf '%s\n' "$out" | grep "^warn	failure-recurring" | qgrep 'Run the linter and fix every reported problem'; check "failure-recurring: names the sensor's guidance (GUIDANCE= in the script)" $?
printf '%s\n' "$out" | grep "^warn	failure-recurring" | qgrep 'rule lint-clean' && printf '%s\n' "$out" | grep "^warn	failure-recurring" | qgrep 'docs/conventions.md#lint-clean' && printf '%s\n' "$out" | grep "^warn	failure-recurring" | qgrep 'AGENTS.md line'; check "failure-recurring: names the guide that would have prevented it (rule line and docs section)" $?
printf '%s\n' "$out" | grep "^warn	failure-recurring" | qgrep 'exemplar'; check "failure-recurring: the fix mentions the exemplar" $?
mkdir -p "$r/.agents/run"; printf '%s\n' 'x lint         [heuristic ] 1 problem                                     12ms' '  guidance: Fix the 1 problem shown in the last run' 'x other        [correctness] fine   3ms' > "$r/.agents/run/last-run.log"
hc "$r"; printf '%s\n' "$out" | grep "^warn	failure-recurring" | qgrep 'Fix the 1 problem shown in the last run'; check "failure-recurring: prefers the guidance printed in the last run's log" $?
r="$(mkclean)"; mkhist "$r" fast lint $(rep p 8) $(rep f 5) $(rep p 7); hc "$r"
only failure-recurring lint.sh && printf '%s\n' "$out" | grep "^warn	failure-recurring" | qgrep 'no rule names this sensor'; check "failure-recurring: with no rule for the sensor it suggests writing a guide" $?
r="$(mkclean)"; mkhist "$r" fast lint $(rep p 8) $(rep f 4) $(rep p 8); hc "$r"; [ $rc -eq 0 ]; check "failure-recurring: 4 failures in 20 is below the threshold, silent" $?
r="$(mkclean)"; mkhist "$r" fast lint $(rep f 5) $(rep p 30); hc "$r"; [ $rc -eq 0 ]; check "failure-recurring: failures older than the last 20 runs do not count" $?
r="$(mkclean)"; mkhist "$r" fast lint p f f f f f; hc "$r"; only failure-recurring lint.sh; check "failure-recurring: 5 failures in a short history still counts" $?
r="$(mkclean)"; mkhist "$r" fast lint p f p f p f p f p f; hc "$r"; only sensor-flaky lint.sh; check "failure-recurring: a flaky sensor is reported once, as flaky" $?

# history robustness
r="$(mkclean)"; mkdir -p "$r/.agents/run/history"; printf 'garbage\n\t\t\n2026-10-01T00:00:00Z\tlint\tweird\t1\n' > "$r/.agents/run/history/fast.tsv"; hc "$r"; [ $rc -eq 0 ]; check "history: malformed lines are ignored" $?
r="$(mkclean)"; mkhist "$r" fast lint $(rep f 10); before="$(cd "$r" && git status --porcelain --ignored | md5sum)"; hc "$r"; hc "$r"; [ "$before" = "$(cd "$r" && git status --porcelain --ignored | md5sum)" ]; check "history checks are read-only" $?
r="$(mkclean)"; mkhist "$r" fast lint $(rep f 10); hc "$r" TMPDIR=/nonexistent-keel; only sensor-always-red lint.sh; check "history checks work from the .agents/run/tmp fallback" $?

# README.agents.md
G="$KEEL/assets/core/README.agents.md"
[ -f "$G" ] && [ "$(wc -l < "$G")" -le 120 ]; check "README.agents.md exists and is at most 120 lines" $?
for t in 'make harness-check' 'scripts/sensors/disabled/' 'KEEL_MEASURE=1' 'adr_dir' '.claude/settings.json' 'scripts/sensors/'; do grep -qF -- "$t" "$G" 2>/dev/null; check "README.agents.md mentions $t" $?; done
# F6: a model change re-runs the read-only evals and moves harness_review_by
grep -qF 'On a model change' "$G" && grep -qF 'read-only eval groups' "$G" && grep -qF 'harness_review_by' "$G"; check "README.agents.md: on a model change, re-run the read-only eval groups and move harness_review_by" $?
grep -qF '## On a model change' "$KEEL/README.md" && sed -n '/^## On a model change/,/^## Evals/p' "$KEEL/README.md" | qgrep 'read-only eval groups' && sed -n '/^## On a model change/,/^## Evals/p' "$KEEL/README.md" | qgrep 'harness_review_by'; check "plugin README: on a model change, re-run the read-only eval groups and move harness_review_by" $?
finish
