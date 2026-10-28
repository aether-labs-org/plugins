#!/usr/bin/env bash
set -uo pipefail
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
  [ "$rc" -eq 1 ] && [ "$(warns)" = 1 ] && printf '%s\n' "$out" | grep -q "^warn	$1	[^	]*$2"
}
commit() { (cd "$1" && git add -A && git commit -q -m c); }

r="$(mkclean)"
hc "$r"; [ $rc -eq 0 ] && printf '%s\n' "$out" | tail -1 | grep -qx 'harness-check: harness is clean'; check "clean fixture: rc 0 and 'harness is clean'" $?
before="$(cd "$r" && git status --porcelain)"; hc "$r"; [ "$before" = "$(cd "$r" && git status --porcelain)" ]; check "read-only: git status unchanged" $?

# no state
r2="$(mkclean)"; rm "$r2/.agents/state.yml"; hc "$r2"; [ $rc -eq 2 ] && printf '%s\n' "$out" | grep -q 'harness-check: no harness installed - run /keel-harness:build'; check "no state -> rc 2" $?

# agents-size
r="$(mkclean)"; for i in $(seq 1 100); do echo "- line $i" >> "$r/AGENTS.md"; done; hc "$r"; only agents-size AGENTS.md; check "agents-size" $?
# nested AGENTS.md
r="$(mkclean)"; mkdir -p "$r/src/api"; for i in $(seq 1 101); do echo "- line $i"; done > "$r/src/api/AGENTS.md"; commit "$r"; hc "$r"; only agents-size src/api/AGENTS.md; check "agents-size on a nested AGENTS.md" $?

# stale-command
r="$(mkclean)"; printf '| Lint | `make lint-all` | exit 0 |\n' >> "$r/AGENTS.md"; hc "$r"; only stale-command AGENTS.md && printf '%s\n' "$out" | grep -q 'make lint-all'; check "stale-command: missing make target" $?
r="$(mkclean)"; printf '| Dev | `npm run dev` | up |\n' >> "$r/AGENTS.md"; hc "$r"; only stale-command AGENTS.md; check "stale-command: missing npm script" $?
r="$(mkclean)"; printf '| Dev | `pnpm build` | ok |\n| Gradle | `./gradlew test` | ok |\n' >> "$r/AGENTS.md"; hc "$r"; [ "$(warns)" = 1 ] && printf '%s\n' "$out" | grep -q 'gradlew'; check "stale-command: pnpm script exists, ./gradlew missing" $?
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

# guard-missing
r="$(mkclean)"; rm "$r/scripts/sensors/guard.sh"; commit "$r"; hc "$r"; only guard-missing scripts/sensors/guard.sh; check "guard-missing: no guard sensor" $?
r="$(mkclean)"; rm "$r/scripts/lib/envparse.sh"; commit "$r"; hc "$r"; printf '%s\n' "$out" | grep -q '^warn	guard-missing	'; check "guard-missing: no envparse lib" $?

# sensor-malformed
r="$(mkclean)"; sed -i 's/^id=lint/id=other/' "$r/scripts/sensors/lint.sh"; hc "$r"; only sensor-malformed scripts/sensors/lint.sh; check "sensor-malformed: id differs from file name" $?
r="$(mkclean)"; sed -i 's/^class=heuristic/class=fuzzy/' "$r/scripts/sensors/lint.sh"; hc "$r"; only sensor-malformed lint.sh; check "sensor-malformed: bad class" $?
r="$(mkclean)"; chmod -x "$r/scripts/sensors/lint.sh"; hc "$r"; only sensor-malformed lint.sh; check "sensor-malformed: not executable" $?
r="$(mkclean)"; cp "$r/scripts/sensors/lint.sh" "$r/scripts/sensors/_helper.sh"; chmod -x "$r/scripts/sensors/_helper.sh"; echo x > "$r/scripts/sensors/README.md"; commit "$r"; hc "$r"; [ $rc -eq 0 ]; check "sensor-malformed: _helper.sh and README.md are ignored" $?

