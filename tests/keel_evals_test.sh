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
finish
