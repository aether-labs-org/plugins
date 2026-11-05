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
# a file named CLAUDE.md or AGENTS.md is loaded by the agents as instructions (Claude Code imported templates/CLAUDE.md, whose @AGENTS.md
# pulled the placeholder AGENTS.md into the session): no template carries those names, at any depth
[ -z "$(find "$T" \( -name CLAUDE.md -o -name AGENTS.md -o -name GEMINI.md -o -name copilot-instructions.md \) -print)" ]; check "templates: no file named CLAUDE.md, AGENTS.md or another auto-loaded instructions file" $?
[ -f "$T/CLAUDE.md.tmpl" ] && [ -f "$T/AGENTS.md.tmpl" ]; check "templates: CLAUDE.md.tmpl and AGENTS.md.tmpl exist" $?
[ "$(cat "$T/CLAUDE.md.tmpl")" = "@AGENTS.md" ] && [ "$(wc -c < "$T/CLAUDE.md.tmpl" | tr -d ' ')" -eq 11 ]; check "CLAUDE.md.tmpl is exactly @AGENTS.md and a newline" $?
[ "$(wc -l < "$T/AGENTS.md.tmpl" | tr -d ' ')" -le 100 ]; check "AGENTS.md.tmpl is at most 100 lines" $?
[ "$(wc -l < "$T/nested-AGENTS.md" | tr -d ' ')" -le 100 ]; check "nested AGENTS.md template is at most 100 lines" $?
heads="$(grep -E '^## ' "$T/AGENTS.md.tmpl" | tr '\n' '|')"
[ "$heads" = "## Setup|## Commands|## Working|## Boundaries|## Before you finish|## Pointers|" ]; check "AGENTS.md sections in order: Setup, Commands, Working, Boundaries, Before you finish, Pointers" $?
grep -q 'sh .agents/bin/kh setup' "$T/AGENTS.md.tmpl" && grep -qi 'ask the human whether to run the independent review' "$T/AGENTS.md.tmpl" && grep -q 'friction with evidence, not a security boundary' "$T/AGENTS.md.tmpl"; check "AGENTS.md: setup command, the review question and the declared limit" $?
! grep -rn '/keel-harness:' "$T" >/dev/null; check "no template contains /keel-harness:" $?
python3 -I -m json.tool "$T/settings.json" >/dev/null; check "settings.json parses" $?
python3 -I -c '
import json, sys
d = json.load(open(sys.argv[1]))["hooks"]
pre = d["PreToolUse"][0]
assert pre["matcher"] == "Write|Edit|MultiEdit|NotebookEdit|Bash", pre["matcher"]
cmd = pre["hooks"][0]
# round 3: the wrapper is found with CLAUDE_PROJECT_DIR (the session cwd can be in another repository); a missing wrapper
# answers ask / systemMessage and exits 0, never 2 (exit 2 blocks every tool call)
loc = "w=\"${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}/.agents/bin/kh\"; if [ -f \"$w\" ]; then exec sh \"$w\" hook "
assert cmd["command"].startswith(loc + "pre-tool-use; fi; printf ") and cmd["timeout"] == 10, cmd["command"]
stop = d["Stop"][0]["hooks"][0]
assert stop["command"].startswith(loc + "stop; fi; printf ") and stop["timeout"] == 120, stop["command"]
for c in (cmd["command"], stop["command"]):
    assert "\n" not in c and "exit 2" not in c
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

# gitignore.txt: the narrow rule for a repository that ignored all of .claude/ (the commented lines, uncommented, versioned paths visible, the rest ignored)
gi="$W/gi"; mkdir -p "$gi"; (cd "$gi" && git init -q .)
grep '^#   ' "$T/gitignore.txt" | sed 's/^#   //' > "$gi/.gitignore"
[ "$(wc -l < "$gi/.gitignore" | tr -d ' ')" -eq 3 ] && grep -qxF '.claude/*' "$gi/.gitignore" && grep -qxF '!.claude/settings.json' "$gi/.gitignore" && grep -qxF '!.claude/agents/' "$gi/.gitignore"; check "gitignore.txt: the commented narrow rule is .claude/*, !.claude/settings.json, !.claude/agents/" $?
(cd "$gi" && ! git check-ignore -q --no-index .claude/settings.json && ! git check-ignore -q --no-index .claude/agents/keel-reviewer.md); check "gitignore.txt narrow rule: settings.json and the reviewer agent are versioned" $?
(cd "$gi" && git check-ignore -q --no-index .claude/skills/x/SKILL.md && git check-ignore -q --no-index .claude/worktrees/w/f && git check-ignore -q --no-index .claude/settings.local.json); check "gitignore.txt narrow rule: skills, worktrees and local settings stay ignored" $?

# gitleaks.toml.tmpl: gitleaks has no option to honour .gitignore, so ignored directories are allow-listed (round 3)
[ -s "$T/gitleaks.toml.tmpl" ]; check "template gitleaks.toml.tmpl exists" $?
python3 -I -c '
import sys, tomllib
d = tomllib.load(open(sys.argv[1], "rb"))
assert d["extend"]["useDefault"] is True, "without useDefault the default rules are lost and nothing is ever found"
al = d["allowlists"]
assert isinstance(al, list) and al and al[0]["paths"], "an [[allowlists]] table with paths"
' "$T/gitleaks.toml.tmpl"; check "gitleaks.toml.tmpl: valid TOML, extends the default rules, [[allowlists]] with paths" $?
for st in typescript python jvm; do
  python3 -I -c '
