#!/usr/bin/env bash
set -uo pipefail
qgrep() { grep "$@" >/dev/null; } # reads all its input: `| grep -q` can SIGPIPE the writer under pipefail
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
has "$R/topics/architecture.md" '## Code map' && has "$R/topics/architecture.md" 'Invariants'; check "topics/architecture.md has Code map and Invariants" $?
T="$R/topics/architecture.md"
awk '/^## Code map/{p=1;next} /^## /{p=0} p' "$T" | qgrep "Bird's-eye"; check "Code map template opens with a bird's-eye paragraph" $?
awk '/^## Code map/{p=1;next} /^## /{p=0} p' "$T" | qgrep -F -- '- `{{path/}}` — '; check "Code map template has one bullet per module: \`path/\` — what lives there" $?
awk '/^## Code map/{p=1;next} /^## /{p=0} p' "$T" | qgrep -i 'invariants'; check "Code map template ends with the invariants" $?
has "$T" 'harness-check' && has "$T" 'codemap-stale'; check "architecture topic names the codemap-stale check" $?
has "$S" '## Code map' && has "$S" 'measure.sh" tree 2' && has "$S" 'confirm or correct'; check "rules drafts the Code map from measure.sh tree 2 and has the user confirm it" $?
awk '/^### Phase 5/{p=1} /^### Phase 6/{p=0} p' "$S" | qgrep 'Code map'; check "the Code map is proposed in the proposals phase (architecture topic)" $?
for t in conventions testing; do [ -f "$R/topics/$t.md" ] && has "$R/topics/$t.md" '<a id="'; check "topics/$t.md with an example anchored section" $?; done
has "$root/plugins/keel-harness/contracts/plan.md" 'Status:' && has "$root/plugins/keel-harness/contracts/plan.md" '## Acceptance' && has "$root/plugins/keel-harness/contracts/plan.md" 'make gate-fast'; check "contracts/plan.md" $?
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

# --- F3b: rules writes versioned plans from contracts/plan.md and verifies them
! grep -q '`\.agents/plans/` in `\.gitignore`' "$S"; check "rules no longer adds .agents/plans/ to .gitignore" $?
! grep -qi 'gitignored' "$S"; check "rules does not call plans gitignored" $?
has "$S" 'keel verify plan'; check "rules runs keel verify plan on each plan" $?
has "$S" '## Acceptance'; check "rules writes an Acceptance section" $?
has "$S" 'PLAN='; check "rules still records PLAN=" $?

