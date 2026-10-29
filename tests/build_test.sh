#!/usr/bin/env bash
set -uo pipefail
fail=0
check() { if [ "$2" -eq 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fail=1; fi; }
root="$(cd "$(dirname "$0")/.." && pwd)"
sk="$root/plugins/keel-harness/skills/build"
S="$sk/SKILL.md"
C="$root/plugins/keel-harness/contracts/sensor.md"
has() { grep -qF -- "$2" "$1" 2>/dev/null; }

[ -f "$sk/references/agents-md-template.md" ]; check "agents-md-template.md exists" $?
! grep -q "120" "$sk/references/agents-md-template.md" 2>/dev/null; check "template ceiling is not 120" $?
grep -q "100" "$sk/references/agents-md-template.md" 2>/dev/null; check "template ceiling is 100" $?
[ -f "$sk/references/context-engineering.md" ]; check "context-engineering.md copied" $?

# --- Task 4: build installs bundled assets
for s in '${CLAUDE_PLUGIN_ROOT}/assets/core/gate.sh' 'keel:repo-specific' 'KEEL_MEASURE=1' 'schema_version: 2' \
         'harness_review_by' 'gate.env' 'gate-slow' 'AskUserQuestion' 'at most 4 questions' \
         'before writing anything' 'installed_at' 'not_installed' 'resumable' '100 lines'; do
  has "$S" "$s"; check "SKILL.md contains: $s" $?
done
grep -qi "never invent" "$S"; check "SKILL.md keeps the never-invent-commands rule" $?
for s in model_baseline byte-for-byte 'sensors:'; do
  ! has "$S" "$s"; check "SKILL.md does not contain: $s" $?
done
[ "$(wc -l < "$S")" -le 250 ]; check "SKILL.md is at most 250 lines" $?
! grep -qE "instalado_em|camadas|nao_instaladas|classe:|revisar_em" "$S"; check "state keys are English" $?

[ -f "$C" ]; check "contracts/sensor.md exists" $?
! grep -qE '^#!/usr/bin/env bash' "$C"; check "contract embeds no script" $?
for s in 'scripts/sensors/slow/' '.agents/baselines/' 'KEEL_MEASURE' 'FreezingArchRule'; do
  has "$C" "$s"; check "contract contains: $s" $?
done
grep -qE 'security.*never.*baseline' "$C"; check "contract: security never reads a baseline" $?
for field in "pass signal" "guidance" "scope" "class" "cost" "ceiling" "verbosity"; do
  grep -qi "$field" "$C"; check "contract field: $field" $?
done
for cls in security correctness heuristic; do grep -q "$cls" "$C"; check "contract class: $cls" $?; done
has "$C" review_by; check "baselines expire (review_by)" $?

[ -f "$sk/references/sensors-by-language.md" ]; check "sensors-by-language.md exists" $?
grep -q "GitLeaks" "$sk/references/sensors-by-language.md"; check "secret scanner named" $?
grep -qi "names tools, never commands" "$sk/references/sensors-by-language.md"; check "language table states the tools-not-commands rule" $?

grep -q "gate-fast" "$S"; check "SKILL.md writes the gate-fast target" $?

# --- Task 6: Stop hook and v0.1 upgrade
for s in 'settings-stop.json' '"timeout": 120' 'claude-stop.sh' 'replaces the v0.1 PostToolUse entry' \
         '.agents/plans/' '${CLAUDE_PROJECT_DIR}'; do
  has "$S" "$s"; check "SKILL.md contains: $s" $?
done
# F2c-3: the v0.2/v0.1 upgrade round moved out of SKILL.md into references/upgrade.md
U="$sk/references/upgrade.md"
has "$U" '.agents/.gate-lock/'; check "upgrade.md contains: .agents/.gate-lock/" $?
has "$S" 'references/upgrade.md'; check "SKILL.md points at references/upgrade.md" $?
# F2c-3: the discovery commands moved out of SKILL.md into references/discovery.md
D="$sk/references/discovery.md"
has "$S" 'references/discovery.md' && has "$D" 'ls mvnw gradlew' && has "$D" 'grep -E "^[a-zA-Z_-]+:" Makefile'; check "discovery commands live in references/discovery.md, which SKILL.md names" $?
! grep -q '"PostToolUse"' "$S"; check "SKILL.md has no JSON block keyed PostToolUse" $?
[ -f "$root/plugins/keel-harness/evals/build-typescript/graders/stop-hook.md" ]; check "stop-hook grader exists" $?

# --- Task 7: template v2, CLAUDE.md bridge, ADR path
T="$sk/references/agents-md-template.md"
for s in '## Commands' '## Before you finish' '## Rules' 'make gate-slow'; do has "$T" "$s"; check "template has: $s" $?; done
for s in 'File map' 'Docs Index' 'Metrics' 'Schemas & contracts'; do ! has "$T" "$s"; check "template lacks: $s" $?; done
has "$S" '@AGENTS.md' && has "$S" '.claude/CLAUDE.md'; check "SKILL.md has the CLAUDE.md bridge" $?
CE="$sk/references/context-engineering.md"
! has "$CE" '150–200'; check "context-engineering drops the unsourced instruction count" $?
has "$CE" '2602.11988'; check "context-engineering cites arXiv 2602.11988" $?
has "$S" '.agents/run/'; check "build ignores .agents/run/" $?
has "$S" 'schema_version: 3'; check "build writes schema_version: 3" $?
g="$root/plugins/keel-harness/evals/build-typescript/graders"
[ -f "$g/claude-md-import.md" ] && [ -f "$g/linecount-measured.md" ]; check "claude-md-import and linecount-measured graders exist" $?
! grep -q "PreToolUse" "$S"; check "SKILL.md installs no blocking hook" $?

# --- Task 22: validator and guide are installed
for s in 'scripts/harness-check.sh' '.agents/README.md' 'harness-check: ; @bash scripts/harness-check.sh'; do
  has "$S" "$s"; check "SKILL.md contains: $s" $?
done
has "$U" 'make harness-check'; check "upgrade.md contains: make harness-check (F2c-3: the upgrade round moved there)" $?
[ "$(wc -l < "$S")" -le 250 ]; check "SKILL.md still at most 250 lines" $?

# --- F2c-2: the order is enforced by scripts/keel; the prose checklist of section 10 is gone
for s in 'scripts/keel check pre build' 'scripts/keel plan build' 'keel approve build' 'scripts/keel apply build' 'scripts/keel verify build' \
         'before the first write' 'the acceptance came from the request'; do
  has "$S" "$s"; check "SKILL.md calls keel: $s" $?
done
[ "$(grep -c '^- \[ \]' "$S")" -eq 0 ]; check "SKILL.md keeps no '- [ ]' checklist (keel verify build replaces it)" $?
[ "$(wc -l < "$S")" -le 245 ]; check "SKILL.md is well under 250 lines after the keel wiring" $?
has "$S" 'Every command cited in `AGENTS.md` really exists' && has "$S" '→ docs/X.md` pointers.'; check "SKILL.md keeps the two checks keel cannot make" $?

# --- Task 20: stacks
L="$sk/references/sensors-by-language.md"
for st in 'TypeScript / Node — *actionable*' 'React — *actionable*' 'Python — *actionable*' 'Java / Kotlin (Spring) — *actionable*'; do
  has "$L" "$st"; check "stack is actionable: $st" $?
done
for st in 'Go — *documentation only*' 'Terraform — *documentation only*'; do has "$L" "$st"; check "stack stays documentation only: $st" $?; done
has "$S" 'React' && has "$S" 'sensors/typescript/'; check "SKILL.md stack table maps React to sensors/typescript/" $?
has "$L" 'Stryker' && has "$L" 'dependency-cruiser'; check "React notes mention Stryker and dependency-cruiser" $?
for c in build-python build-java build-react; do
  e="$root/plugins/keel-harness/evals/$c"
  [ -f "$e/case.yaml" ] && [ -f "$e/prompt.md" ] && [ -f "$e/scaffold.sh" ] && [ "$(ls "$e/graders" | wc -l)" -ge 5 ]; check "eval $c exists with graders" $?
  bash -n "$e/scaffold.sh"; check "eval $c scaffold parses" $?
done
grep -q 'ruff' "$root/plugins/keel-harness/evals/build-python/graders/lint-is-ruff.md" 2>/dev/null; check "build-python checks that lint uses ruff" $?
grep -q 'LINT_PATHS' "$root/plugins/keel-harness/evals/build-react/graders/lint-paths.md" 2>/dev/null; check "build-react checks LINT_PATHS" $?
E="$root/plugins/keel-harness/skills/build/references/enforcement.md"
has "$S" 'references/enforcement.md'; check "build proposes the ci and precommit layers (F3a)" $?
for t in 'assets/core/ci/keel.yml' 'KEEL_GUARD_BASE' 'never a new one' 'required'; do has "$E" "$t"; check "enforcement.md: $t" $?; done

# --- F3b: plans and progress are versioned (D6 revised)
! grep -qE 'and `\.agents/plans/` to `\.gitignore`|`\.agents/plans/` in `\.gitignore`' "$S"; check "build no longer adds .agents/plans/ to .gitignore" $?
has "$S" 'versioned, not ignored'; check "build says plans and progress are versioned, not ignored" $?
has "$S" '.agents/progress.md'; check "build creates .agents/progress.md" $?
has "$sk/references/upgrade.md" '`.agents/plans/` line in `.gitignore`'; check "upgrade.md proposes removing an existing .agents/plans/ line" $?
has "$sk/references/agents-md-template.md" 'Progress across sessions → .agents/progress.md'; check "AGENTS.md template points at .agents/progress.md" $?
tl="$(awk '/^```markdown$/{t=1;next} /^```$/{t=0} t' "$sk/references/agents-md-template.md" | wc -l | tr -d ' ')"
[ "$tl" -le 100 ]; check "the rendered AGENTS.md template stays within 100 lines ($tl)" $?
! grep -rqi 'plans.*gitignored\|gitignored.*plans' "$root/plugins/keel-harness" --include=*.md --include=*.sh; check "nothing in the plugin says plans are gitignored" $?
! grep -q 'plans/' "$root/plugins/keel-harness/assets/core/gate.sh" 2>/dev/null; check "gate.sh does not touch .agents/plans/" $?
[ ! -e "$root/plugins/keel-harness/evals/rules-brownfield/graders/gitignore-plans.md" ]; check "the brownfield eval no longer expects .agents/plans/ in .gitignore" $?
has "$root/plugins/keel-harness/evals/rules-brownfield/graders/plan-acceptance.md" '## Acceptance'; check "the brownfield eval expects an Acceptance section in the plan" $?
# --- F2d (D42): the LSP proposal, names only from the cited official docs
CE="$sk/references/context-engineering.md"
for t in 'https://code.claude.com/docs/en/discover-plugins' 'https://code.claude.com/docs/en/plugins-reference' 'https://code.claude.com/docs/en/plugins/code-intelligence.md' 'read on 2026-10-29' 'no official LSP plugin found (2026-10-29)'; do
  has "$CE" "$t"; check "context-engineering.md cites: $t" $?
done
for p in typescript-lsp pyright-lsp jdtls-lsp kotlin-lsp gopls-lsp rust-analyzer-lsp; do
  grep -qF "| \`$p\` |" "$CE"; check "LSP table row: $p" $?
  has "$CE" "/plugin install $p@claude-plugins-official"; check "LSP table install command: $p" $?
done
# every *-lsp name the skill and its references use is one the official page lists (the 13 on 2026-10-29)
official=" clangd-lsp csharp-lsp gopls-lsp jdtls-lsp kotlin-lsp liquid-lsp lua-lsp php-lsp pyright-lsp ruby-lsp rust-analyzer-lsp swift-lsp typescript-lsp "
bad=""
for n in $(grep -rhoE '[a-z][a-z-]*-lsp' "$S" "$CE" | sort -u); do
  case "$official" in *" $n "*) ;; *) bad="$bad $n" ;; esac
