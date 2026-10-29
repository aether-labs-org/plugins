#!/usr/bin/env bash
set -uo pipefail
fail=0
check() { if [ "$2" -eq 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fail=1; fi; }
root="$(cd "$(dirname "$0")/.." && pwd)"
sk="$root/plugins/keel-harness/skills/assess"

[ -f "$sk/references/rubric.md" ]; check "rubric.md exists" $?
for axis in "Bootstrap" "Guides" "Fast sensors" "Slow sensors" "Enforcement" "Context" "Rules" "Reproducible build" "Headless setup" "Flaky tests" "Observability"; do
  grep -q "$axis" "$sk/references/rubric.md" 2>/dev/null; check "rubric has axis: $axis" $?
done
for state in present partial absent; do
  grep -qi "$state" "$sk/references/rubric.md" 2>/dev/null; check "rubric has state: $state" $?
done
[ -f "$sk/references/harness-model.md" ]; check "harness-model.md copied" $?
grep -q "Cost to close" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md pins the report table header" $?
grep -q "setup minutes" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md names the setup-minutes unit" $?
grep -q "not measured" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md forbids guessing a cost" $?
grep -qi "writes nothing" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md states the no-write rule" $?
grep -q "aggregate score" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md forbids an aggregate score" $?

R="$sk/references/rubric.md"
for s in husky lefthook mutation; do grep -qi "$s" "$R"; check "rubric mentions $s" $?; done
! grep "^| \*\*Context" "$R" | grep -q '\.mcp\.json'; check "Context row no longer requires .mcp.json" $?
for s in 'estimated setup minutes' greenfield brownfield '.github/copilot-instructions.md' '.devin/rules' 'eleven-axis'; do
  grep -qF -- "$s" "$sk/SKILL.md"; check "SKILL.md contains: $s" $?
done
ev="$root/plugins/keel-harness/evals/assess-claude-md"
for f in case.yaml prompt.md scaffold.sh; do [ -f "$ev/$f" ]; check "assess-claude-md has $f" $?; done
[ "$(ls "$ev/graders" 2>/dev/null | wc -l)" -ge 3 ]; check "assess-claude-md has 3 graders" $?
bash -n "$ev/scaffold.sh" 2>/dev/null; check "assess-claude-md scaffold parses" $?

# --- F2d: four new axes (11 in a fixed order), each with a rubric row, evidence and a cost
ax="$(sed -n '/^| Axis/,/^$/p' "$R" | grep -E '^\| \*\*' | sed 's/^| \*\*\([^*]*\)\*\*.*/\1/' | tr '\n' ',')"
[ "$ax" = "Bootstrap,Guides,Fast sensors,Slow sensors,Enforcement,Context,Rules,Reproducible build,Headless setup,Flaky tests,Observability," ]; check "rubric has the 11 axes in the fixed order ($ax)" $?
grep -q 'Eleven axes' "$R"; check "rubric states eleven axes" $?
for s in 'npm ci' 'pnpm install --frozen-lockfile' 'uv sync --frozen' 'poetry install --sync' 'Gradle or Maven wrapper'; do
  grep '^| \*\*Reproducible build' "$R" | grep -qF -- "$s"; check "Reproducible build row names: $s" $?
done
grep '^| \*\*Headless setup' "$R" | grep -q 'no `read`' && grep '^| \*\*Headless setup' "$R" | grep -q '.env.example'; check "Headless setup row: no read, .env.example" $?
grep '^| \*\*Flaky tests' "$R" | grep -q '3 times' && grep '^| \*\*Flaky tests' "$R" | grep -q 'not measured'; check "Flaky tests row: measured 3 times, unmeasured is not measured" $?
grep '^| \*\*Observability' "$R" | grep -q 'pino' && grep '^| \*\*Observability' "$R" | grep -q 'log-format line'; check "Observability row: logging library and a log-format line" $?
grep -qF '+N.Ns per run' "$R" && grep -qF '+N.Ns per run' "$sk/SKILL.md"; check "the per-run cost unit is in the rubric and the report contract" $?
phase1="$(awk '/^### Phase 1/{p=1} /^### Phase 2/{p=0} p' "$sk/SKILL.md")" # captured once: a pipe into grep -q can die of SIGPIPE under pipefail
grep -q 'three times' <<< "$phase1"; check "phase 1 asks before running the tests three times" $?
grep -q 'only after the user agrees' "$sk/SKILL.md" && grep -qi 'agreement' "$R"; check "the three runs need the user's agreement" $?
for a in 'Reproducible build' 'Headless setup' 'Flaky tests' 'Observability'; do
  grep -qF -- "\`$a\`" <<< "$phase1"; check "phase 1 scoring lists axis: $a" $?
done
! grep -qi 'aggregate score\|overall grade' "$R" || grep -q 'There is no aggregate score' "$R"; check "still no aggregate score" $?

# --- F2c-2: assess runs through scripts/keel
for s in "scripts/keel check pre assess" "scripts/keel verify assess"; do
  grep -qF -- "$s" "$sk/SKILL.md"; check "assess SKILL.md calls: $s" $?
done
awk '/keel check pre assess/{a=NR} /keel verify assess/{v=NR} END{exit !(a>0 && v>a)}' "$sk/SKILL.md"; check "assess runs check pre first and verify last" $?

# --- doctor folded into assess (D51, F2c-1): the health check half
f="$sk/SKILL.md"
chk="$sk/references/checks.md"
has() { grep -qF -- "$1" "$f" 2>/dev/null; }
hasc() { grep -qF -- "$1" "$chk" 2>/dev/null; }
[ ! -e "$root/plugins/keel-harness/skills/""doctor" ]; check "the doctor skill is gone (folded into assess)" $?
grep -qE '^disallowed-tools: Write Edit NotebookEdit$' "$f"; check "assess declares disallowed-tools: Write Edit NotebookEdit (D36)" $?
! grep -q '^allowed-tools:' "$f"; check "assess does not use allowed-tools as a restriction" $?
[ "$(awk '/^description: >/{d=1;next} d&&/^[a-z-]+:/{d=0} d' "$f" | sed 's/^ *//' | tr '\n' ' ' | wc -c)" -le 1024 ]; check "assess description is at most 1,024 characters" $?
grep -qi 'out of date' "$f" && grep -qi 'health check' "$f" && grep -qi 'ready' "$f"; check "assess description keeps bothd; } | trigger families" $?
has '.agents/state.yml'; check "assess branches on .agents/state.yml" $?
has 'references/checks.md'; check "assess links references/checks.md" $?
hasc "100 lines"; check "AGENTS.md size is covered" $?
! has "model_baseline" && ! hasc "model_baseline"; check "no model_baseline check (replaced by review-due)" $?
has 'harness-check.sh'; check "runs harness-check.sh" $?
has '${CLAUDE_PLUGIN_ROOT}/assets/core/harness-check.sh'; check "runs the plugin's copy of the validator" $?
has 'prompt-audit'; check "points at /doctor prompt-audit" $?
grep -qi "writes nothing" "$f"; check "assess writes nothing" $?
grep -qi "exactly one warning" "$chk"; check "one condition produces one warning" $?
has 'cmp'; check "proposes updating scripts/harness-check.sh when it differs (cmp)" $?
for id in agents-size stale-command agents-not-loaded dangling-pointer hook-missing run-state guard-missing enforcement-drift protect-missing sensor-malformed sensor-unavailable \
          rule-inconsistent topic-size baseline-malformed baseline-stale codemap-stale review-due; do
  hasc "$id"; check "check id: $id" $?
done
for id in plan-stale progress-size acceptance-untested; do
  hasc "$id"; check "check id (F3b): $id" $?
done
for id in sensor-always-green sensor-always-red sensor-flaky failure-recurring; do
  hasc "$id"; check "check id (F6): $id" $?
done
has ".agents/run/history/"; check "assess SKILL.md says the history checks read .agents/run/history/" $?
! has "looks once, not across time"; check "assess SKILL.md no longer says the health check looks once" $?
! grep -qi "capture rate" "$f" "$chk"; check "no capture-rate check (keel does not record why a run failed)" $?
# the count written in the title, in assess/SKILL.md and in the README equals the rows of the table
nrows="$(grep -c '^| `' "$chk")"
words="x x x x x x x x x x x x x x x fifteen sixteen seventeen eighteen nineteen twenty twenty-one twenty-two twenty-three twenty-four twenty-five twenty-six twenty-seven twenty-eight twenty-nine thirty"
word="$(printf '%s\n' "$words" | cut -d' ' -f$((nrows + 1)))"
grep -q "^# The $word checks$" "$chk"; check "checks.md title counts its $nrows rows ($word)" $?
grep -qF "The $word checks, what each one means" "$f"; check "assess SKILL.md counts the checks: $word" $?
grep -qF "$nrows checks), explains" "$root/plugins/keel-harness/README.md"; check "README counts the checks: $nrows" $?
grep '^| `codemap-stale`' "$chk" | grep -q 'Code map'; check "codemap-stale row explains the Code map" $?
! grep -qi "is not installed by keel\|not installed by keel" "$f"; check "assess no longer says keel does not install enforcement" $?
ev="$root/plugins/keel-harness/evals/assess-validator-drift"
for x in case.yaml prompt.md scaffold.sh; do [ -f "$ev/$x" ]; check "assess-validator-drift has $x" $?; done
[ "$(ls "$ev/graders" 2>/dev/null | wc -l)" -ge 3 ]; check "assess-validator-drift has graders" $?
bash -n "$ev/scaffold.sh" 2>/dev/null; check "assess-validator-drift scaffold parses" $?
grep -q 'assess-finds-drift/scaffold.sh' "$ev/scaffold.sh"; check "assess-validator-drift scaffold calls assess-finds-drift" $?
[ -f "$root/plugins/keel-harness/evals/assess-finds-drift/scaffold.sh" ]; check "assess-finds-drift scaffold exists" $?
[ ! -e "$root/plugins/keel-harness/evals/doctor-finds-drift" ] && [ ! -e "$root/plugins/keel-harness/evals/doctor-validator-drift" ]; check "doctor-* eval cases renamed to assess-*-drift" $?
[ ! -e "$root/plugins/keel-harness/evals/doctor-agents-not-loaded" ]; check "doctor-agents-not-loaded retired (E1)" $?
for c in assess-finds-drift assess-validator-drift; do
  grep -q "allowed_tools: \[.*Bash" "$root/plugins/keel-harness/evals/$c/prompt.md"; check "$c grants Bash (assess runs the validator)" $?
  grep -q '^name: '"$c"'$' "$root/plugins/keel-harness/evals/$c/case.yaml" && grep -q '^tags: \[assess,' "$root/plugins/keel-harness/evals/$c/case.yaml"; check "$c case.yaml carries its new name and the assess tag" $?
  grep -q 'tool: Skill' "$root/plugins/keel-harness/evals/$c/graders/skill-fired.md" && grep -qF '"skill"\s*:\s*"(?:[\w-]+:)?assess"' "$root/plugins/keel-harness/evals/$c/graders/skill-fired.md"; check "$c has the skill-fired grader" $?
done
! grep -q 'doctor' "$root/plugins/keel-harness/evals/should-not-trigger/graders/skill-silent.md"; check "should-not-trigger no longer names doctor" $?
! grep -rq 'sensors:' "$root/plugins/keel-harness/evals/gate-catches-defect/fixtures/harness/.agents/state.yml"; check "eval fixture state has no sensors list" $?

# --- F6: lessons inbox
L="$sk/references/lessons.md"
LC="$root/plugins/keel-harness/contracts/learnings.md"
[ -f "$L" ] && [ -f "$LC" ]; check "lessons.md and contracts/learnings.md exist" $?
has 'references/lessons.md' && has '.agents/run/learnings/'; check "assess SKILL.md reads the lessons inbox through references/lessons.md" $?
has 'it never promotes, edits or deletes a lesson, and never writes memory or learnings'; check "assess SKILL.md: never promotes, edits or deletes a lesson, never writes memory or learnings" $?
for s in '/keel-harness:rules' 'ADR' 'discard' 'malformed' 'Seen:' 'Proposed:' 'Source:'; do
  grep -qF -- "$s" "$L"; check "lessons.md covers: $s" $?
done
for s in 'Source:' 'Seen:' 'Proposed:' '`rule`' '`sensor`' '`adr`' '`discard`' 'git-ignored' 'Stop hook' 'sessions in a row' 'YYYY-MM-DD-<slug>.md' 'Only the user'; do
  grep -qF -- "$s" "$LC"; check "learnings.md states: $s" $?
done
grep -qF '.agents/run/learnings/YYYY-MM-DD-<slug>.md' "$root/plugins/keel-harness/assets/core/README.agents.md"; check "README.agents.md tells agents where to write a lesson" $?

# --- F6: auto-memory coherence (D41)
M="$sk/references/memory.md"
[ -f "$M" ]; check "memory.md exists" $?
grep -qF 'https://code.claude.com/docs/en/memory' "$M" && grep -qF 'read 2026-10-29' "$M"; check "memory.md cites the memory docs with the date read" $?
grep -qF '~/.claude/projects/<project>/memory/' "$M" && grep -qF 'MEMORY.md' "$M" && grep -qF 'autoMemoryDirectory' "$M"; check "memory.md states the location, the index and the override as the docs give them" $?
grep -qF 'first 200 lines or 25 KB' "$M"; check "memory.md states what loads at session start" $?
grep -qi 'inferential' "$M" && grep -qF 'env-file' "$M"; check "memory.md says the comparison is inferential and names the env-file numbers" $?
grep -qF 'AGENTS.md' "$M" && grep -q 'contradiction' "$M"; check "memory.md compares with the env files and AGENTS.md" $?
grep -qF 'never guess it' "$M"; check "memory.md does not guess the project directory" $?
grep -qF 'edits or deletes that entry' "$M" && grep -qF 'never edits, creates or deletes a memory file' "$M"; check "memory.md proposes edit or delete and never edits memory" $?
has 'references/memory.md'; check "assess SKILL.md points at references/memory.md" $?
has 'Assess never edits memory'; check "assess SKILL.md: Assess never edits memory" $?
exit $fail