# --- F3d-1: exemplars and legacy zones (C1b)
RE="$root/plugins/keel-harness/contracts/rule-env.md"
has "$RE" 'EXEMPLAR=' && has "$RE" 'LEGACY='; check "contracts/rule-env.md documents EXEMPLAR= and LEGACY=" $?
has "$RE" 'exemplar-missing'; check "rule-env.md names the exemplar-missing check" $?
has "$R/nested-agents-md-template.md" 'Follow {{EXEMPLAR}}, not {{legacy path}}' && has "$R/nested-agents-md-template.md" 'Legacy zone:'; check "nested template has the Follow X, not Y and Legacy zone lines" $?
has "$S" 'EXEMPLAR=' && has "$S" 'LEGACY=' && has "$S" 'only after the user confirms'; check "rules proposes an exemplar and writes it only after confirmation" $?
has "$S" 'With no clear best file'; check "rules proposes no exemplar without a clear best file" $?
[ "$(wc -l < "$S")" -le 250 ]; check "rules SKILL.md still at most 250 lines after F3d-1" $?
awk '/^## adopted-patterns/{p=1;next} /^## /{p=0} p' "$C" | qgrep -F 'pattern.sh'; check "catalog: adopted-patterns promotes a syntactic pattern to pattern.sh" $?
awk '/^## adopted-patterns/{p=1;next} /^## /{p=0} p' "$C" | qgrep -F 'measure.sh pattern' && awk '/^## adopted-patterns/{p=1;next} /^## /{p=0} p' "$C" | qgrep -F 'RULE_FILE'; check "catalog: the promotion route measures first and names RULE_FILE for ast-grep and semgrep" $?
has "$S" 'rules/pattern.sh' && has "$S" 'measure.sh" pattern'; check "rules copies pattern.sh for a confirmed pattern and measures it first" $?
[ -f "$root/plugins/keel-harness/assets/core/sensors/rules/pattern.sh" ]; check "pattern.sh ships under assets/core/sensors/rules" $?
# --- F3c-2: mandatory rules (D43), Spec Kit constitution
CT="$root/plugins/keel-harness/contracts/rule-env.md"
P5="$(awk '/^### Phase 5/{p=1} /^### Phase 6/{p=0} p' "$S")"
printf '%s\n' "$P5" | qgrep -F 'Mandatory or ratchet?' && printf '%s\n' "$P5" | qgrep -F 'ENFORCEMENT_LEVEL=mandatory' && printf '%s\n' "$P5" | qgrep -F 'superseding ADR'; check "phase 5 asks mandatory or ratchet, with the trade-off" $?
printf '%s\n' "$P5" | qgrep -F 'inferential rule stays ratchet'; check "phase 5: an inferential rule stays ratchet" $?
awk '/^### Phase 3/{p=1} /^### Phase 4/{p=0} p' "$S" | qgrep -F '.specify/memory/constitution.md'; check "phase 3 reads a Spec Kit constitution" $?
awk '/^### Phase 3/{p=1} /^### Phase 4/{p=0} p' "$S" | qgrep -F '## Principles' && awk '/^### Phase 3/{p=1} /^### Phase 4/{p=0} p' "$S" | qgrep -F '→ review:<owner>'; check "unsensorable principles go to ## Principles with → review:<owner>" $?
has "$S" 'never writes a `constitution.md`'; check "rules never writes a constitution.md" $?
[ -z "$(find "$root/plugins/keel-harness" -name 'constitution*' | head -1)" ]; check "the plugin ships no constitution file or template" $?
awk '/^### Phase 7/{p=1} /^### Phase 8/{p=0} p' "$S" | qgrep -F 'mandatory rules come first' && awk '/^### Phase 7/{p=1} /^### Phase 8/{p=0} p' "$S" | qgrep -F '[mandatory]'; check "phase 7 puts mandatory rules first in AGENTS.md" $?
awk '/^### Phase 7/{p=1} /^### Phase 8/{p=0} p' "$S" | qgrep -F 'A mandatory rule has no baseline'; check "phase 7: a mandatory rule has EXCEPTIONS, not a baseline" $?
has "$R/nested-agents-md-template.md" '[mandatory]' && has "$R/nested-agents-md-template.md" 'mandatory rules first'; check "nested AGENTS.md template lists mandatory rules first" $?
has "$root/plugins/keel-harness/skills/build/references/agents-md-template.md" '[mandatory]' && has "$root/plugins/keel-harness/skills/build/references/agents-md-template.md" 'mandatory rules first'; check "root AGENTS.md template lists mandatory rules first" $?
has "$R/adr-template.md" 'Supersedes:' && has "$R/adr-template.md" 'CODEOWNERS'; check "adr-template.md documents the Supersedes: line and its CODEOWNERS approval" $?
has "$root/plugins/keel-harness/skills/build/references/enforcement.md" 'mandatory' && has "$root/plugins/keel-harness/skills/build/references/enforcement.md" 'required'; check "enforcement.md asks for a required keel check when a rule is mandatory" $?
for t in ENFORCEMENT_LEVEL EXCEPTIONS 'ratchet' 'Supersedes:' 'CODEOWNERS' 'mandatory-unsensored' 'exception-expired' 'no baseline' '.agents/rules/'; do has "$CT" "$t"; check "rule-env.md documents $t" $?; done
has "$R/topics/architecture.md" '## Principles' && has "$R/topics/architecture.md" 'review:'; check "architecture topic has the ## Principles section" $?
# --- F3d-2: catalog entries (D44), each marked unproven
ST='**Status**: unproven — no with/without measurement yet (D50; F3d acceptance)'
D44="function-size complexity max-params dead-code duplication comments spelling code-style naming suppressions dependencies type-strictness error-handling logging test-conventions"
for e in $D44; do
  sec="$(awk -v h="## $e" '$0 == h { p = 1; next } /^## / { p = 0 } p' "$C")"
  [ -n "$sec" ]; check "catalog entry (D44): $e" $?
  ok=0; for l in '**Questions**' '**Measure**' '**Default**' '**Why**' '**Sensor**' '**Opinion**'; do printf '%s\n' "$sec" | qgrep -F -- "$l" || ok=1; done
  check "catalog $e: has the six labels" $ok
  printf '%s\n' "$sec" | qgrep -F -- "$ST"; check "catalog $e: marked unproven (D50)" $?
  [ "$e" = test-conventions ] || { printf '%s\n' "$sec" | qgrep 'https://'; check "catalog $e: cites a URL" $?; }
done
[ "$(grep -cF -- "$ST" "$C")" -eq 15 ]; check "catalog: exactly the 15 D44 entries carry the unproven status" $?
[ "$(wc -l < "$C")" -le 300 ]; check "catalog stays at most 300 lines (else split it into references/catalog/)" $?
for e in comments suppressions error-handling logging; do
  awk -v h="## $e" '$0 == h { p = 1; next } /^## / { p = 0 } p' "$C" | qgrep -F 'contracts/rule-env.md'; check "catalog $e: the Sensor names the preset in contracts/rule-env.md" $?
  has "$CT" "### $e"; check "rule-env.md documents the $e preset" $?
done
awk '/^## dependencies$/{p=1;next} /^## /{p=0} p' "$C" | qgrep -F 'dependencies.sh'; check "catalog dependencies: the Sensor is dependencies.sh" $?
[ -f "$root/plugins/keel-harness/assets/core/sensors/rules/dependencies.sh" ]; check "dependencies.sh ships under assets/core/sensors/rules" $?
awk '/^## type-strictness$/{p=1;next} /^## /{p=0} p' "$C" | qgrep -F 'guard'; check "catalog type-strictness: the Sensor is guard" $?
awk '/^## function-size$/{p=1;next} /^## /{p=0} p' "$C" | qgrep -iF 'no study'; check "catalog function-size: says no study backs an exact number" $?
awk '/^## test-conventions$/{p=1;next} /^## /{p=0} p' "$C" | qgrep -F 'test-presence' && awk '/^## test-conventions$/{p=1;next} /^## /{p=0} p' "$C" | qgrep -F 'folder-layout'; check "catalog test-conventions: no new sensor, test-presence and folder-layout" $?
has "$CT" 'measure.sh deps'; check "rule-env.md documents measure.sh deps" $?
exit $fail
