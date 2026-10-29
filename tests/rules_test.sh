#!/usr/bin/env bash
set -uo pipefail
fail=0
check() { if [ "$2" -eq 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fail=1; fi; }
root="$(cd "$(dirname "$0")/.." && pwd)"
sk="$root/plugins/keel-harness/skills/rules"
S="$sk/SKILL.md"
has() { grep -qF -- "$2" "$1" 2>/dev/null; }

# --- Task 9: skeleton
[ -f "$S" ]; check "rules SKILL.md exists" $?
grep -q '^name: rules$' "$S" 2>/dev/null; check "rules frontmatter name" $?
grep -q '^description: >' "$S" 2>/dev/null; check "rules frontmatter description block" $?
has "$S" 'ArchUnit'; check "description mentions ArchUnit" $?
has "$S" 'ADR'; check "description mentions ADR" $?

# --- Task 16: flow, interview, ADRs, catalog and templates
[ "$(wc -l < "$S")" -le 250 ]; check "rules SKILL.md is at most 250 lines" $?
for s in 'interview.md' '0001-agent-harness-context' 'AskUserQuestion' 'at most 4 questions' 'measure.sh' 'render.sh' \
         'KEEL_MEASURE=1' 'FreezingArchRule' 'gate-slow' '.agents/plans/' 'origin:' 'decision:' \
         'writes only what the user approved' 'never migrates' '/keel-harness:build' 'scripts/keel check pre rules' \
         '300 lines' 'docs/architecture.md' 'docs/conventions.md' 'docs/testing.md'; do
  has "$S" "$s"; check "rules SKILL.md contains: $s" $?
done
for s in 'scripts/keel plan rules' 'keel approve rules' 'scripts/keel apply rules' 'scripts/keel verify rules' 'before the first write'; do
  has "$S" "$s"; check "rules SKILL.md calls keel (F2c-2): $s" $?
done
[ "$(grep -c '^- \[ \]' "$S")" -eq 0 ]; check "rules SKILL.md keeps no '- [ ]' checklist (keel verify rules replaces it)" $?
! grep -q 'Every approved rule has its section' "$S"; check "rules SKILL.md dropped the prose Done-when list" $?
R="$sk/references"
C="$R/catalog.md"
for e in file-size folder-layout architecture code-language testing-strategy adopted-patterns; do
  grep -q "^## .*$e" "$C" 2>/dev/null; check "catalog entry: $e" $?
done
for l in '**Questions**' '**Measure**' '**Default**' '**Why**' '**Sensor**' '**Opinion**'; do
  [ "$(grep -cF -- "$l" "$C" 2>/dev/null)" -ge 6 ]; check "catalog has $l in every entry" $?
done
for w in onionArchitecture PIT Stryker mutmut; do has "$C" "$w"; check "catalog mentions $w" $?; done
has "$C" 'https://'; check "catalog cites URLs" $?
has "$R/adr-template.md" 'Considered Options' && has "$R/adr-template.md" 'supersede'; check "adr-template.md" $?
RS="$R/rule-section.md"
for s in '<a id="' '**Rule.**' '**Why.**' '**✓ / ✗.**' '**When it fails.**' '**Decision.**'; do has "$RS" "$s"; check "rule-section.md has $s" $?; done
for k in RULE_ID KIND ORIGIN APPROVED_AT ENFORCEMENT DOC DECISION PLAN; do has "$root/plugins/keel-harness/contracts/rule-env.md" "$k="; check "contracts/rule-env.md names $k" $?; done
has "$R/topics/architecture.md" 'Codemap' && has "$R/topics/architecture.md" 'Invariants'; check "topics/architecture.md has Codemap and Invariants" $?
for t in conventions testing; do [ -f "$R/topics/$t.md" ] && has "$R/topics/$t.md" '<a id="'; check "topics/$t.md with an example anchored section" $?; done
has "$root/plugins/keel-harness/contracts/plan.md" 'review_by' && has "$root/plugins/keel-harness/contracts/plan.md" 'make gate-fast'; check "contracts/plan.md" $?
[ -f "$R/nested-agents-md-template.md" ] && has "$R/nested-agents-md-template.md" '## Rules' && has "$R/nested-agents-md-template.md" '100 lines'; check "nested-agents-md-template.md" $?
[ -f "$R/interview.md" ] && has "$R/interview.md" 'at most 4 questions'; check "interview.md" $?
has "$root/plugins/keel-harness/skills/build/SKILL.md" '/keel-harness:rules'; check "build SKILL.md offers /keel-harness:rules" $?
has "$sk/SKILL.md" 'adr_dir:'; check "rules records adr_dir in state.yml (D45)" $?
has "$sk/SKILL.md" 'docs/adr/'; check "rules defaults the ADR folder to docs/adr/" $?
! grep -rq "docs/""rules" "$root/plugins" "$root/tests"; check "per-rule doc path is gone (D28)" $?

# --- Task 17: rules evals
EV="$root/plugins/keel-harness/evals"
for c in rules-brownfield rules-greenfield rules-architecture-java rules-effect-with rules-effect-without; do
  [ -f "$EV/$c/case.yaml" ] && [ -f "$EV/$c/prompt.md" ] && [ -f "$EV/$c/scaffold.sh" ]; check "eval $c has case, prompt and scaffold" $?
  [ "$(ls "$EV/$c/graders" 2>/dev/null | wc -l)" -ge 1 ]; check "eval $c has at least one grader" $?
  bash -n "$EV/$c/scaffold.sh" 2>/dev/null; check "eval $c scaffold parses" $?
done
bash -n "$EV/rules-brownfield/harness.sh"; check "eval harness helper parses" $?
exit $fail
