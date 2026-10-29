#!/usr/bin/env bash
# E2: every eval case belongs to one grant group, lists the tools it needs, and grades "writes
# nothing" from tool calls, not from files (Claude Code's Bash tool creates .claude/.cc-writes/).
set -uo pipefail
qgrep() { grep "$@" >/dev/null; } # reads all its input: `| grep -q` can SIGPIPE the writer under pipefail
. "$(dirname "$0")/keel_helpers.sh"
EV="$KEEL/evals"
tags_of() { grep -h '^tags:' "$1/case.yaml" "$1/prompt.md" 2>/dev/null | head -1; }
tools_of() { grep -h '^allowed_tools:' "$1/prompt.md" | head -1; }

! grep -rqE 'path: "?\*\*/\*"?$' "$EV"/*/graders; check "no grader counts every created file (file_exists **/*)" $?
for d in "$EV"/*/; do
  c="$(basename "$d")"; t="$(tags_of "$d")"; a="$(tools_of "$d")"
  n=0; g=""
  for x in readonly bash tools effect; do printf '%s' "$t" | qgrep -E "[[, ]$x[],]" && { n=$((n + 1)); g=$x; }; done
  [ "$n" = 1 ]; check "$c is in exactly one grant group (readonly | bash | tools | effect)" $?
  case "$g" in
    readonly) ! printf '%s' "$a" | qgrep -E '\b(Bash|Write|Edit)\b'; check "$c (readonly) lists no gated tool" $? ;;
    bash) printf '%s' "$a" | qgrep '\bBash\b' && ! printf '%s' "$a" | qgrep -E '\b(Write|Edit)\b'; check "$c (bash) lists Bash and no Write/Edit" $? ;;
    tools | effect) printf '%s' "$a" | qgrep '\bBash\b' && printf '%s' "$a" | qgrep '\bWrite\b'; check "$c ($g) lists Bash and Write" $? ;;
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
  [ -x "$d/scaffold.sh" ] && head -1 "$d/scaffold.sh" | qgrep '^#!/usr/bin/env bash'; check "$c has an executable bash scaffold" $?
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

# F5 (D52): profile-L cases, files only; the owner runs them. The reviewer pair is an effect pair like
# rules-effect-with/-without (the group checks above already require Bash and Write); the journey case is a tool case.
for a in with without; do
  c="reviewer-catches-violation-$a"; d="$EV/$c"
  [ -f "$d/case.yaml" ] && [ -f "$d/prompt.md" ] && [ -x "$d/scaffold.sh" ]; check "$c has case.yaml, prompt.md and an executable scaffold.sh" $?
  grep -q "^name: $c\$" "$d/case.yaml" 2>/dev/null; check "$c carries its name" $?
  grep -q '^tags: \[profile-l, effect\]$' "$d/case.yaml" 2>/dev/null; check "$c is tagged [profile-l, effect]" $?
  grep -q 'ablation none' "$d/case.yaml" 2>/dev/null; check "$c says to run with --ablation none and compare by hand" $?
  grep -q 'D52' "$d/case.yaml" 2>/dev/null; check "$c is marked experimental (D52)" $?
done
diff -r "$EV/reviewer-catches-violation-with/graders" "$EV/reviewer-catches-violation-without/graders" >/dev/null; check "reviewer-catches-violation: both arms are graded by the same graders" $?
diff "$EV/reviewer-catches-violation-with/prompt.md" "$EV/reviewer-catches-violation-without/prompt.md" >/dev/null; check "reviewer-catches-violation: both arms get the same prompt" $?
grep -q 'make gate-slow' "$EV/reviewer-catches-violation-with/prompt.md"; check "reviewer-catches-violation: the prompt runs make gate-slow" $?
grep -q 'reviewer' "$EV/reviewer-catches-violation-with/scaffold.sh" && ! grep -qi 'reviewer' "$EV/reviewer-catches-violation-without/scaffold.sh"; check "reviewer-catches-violation: only the -with arm installs the reviewer sensor" $?
grep -q 'KEEL_EVAL_REVIEWER_CMD' "$EV/reviewer-catches-violation-with/scaffold.sh" && grep -q '<a model other than the one that codes>' "$EV/reviewer-catches-violation-with/scaffold.sh"; check "reviewer-catches-violation-with: the command is the host's, with a placeholder instead of a model name" $?
grep -q 'reviewer' "$EV/reviewer-catches-violation-with/graders/reviewer-fails.md" && grep -q 'type: regex' "$EV/reviewer-catches-violation-with/graders/reviewer-fails.md"; check "reviewer-catches-violation: a grader reads the reviewer's line in the gate output" $?
grep -q 'type: tool_used' "$EV/reviewer-catches-violation-with/graders/ran-gate-slow.md"; check "reviewer-catches-violation: a grader checks that make gate-slow ran" $?
d="$EV/journey-catches-regression"
[ -f "$d/case.yaml" ] && [ -f "$d/prompt.md" ] && [ -x "$d/scaffold.sh" ]; check "journey-catches-regression has case.yaml, prompt.md and an executable scaffold.sh" $?
grep -q '^name: journey-catches-regression$' "$d/case.yaml" && grep -q '^tags: \[profile-l, tools\]$' "$d/case.yaml"; check "journey-catches-regression is named and tagged [profile-l, tools]" $?
grep -q 'make gate-slow' "$d/prompt.md"; check "journey-catches-regression: the prompt runs make gate-slow" $?
for g in journey-fails names-the-journey gives-the-trace ran-gate-slow; do
  [ -f "$d/graders/$g.md" ]; check "journey-catches-regression has the $g grader" $?
done
grep -q '@playwright/test' "$d/scaffold.sh" && grep -q 'count += 2' "$d/scaffold.sh"; check "journey-catches-regression: Playwright fixture with a planted regression" $?
grep -q 'reviewer-catches-violation-with. / .-without. (F5' "$KEEL/README.md" && grep -q 'journey-catches-regression. (F5' "$KEEL/README.md" && grep -q 'KEEL_EVAL_REVIEWER_CMD' "$KEEL/README.md"; check "README lists the host prerequisites of the F5 cases, and that the reviewer arm is a billed model call" $?
! grep -rniE '\b(opus|sonnet|haiku)\b|claude-[0-9]' "$EV/reviewer-catches-violation-with" "$EV/reviewer-catches-violation-without" "$EV/journey-catches-regression" >/dev/null; check "no model name in the F5 eval cases" $?

# The scaffolds really build what they describe: run them with the stub as the reviewer (no network, no model).
# The journey scaffold needs npm and the network, so it is not run here.
if command -v git >/dev/null 2>&1; then
  for a in with without; do
    w="$(mktemp -d)"; _keel_tmps="$_keel_tmps $w"
    (cd "$w" && KEEL_EVAL_REVIEWER_CMD="$FIXTURES/reviewer/stub-reviewer.sh" bash "$EV/reviewer-catches-violation-$a/scaffold.sh" >/dev/null 2>&1); rc=$?
    [ "$rc" -eq 0 ] && [ -f "$w/src/app.ts" ]; check "reviewer-catches-violation-$a: scaffold.sh builds the repository" $?
    (cd "$w" && git diff --name-only | qgrep -x 'src/app.ts'); check "reviewer-catches-violation-$a: the violation is the one uncommitted change" $?
    gout="$(cd "$w" && bash scripts/gate.sh slow 2>&1)"; grc=$?
    if [ "$a" = with ]; then
      [ "$grc" -ne 0 ] && printf '%s\n' "$gout" | qgrep -E 'reviewer +\[heuristic +\] +[0-9]+ rule violation'; check "reviewer-catches-violation-with: the slow gate fails on the planted violation (stub reviewer)" $?
      printf '%s\n' "$gout" | qgrep -E 'reviewer.*rule violation' && printf '%s\n' "$gout" | qgrep 'no-console'; check "reviewer-catches-violation-with: the output matches the graders' patterns" $?
    else
      [ "$grc" -eq 0 ] && printf '%s\n' "$gout" | qgrep 'gate: slow - PASSED' && ! printf '%s\n' "$gout" | qgrep 'reviewer'; check "reviewer-catches-violation-without: the slow gate passes and says nothing about the violation" $?
    fi
  done
fi
finish