import sys, re
t = open(sys.argv[1]).read()
m = re.search(r"^  secrets:\n((?:    .*\n)+)", t, re.M)
assert m and "config: [.gitleaks.toml]" in m.group(1), "the secrets script declares config: [.gitleaks.toml]"
' "$T/keel-$st.yml"; check "keel-$st.yml: the secrets script declares config: [.gitleaks.toml]" $?
done
grep -q 'gitleaks.toml' "$T/adr-0001.md"; check "adr-0001.md has a line for the secrets allowlist" $?
GL="$(command -v gitleaks || true)"; [ -z "$GL" ] && [ -x "$HOME/.local/bin/gitleaks" ] && GL="$HOME/.local/bin/gitleaks"
if [ -n "$GL" ]; then
  g="$W/gl"; mkdir -p "$g/build" "$g/.claude/worktrees/w" "$g/src"
  fake='const k = "AKIAIOSFODNN7EXAMPLQ";' # gitleaks:allow (fake key: this test checks that gitleaks finds it)
  printf '%s\n' "$fake" > "$g/build/a.js"; printf '%s\n' "$fake" > "$g/.claude/worktrees/w/b.js"; printf '%s\n' "$fake" > "$g/src/c.js"
  printf 'build/\n.claude/worktrees/\n' > "$g/.gitignore"
  (cd "$g" && git init -q .)
  files() { python3 -I -c 'import json,sys; print(" ".join(sorted({x["File"] for x in json.load(open(sys.argv[1]))})))' "$1"; }
  (cd "$g" && "$GL" detect --no-git --no-banner --redact --report-format json --report-path "$W/gl0.json" >/dev/null 2>&1)
  [ "$(files "$W/gl0.json")" = ".claude/worktrees/w/b.js build/a.js src/c.js" ]; check "gitleaks ($("$GL" version)) without the config reports the secret in ignored directories too (the pitfall)" $?
  # one allowlist entry per ignored directory: the line of the template that holds <ignored-dir> is repeated for each
  DIRS='build|\.claude/worktrees' awk '/<ignored-dir>/ { n = split(ENVIRON["DIRS"], d, "|"); for (i = 1; i <= n; i++) { l = $0; sub(/<ignored-dir>/, d[i], l); print l }; next } { print }' "$T/gitleaks.toml.tmpl" > "$g/.gitleaks.toml"
  (cd "$g" && "$GL" detect --no-git --no-banner --redact --report-format json --report-path "$W/gl1.json" >/dev/null 2>&1)
  [ "$(files "$W/gl1.json")" = "src/c.js" ]; check "gitleaks: with .gitleaks.toml from the template, the secret in ignored directories is not reported and the one in a tracked file is" $?
else
  [ -n "${CI:-}" ] && fail "templates: gitleaks is required in CI" || echo "  skip gitleaks allowlist fixture: gitleaks not installed"
fi

# ------------------------------------------------------------------ the built kh validates and checks each stack
if ! command -v go >/dev/null 2>&1; then
  if [ -n "${CI:-}" ]; then fail "templates: go is required in CI"; finish; fi
  echo "  skip templates: go not installed (kh not built)"; finish
fi
KH="$W/kh"
(cd "$REPO_ROOT/cli/kh" && CGO_ENABLED=0 go build -trimpath -buildvcs=false -o "$KH" .) 2>&1 | cat
[ "${PIPESTATUS[0]}" -eq 0 ]; check "kh builds" $?
[ -x "$KH" ] || finish

# every builtin kh knows is described in references/gates.md with its with: keys (kh schema keel is the source)
GATES_MD="$REPO_ROOT/plugins/keel-harness/skills/harness/references/gates.md"
"$KH" schema keel > "$W/keel.schema.json"
python3 -I - "$W/keel.schema.json" "$GATES_MD" <<'PY'
import json, sys
schema = json.load(open(sys.argv[1]))
text = open(sys.argv[2]).read()
with_ = schema["$defs"]["with"]
assert len(with_) >= 13, sorted(with_)
for name, w in sorted(with_.items()):
    row = next((l for l in text.splitlines() if l.startswith("| `" + name + "` |")), None)
    assert row, "gates.md has no row for builtin " + name
    for key in w["properties"]:
        assert key in row, f"gates.md row of {name} lacks the key {key}"
    assert w["description"] and w["examples"], name
PY
check "kh schema keel describes every builtin's with:, and references/gates.md has a row naming each builtin and its keys" $?

for stack in typescript python jvm; do
  r="$W/$stack"; mkdir -p "$r"; cp -R "$FX/$stack/." "$r/"
  mkdir -p "$r/.agents" "$r/docs" "$r/.claude/agents" "$r/.github/agents"
  cp "$T/keel-$stack.yml" "$r/.agents/keel.yml"
  cp "$T/AGENTS.md.tmpl" "$r/AGENTS.md"; cp "$T/CLAUDE.md.tmpl" "$r/CLAUDE.md"
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