done
[ -z "$bad" ]; check "no invented LSP plugin name in build ($bad)" $?
grep -qE '^Propose the stack.s official LSP plugin' "$S" && has "$S" 'own accept-or-decline item' && has "$S" '`lsp` under `not_installed`'; check "guides phase proposes the LSP plugin as a separate item and records a decline under not_installed" $?
awk '/^### Phase 2 - guides/{p=1} /^### Phase 3/{p=0} p' "$S" | grep -q 'official LSP plugin'; check "the LSP line is in the guides phase" $?
has "$root/plugins/keel-harness/contracts/state.md" '`lsp`'; check "contracts/state.md documents the lsp not_installed key" $?
# --- F3c-1: the authority layer (consequence map, protect hook, CODEOWNERS)
AU="$sk/references/authority.md"
[ -f "$AU" ]; check "references/authority.md exists" $?
for t in 'references/authority.md' 'scripts/hooks/claude-protect.sh' '.agents/consequence.yml' 'Never invent an owner' 'authority'; do
  has "$S" "$t"; check "SKILL.md contains: $t" $?
done
has "$S" 'AUTHORITY  '; check "SKILL.md proposal block has an AUTHORITY line" $?
has "$S" 'authority: installed'; check "SKILL.md state example records authority: installed" $?
[ "$(wc -l < "$S")" -le 245 ]; check "SKILL.md still at most 245 lines with the authority phase" $?
for t in 'assets/core/consequence.yml' 'settings-protect.json' 'claude-protect.sh' 'CODEOWNERS' 'never invent an owner' 'Never add a line for a path nothing' \
         'code.claude.com/docs/en/permissions' 'code.claude.com/docs/en/hooks' 'notebook_path' '_source' 'protect-missing' 'Known limit' \
         'a line they do not answer stays out' 'Require review from Code Owners' 'git ls-files'; do
  grep -qiF -- "$t" "$AU"; check "authority.md: $t" $?
done
for t in 'Long autonomous sessions (profile L)' 'keel installs nothing for this' 'https://code.claude.com/docs/en/sandboxing' 'https://code.claude.com/docs/en/devcontainer' \
         'covers shell commands only' 'sandbox.filesystem.denyWrite' 'allowUnsandboxedCommands' 'failIfUnavailable' 'init-firewall.sh' 'dangerously-skip-permissions'; do
  grep -qF -- "$t" "$AU"; check "authority.md sandbox section: $t" $?
done
! grep -q 'PostToolUse' "$sk/references/authority.md"; check "authority.md installs no PostToolUse hook" $?
! grep -qE '@[A-Za-z][A-Za-z0-9_-]+' "$AU" || ! grep -E '@[A-Za-z][A-Za-z0-9_-]+' "$AU" | grep -vE '@(user|org/team)|@\{\{' | grep -q .; check "authority.md names no real owner (only @user, @org/team placeholders)" $?
grep -q 'authority' "$root/plugins/keel-harness/skills/assess/references/checks.md" && grep -q 'protect-missing' "$root/plugins/keel-harness/skills/assess/references/checks.md"; check "checks.md lists protect-missing" $?
exit $fail
