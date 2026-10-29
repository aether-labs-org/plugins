#!/usr/bin/env bash
# F5 Task 3 (C10, D47): the autonomous-run recipe is documentation only. It names concrete runners and
# keeps keel out of orchestration. Text checks: the recipe is prose, so the test pins what it must say.
# shellcheck disable=SC2319 # `check "..." $?` right after a [ ] test is this suite's idiom
set -uo pipefail
qgrep() { grep "$@" >/dev/null; } # reads all its input: `| grep -q` can SIGPIPE the writer under pipefail
. "$(dirname "$0")/keel_helpers.sh"
RA="$KEEL/assets/core/README.agents.md"
RM="$KEEL/README.md"

# section NAME FILE -> the text from the "## NAME" heading to the next "## " heading
section() { awk -v h="## $1" '$0 == h { on = 1; print; next } on && /^## / { exit } on { print }' "$2"; }

# ------------------------------------------------------------------ the short recipe in the installed README
ra="$(section 'Autonomous runs' "$RA")"
[ -n "$ra" ]; check "README.agents.md has an '## Autonomous runs' section" $?
[ "$(printf '%s\n' "$ra" | wc -l | tr -d ' ')" -le 30 ]; check "README.agents.md: the recipe is short (at most 30 lines)" $?
for k in 'executing-plans' 'subagent-driven-development' 'Agent SDK' 'claude -p' '.agents/plans/' 'Acceptance' '.agents/progress.md' 'make gate-fast' 'reviewer' 'evaluator' 'stateless'; do
  printf '%s\n' "$ra" | qgrep -F -- "$k"; check "README.agents.md recipe mentions: $k" $?
done
printf '%s\n' "$ra" | qgrep -i 'keel orchestrates nothing'; check "README.agents.md recipe says keel orchestrates nothing" $?
! printf '%s\n' "$ra" | qgrep -E 'CLAUDE_|keel-harness/'; check "README.agents.md recipe cites no path into the plugin (it runs with the plugin absent)" $?
printf '%s\n' "$ra" | qgrep -i 'experimental'; check "README.agents.md recipe marks the reviewer experimental" $?

# ------------------------------------------------------------------ the full recipe in the plugin README
rm_="$(section 'Autonomous runs (profile L)' "$RM")"
[ -n "$rm_" ]; check "plugin README has an '## Autonomous runs (profile L)' section" $?
for k in 'executing-plans' 'subagent-driven-development' 'Agent SDK' 'claude -p' '.agents/plans/' 'Acceptance' '.agents/progress.md' 'stateless' 'read-heavy' 'make gate-fast' 'make gate-slow' 'REVIEWER_CMD' 'evaluator subagent' 'journey'; do
  printf '%s\n' "$rm_" | qgrep -F -- "$k"; check "plugin README recipe mentions: $k" $?
done
printf '%s\n' "$rm_" | qgrep -i 'keel orchestrates nothing'; check "plugin README recipe says keel orchestrates nothing" $?
printf '%s\n' "$rm_" | qgrep 'D47'; check "plugin README recipe cites D47" $?
# the recipe's order: planner pass, main loop, gate after each step, reviewer at the end, progress across sessions
order="$(printf '%s\n' "$rm_" | grep -n -iE 'planner|main loop|gate after|reviewer sensor or|progress\.md' | cut -d: -f1 | tr '\n' ' ')"
[ "$(printf '%s\n' "$order" | wc -w | tr -d ' ')" -ge 5 ]; check "plugin README recipe has the five steps" $?
printf '%s\n' "$rm_" | qgrep -i 'experimental'; check "plugin README recipe marks profile L experimental" $?
qgrep 'D52' "$RM"; check "plugin README explains the D52 rule for profile L" $?
section 'Profile L (experimental)' "$RM" | qgrep 'Δ > 0'; check "plugin README says each profile L component ships only with a measured gain (Δ > 0)" $?
section 'Profile L (experimental)' "$RM" | qgrep -E 'reviewer-catches-violation'; check "plugin README names the reviewer eval cases" $?
section 'Profile L (experimental)' "$RM" | qgrep -E 'journey-catches-regression'; check "plugin README names the journey eval case" $?
section 'Profile L (experimental)' "$RM" | qgrep -iE 'diff.*(leaves|sent)|leave the machine'; check "plugin README says the reviewer sends the diff to the configured command" $?

# ------------------------------------------------------------------ keel does not orchestrate
! find "$KEEL/assets" "$KEEL/scripts" -type f | qgrep -iE 'orchestrat|planner|subagent|runner'; check "no asset or script is an orchestrator, planner or runner" $?
! grep -rniE 'executing-plans|subagent-driven-development' "$KEEL/assets" "$KEEL/scripts" --include='*.sh' | qgrep .; check "no installed script calls a runner" $?
finish
