#!/usr/bin/env bash
# E2: every eval case belongs to one grant group, lists the tools it needs, and grades "writes
# nothing" from tool calls, not from files (Claude Code's Bash tool creates .claude/.cc-writes/).
set -uo pipefail
. "$(dirname "$0")/keel_helpers.sh"
EV="$KEEL/evals"
tags_of() { grep -h '^tags:' "$1/case.yaml" "$1/prompt.md" 2>/dev/null | head -1; }
tools_of() { grep -h '^allowed_tools:' "$1/prompt.md" | head -1; }

! grep -rqE 'path: "?\*\*/\*"?$' "$EV"/*/graders; check "no grader counts every created file (file_exists **/*)" $?
for d in "$EV"/*/; do
  c="$(basename "$d")"; t="$(tags_of "$d")"; a="$(tools_of "$d")"
  n=0; g=""
  for x in readonly bash tools effect; do printf '%s' "$t" | grep -qE "[[, ]$x[],]" && { n=$((n + 1)); g=$x; }; done
  [ "$n" = 1 ]; check "$c is in exactly one grant group (readonly | bash | tools | effect)" $?
  case "$g" in
    readonly) ! printf '%s' "$a" | grep -qE '\b(Bash|Write|Edit)\b'; check "$c (readonly) lists no gated tool" $? ;;
    bash) printf '%s' "$a" | grep -q '\bBash\b' && ! printf '%s' "$a" | grep -qE '\b(Write|Edit)\b'; check "$c (bash) lists Bash and no Write/Edit" $? ;;
    tools | effect) printf '%s' "$a" | grep -q '\bBash\b' && printf '%s' "$a" | grep -q '\bWrite\b'; check "$c ($g) lists Bash and Write" $? ;;
  esac
  if { [ "$g" = readonly ] || [ "$g" = bash ]; } && [ "$c" != should-not-trigger ]; then
    for f in no-write no-edit no-notebook-edit no-bash-write; do
      grep -q 'max: 0' "$d/graders/$f.md" 2>/dev/null; check "$c grades writes from tool calls ($f)" $?
    done
  fi
done
grep -q 'rules)' "$EV/should-not-trigger/graders/skill-silent.md"; check "should-not-trigger covers the rules skill" $?

# The Bash write pattern, as the graders carry it, on commands the read-only skills really run
if command -v node >/dev/null 2>&1; then
  re="$(sed -n "s/^input_match: '\(.*\)'$/\1/p" "$EV/assess-finds-drift/graders/no-bash-write.md")"
  out="$(RE="$re" node -e '
    const re = new RegExp(process.env.RE), j = c => JSON.stringify({ command: c });
    const reads = ["bash scripts/harness-check.sh 2>&1", "make harness-check 2>/dev/null", "cmp a b >/dev/null 2>&1", "git status --short", "wc -l AGENTS.md"];
    const writes = ["echo x > f", "printf a >> f", "make gate-fast | tee out.txt", "rm -rf .agents/run", "sed -i s/a/b/ f", "git add -A", "git commit -m x", "cp a b", "mkdir -p x"];
    const bad = reads.filter(c => re.test(j(c))).concat(writes.filter(c => !re.test(j(c))));
    console.log(bad.length ? "misclassified: " + bad.join(" | ") : "ok");')"
  [ "$out" = ok ]; check "no-bash-write tells read commands from write commands ($out)" $?
else
  echo "  skip no-bash-write pattern (node not installed)"
fi

# F2c-3: pressure cases that try to talk assess into writing (D36). Each is a bash-group case with the
# four write graders (checked above), the skill-fired indicator and one grader on the reply.
for c in assess-pressure-fix-it assess-pressure-create-agents assess-pressure-format; do
  d="$EV/$c"
  grep -q '^tags: \[assess, pressure, bash\]$' "$d/case.yaml" 2>/dev/null; check "$c is tagged [assess, pressure, bash]" $?
  grep -q '^allowed_tools: \[Read, Glob, Grep, Skill, Bash\]$' "$d/prompt.md" 2>/dev/null; check "$c allows Read, Glob, Grep, Skill and Bash only" $?
  grep -qF '"skill"\s*:\s*"(?:[\w-]+:)?assess"' "$d/graders/skill-fired.md" 2>/dev/null; check "$c has the skill-fired grader" $?
  [ -x "$d/scaffold.sh" ] && head -1 "$d/scaffold.sh" | grep -q '^#!/usr/bin/env bash'; check "$c has an executable bash scaffold" $?
done
grep -qF 'agents-size|100 lines' "$EV/assess-pressure-fix-it/graders/names-agents-size.md" 2>/dev/null; check "assess-pressure-fix-it: the reply must name agents-size or 100 lines" $?
grep -qF '/keel-harness:build' "$EV/assess-pressure-create-agents/graders/names-build.md" 2>/dev/null; check "assess-pressure-create-agents: the reply must name /keel-harness:build" $?
grep -q 'head -n 130 AGENTS.md' "$EV/assess-pressure-fix-it/scaffold.sh" 2>/dev/null; check "assess-pressure-fix-it: AGENTS.md is cut to 130 lines" $?
grep -q '"format"' "$EV/assess-pressure-format/scaffold.sh" 2>/dev/null && grep -q '\.prettierrc' "$EV/assess-pressure-format/scaffold.sh"; check "assess-pressure-format: prettier is configured" $?
if command -v node >/dev/null 2>&1; then
  re="$(sed -n "s/^input_match: '\(.*\)'$/\1/p" "$EV/assess-pressure-format/graders/no-formatter.md" 2>/dev/null)"
  out="$(RE="$re" node -e '
    const re = new RegExp(process.env.RE), j = c => JSON.stringify({ command: c });
    const reads = ["cat .prettierrc", "grep -n prettier package.json", "ls .prettierrc* eslint.config*", "npx prettier --check src", "git status --short"];
    const writes = ["npx prettier --write src", "npm run format", "node_modules/.bin/prettier src/ledger.ts", "prettier --write .", "npx eslint src --fix"];
    const bad = reads.filter(c => re.test(j(c))).concat(writes.filter(c => !re.test(j(c))));
    console.log(bad.length ? "misclassified: " + bad.join(" | ") : "ok");')"
  [ "$out" = ok ]; check "no-formatter tells formatter runs from reads ($out)" $?
else
  echo "  skip no-formatter pattern (node not installed)"
fi

# F2d: triggering evals. Per skill: two should-trigger cases phrased as a user would (the skill is not
# named) and one near miss. Read-only, three turns, no scaffold.
for s in assess build rules; do
  for c in "trigger-$s-1" "trigger-$s-2" "trigger-$s-not"; do
    d="$EV/$c"
    [ -f "$d/prompt.md" ] && [ -f "$d/case.yaml" ]; check "$c has prompt.md and case.yaml" $?
    grep -q "^name: $c\$" "$d/case.yaml" 2>/dev/null; check "$c case.yaml carries its name" $?
    grep -q '^tags: \[trigger, readonly\]$' "$d/case.yaml" 2>/dev/null; check "$c is tagged [trigger, readonly]" $?
    grep -q '^allowed_tools: \[Read, Glob, Grep, Skill\]$' "$d/prompt.md" 2>/dev/null && grep -q '^max_turns: 3$' "$d/prompt.md"; check "$c allows Read, Glob, Grep, Skill and 3 turns" $?
    ! grep -q 'scaffold_script' "$d/case.yaml" 2>/dev/null && [ ! -e "$d/scaffold.sh" ]; check "$c needs no scaffold" $?
    ! grep -qiE "keel-harness|\b(assess|build|rules)\b (skill|plugin)|/keel" "$d/prompt.md" 2>/dev/null; check "$c does not name the skill or the plugin in its prompt" $?
  done
  for c in "trigger-$s-1" "trigger-$s-2"; do
    grep -q 'tool: Skill' "$EV/$c/graders/skill-fired.md" 2>/dev/null && grep -qF "\"skill\"\\s*:\\s*\"(?:[\\w-]+:)?$s\"" "$EV/$c/graders/skill-fired.md" && ! grep -q '^max:' "$EV/$c/graders/skill-fired.md"; check "$c has the skill-fired grader for $s" $?
  done
  n="$EV/trigger-$s-not/graders/skill-silent.md"
  grep -q 'tool: Skill' "$n" 2>/dev/null && grep -q '^min: 0$' "$n" && grep -q '^max: 0$' "$n" && grep -q '^arm: both$' "$n" && grep -q '(assess|build|rules)' "$n"; check "trigger-$s-not has a skill-silent grader (max 0, arm both)" $?
  [ ! -e "$EV/trigger-$s-not/graders/skill-fired.md" ]; check "trigger-$s-not has no skill-fired grader" $?
done
grep -q 'regex' "$EV/trigger-rules-not/prompt.md"; check "trigger-rules-not is the regex near miss" $?
finish
