#!/usr/bin/env bash
# keel-harness v0.5 templates: the keel.yml of each stack validates and checks clean with the built kh,
# settings.json matches the hook contract, the guides stay small, the git hooks are POSIX sh.
# shellcheck disable=SC2319  # "check ... $?" after a test is this suite's idiom (see keel_helpers.sh)
set -uo pipefail
. "$(dirname "$0")/keel_helpers.sh"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$REPO_ROOT/plugins/keel-harness/skills/harness/templates"
FX="$REPO_ROOT/tests/fixtures/keel-v05"
W="$(mktemp -d)"; _keel_tmps="$_keel_tmps $W"
SHEBANG='#!/bin/sh'

# ------------------------------------------------------------------ static checks
[ "$(cat "$T/CLAUDE.md")" = "@AGENTS.md" ] && [ "$(wc -c < "$T/CLAUDE.md" | tr -d ' ')" -eq 11 ]; check "CLAUDE.md is exactly @AGENTS.md and a newline" $?
[ "$(wc -l < "$T/AGENTS.md" | tr -d ' ')" -le 100 ]; check "AGENTS.md template is at most 100 lines" $?
[ "$(wc -l < "$T/nested-AGENTS.md" | tr -d ' ')" -le 100 ]; check "nested AGENTS.md template is at most 100 lines" $?
heads="$(grep -E '^## ' "$T/AGENTS.md" | tr '\n' '|')"
[ "$heads" = "## Setup|## Commands|## Working|## Boundaries|## Before you finish|## Pointers|" ]; check "AGENTS.md sections in order: Setup, Commands, Working, Boundaries, Before you finish, Pointers" $?
grep -q 'sh .agents/bin/kh setup' "$T/AGENTS.md" && grep -qi 'ask the human whether to run the independent review' "$T/AGENTS.md" && grep -q 'friction with evidence, not a security boundary' "$T/AGENTS.md"; check "AGENTS.md: setup command, the review question and the declared limit" $?
! grep -rn '/keel-harness:' "$T" >/dev/null; check "no template contains /keel-harness:" $?
python3 -I -m json.tool "$T/settings.json" >/dev/null; check "settings.json parses" $?
python3 -I -c '
import json, sys
d = json.load(open(sys.argv[1]))["hooks"]
pre = d["PreToolUse"][0]
assert pre["matcher"] == "Write|Edit|MultiEdit|NotebookEdit|Bash", pre["matcher"]
cmd = pre["hooks"][0]
assert cmd["command"] == "sh \"$(git rev-parse --show-toplevel)/.agents/bin/kh\" hook pre-tool-use" and cmd["timeout"] == 10
stop = d["Stop"][0]["hooks"][0]
assert stop["command"] == "sh \"$(git rev-parse --show-toplevel)/.agents/bin/kh\" hook stop" and stop["timeout"] == 120
' "$T/settings.json"
check "settings.json: PreToolUse matcher, Stop entry, commands and timeouts match the hook contract" $?
for h in pre-commit commit-msg pre-push; do
  [ "$(head -1 "$T/githooks/$h")" = "$SHEBANG" ]; check "githooks/$h starts with the sh shebang" $?
  if command -v dash >/dev/null 2>&1; then dash -n "$T/githooks/$h"; else sh -n "$T/githooks/$h"; fi; check "githooks/$h is POSIX sh (dash -n)" $?
  [ -x "$T/githooks/$h" ]; check "githooks/$h is executable" $?
done
grep -q 'gate commit' "$T/githooks/pre-commit" && grep -q 'hook commit-msg "\$1"' "$T/githooks/commit-msg" && grep -q 'gate slow' "$T/githooks/pre-push"; check "githooks call the commit gate, the commit-msg hook and the slow gate" $?
for f in keel-reviewer.claude.md keel-reviewer.agent.md; do
  [ "$(head -1 "$T/$f")" = "---" ] && grep -q '^name: keel-reviewer$' "$T/$f" && grep -q '^description: ' "$T/$f" && grep -q '^tools: ' "$T/$f" && grep -q 'docs/review.md' "$T/$f" && grep -q 'Change nothing' "$T/$f"; check "$f: frontmatter name/description/tools, applies docs/review.md, changes nothing" $?