# two broken conditions -> two lines
r="$(mkclean)"; printf '| X | `make nope` | x |\n' >> "$r/AGENTS.md"; printf 'nothing\n' > "$r/CLAUDE.md"; hc "$r"; [ $rc -eq 1 ] && [ "$(warns)" = 2 ] && printf '%s\n' "$out" | tail -1 | grep -qx 'harness-check: 2 warning(s)'; check "two broken conditions -> two warn lines and a count" $?
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
r="$(mkclean)"; addrule "$r"; rm "$r/scripts/sensors/file-size.sh"; hc "$r"; [ "$(warns)" -ge 1 ] && printf '%s\n' "$out" | grep -q '^warn	rule-inconsistent'; check "rule-inconsistent: sensor file missing" $?
r="$(mkclean)"; addrule "$r"; rm "$r/docs/decisions/0003-file-size-limit.md"; hc "$r"; only rule-inconsistent file-size.env; check "rule-inconsistent: DECISION file missing" $?
r="$(mkclean)"; addrule "$r"; sed -i 's/300 lines/200 lines/' "$r/docs/conventions.md"; hc "$r"; only rule-inconsistent file-size.env && printf '%s\n' "$out" | grep -q 'LIMIT=300'; check "rule-inconsistent: numeric parameter absent from the section" $?
r="$(mkclean)"; addrule "$r"; mkdir -p "$r/scripts/sensors/slow"; mv "$r/scripts/sensors/file-size.sh" "$r/scripts/sensors/slow/file-size.sh"; hc "$r"; [ $rc -eq 0 ]; check "rule-inconsistent: a slow sensor satisfies sensor:<id>" $?
r="$(mkclean)"; addrule "$r"; sed -i 's/^ENFORCEMENT=.*/ENFORCEMENT=inferential/' "$r/.agents/rules/file-size.env"; rm "$r/scripts/sensors/file-size.sh" "$r/.agents/baselines/file-size.tsv"; hc "$r"; [ $rc -eq 0 ]; check "rule-inconsistent: inferential rules need no sensor" $?

r="$(mkclean)"; mkdir -p "$r/docs"; seq 1 301 | sed 's/.*/x/' > "$r/docs/testing.md"; commit "$r"; hc "$r"; only topic-size docs/testing.md; check "topic-size" $?

r="$(mkclean)"; addrule "$r"; printf 'src/a.ts\t3\n' > "$r/.agents/baselines/file-size.tsv"; hc "$r"; only baseline-malformed file-size.tsv; check "baseline-malformed: no header" $?
r="$(mkclean)"; addrule "$r"; printf '# measured_at: 2026-10-20 review_by: 2027-04-20\nsrc/a.ts\tmany\n' > "$r/.agents/baselines/file-size.tsv"; hc "$r"; only baseline-malformed file-size.tsv; check "baseline-malformed: non-integer count" $?

r="$(mkclean)"; addrule "$r"; hc "$r" KEEL_TODAY=2027-05-01
[ $rc -eq 1 ] && [ "$(warns)" = 2 ] && printf '%s\n' "$out" | grep -q '^warn	baseline-stale	' && printf '%s\n' "$out" | grep -q '^warn	review-due	.agents/state.yml'; check "KEEL_TODAY=2027-05-01 -> baseline-stale and review-due" $?
hc "$r" KEEL_TODAY=2027-05-01 MEASURED=2; [ "$(warns)" = 1 ] && printf '%s\n' "$out" | grep -q '^warn	review-due'; check "baseline past review_by but shrunk -> only review-due" $?
r="$(mkclean)"; addrule "$r"; printf '# measured_at: 2026-10-20 review_by: 2027-04-20\n' > "$r/.agents/baselines/file-size.tsv"; hc "$r" KEEL_TODAY=2027-05-01
[ "$(warns)" = 1 ] && printf '%s\n' "$out" | grep -q '^warn	review-due'; check "an empty baseline past review_by is not stale" $?
hc "$r" KEEL_TODAY=2027-01-01; [ $rc -eq 0 ]; check "before review dates -> clean" $?

r="$(mkclean)"; sed -i 's/^printf .*/exit 2/' "$r/scripts/sensors/lint.sh"; commit "$r"; hc "$r"; only sensor-unavailable lint.sh; check "sensor-unavailable: fast sensor exits 2 for a tracked file" $?
r="$(mkclean)"; : > "$r/stub.marker"; sed -i 's|^printf .*|printf "%s" "${SCOPE:-}" > "$PWD/scope.seen"; printf "%s\\t%s\\t%s\\t%s\\n" "$id" "$class" pass ok|' "$r/scripts/sensors/lint.sh"; commit "$r"; hc "$r"; [ "$(cat "$r/scope.seen" 2>/dev/null)" = "src/a.ts" ]; check "sensor-unavailable runs the sensor with SCOPE set to one tracked file" $?
rm -f "$r/scope.seen"

# README.agents.md
G="$KEEL/assets/core/README.agents.md"
[ -f "$G" ] && [ "$(wc -l < "$G")" -le 120 ]; check "README.agents.md exists and is at most 120 lines" $?
for t in 'make harness-check' 'scripts/sensors/disabled/' 'KEEL_MEASURE=1' 'adr_dir' '.claude/settings.json' 'scripts/sensors/'; do grep -qF -- "$t" "$G" 2>/dev/null; check "README.agents.md mentions $t" $?; done
finish