done
grep -qi 'read-only' "$T/keel-reviewer.claude.md" && grep -qi 'read-only' "$T/keel-reviewer.agent.md"; check "reviewer definitions say the git commands are read-only" $?
for f in review.md adr.md adr-0001.md plan.md progress.md lessons.md pull_request_template.md gitignore.txt; do [ -s "$T/$f" ]; check "template $f exists" $?; done
grep -q '^\.agents/run/$' "$T/gitignore.txt"; check "gitignore.txt ignores .agents/run/" $?
grep -qx 'Status: active' "$T/plan.md" && grep -q '^Scope: ' "$T/plan.md" && grep -q '^## Acceptance' "$T/plan.md"; check "plan.md has Status, Scope and Acceptance" $?
grep -q '^Status: accepted' "$T/adr-0001.md" && grep -q '^Status: ' "$T/adr.md"; check "ADR templates carry a Status line" $?

# architecture templates: 3 tools x 4 styles
for st in hexagonal layered clean modular; do
  for f in "dependency-cruiser-$st.cjs" "import-linter-$st.toml" "archunit-$st.java"; do [ -s "$T/architecture/$f" ]; check "architecture/$f exists" $?; done
  if command -v node >/dev/null 2>&1; then node -e 'require(process.argv[1])' "$T/architecture/dependency-cruiser-$st.cjs"; check "dependency-cruiser-$st.cjs loads with node" $?; fi
  python3 -I -c 'import tomllib,sys;tomllib.load(open(sys.argv[1],"rb"))' "$T/architecture/import-linter-$st.toml"; check "import-linter-$st.toml parses as TOML" $?
done
grep -q 'classes_are_analysed' "$T/architecture/archunit-hexagonal.java"; check "archunit template keeps the guard rule that fails when no class is analysed" $?

# ------------------------------------------------------------------ the built kh validates and checks each stack
if ! command -v go >/dev/null 2>&1; then
  if [ -n "${CI:-}" ]; then fail "templates: go is required in CI"; finish; fi
  echo "  skip templates: go not installed (kh not built)"; finish
fi
KH="$W/kh"
(cd "$REPO_ROOT/cli/kh" && CGO_ENABLED=0 go build -trimpath -buildvcs=false -o "$KH" .) 2>&1 | cat
[ "${PIPESTATUS[0]}" -eq 0 ]; check "kh builds" $?
[ -x "$KH" ] || finish

for stack in typescript python jvm; do
  r="$W/$stack"; mkdir -p "$r"; cp -R "$FX/$stack/." "$r/"
  mkdir -p "$r/.agents" "$r/docs" "$r/.claude/agents" "$r/.github/agents"
  cp "$T/keel-$stack.yml" "$r/.agents/keel.yml"
  cp "$T/AGENTS.md" "$T/CLAUDE.md" "$r/"
  cp "$T/review.md" "$r/docs/review.md"
  cp "$T/keel-reviewer.claude.md" "$r/.claude/agents/keel-reviewer.md"
  cp "$T/keel-reviewer.agent.md" "$r/.github/agents/keel-reviewer.agent.md"
  cp "$T/settings.json" "$r/.claude/settings.json"
  cp "$T/gitignore.txt" "$r/.gitignore"
  (cd "$r" && git init -q . && git config user.email t@t && git config user.name t && git add -A && git commit -q -m "seed")
  out="$(cd "$r" && "$KH" validate 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && [ -z "$out" ]; check "$stack: keel-$stack.yml passes kh validate" $?
  [ "$rc" -eq 0 ] || printf '%s\n' "$out"
  out="$(cd "$r" && "$KH" check 2>&1)"; rc=$?
  extra="$(printf '%s\n' "$out" | grep '^warn ' | grep -vE '^warn (githooks-inactive|script-unavailable):' || true)"
  [ "$rc" -eq 0 ] && [ -z "$extra" ]; check "$stack: kh check reports only githooks-inactive and script-unavailable" $?
  [ -z "$extra" ] || printf '%s\n' "$extra"
  printf '%s\n' "$out" | grep -q '^warn githooks-inactive:'; check "$stack: githooks-inactive is reported until kh setup runs" $?
done

finish
