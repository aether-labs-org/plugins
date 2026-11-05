#!/usr/bin/env bash
# keel-harness v0.5 plugin: the wrapper and lock it carries, the skill structure, the references.
# shellcheck disable=SC2319  # "check ... $?" after a test is this suite's idiom (see keel_helpers.sh)
set -uo pipefail
. "$(dirname "$0")/keel_helpers.sh"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
P="$REPO_ROOT/plugins/keel-harness"

# ------------------------------------------------------------------ the plugin carries the wrapper and the lock (B1)
cmp -s "$REPO_ROOT/cli/kh/wrapper/kh" "$P/kh/bin/kh"; check "plugin: kh/bin/kh is byte-identical to cli/kh/wrapper/kh" $?
[ -x "$P/kh/bin/kh" ]; check "plugin: kh/bin/kh is executable" $?
LOCK="$P/kh/keel.lock"
[ -f "$LOCK" ]; check "plugin: kh/keel.lock exists" $?
grep -qE '^version=[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$' "$LOCK"; check "plugin: keel.lock has a version= line (x.y.z or x.y.z-rc.N)" $?
[ "$(grep -cE '^(linux|darwin)-(amd64|arm64)=[0-9a-f]{64}$' "$LOCK")" -eq 4 ]; check "plugin: keel.lock has the four platform hashes of 64 hex" $?
[ "$(grep -cvE '^(#.*|version=.*|(linux|darwin)-(amd64|arm64)=[0-9a-f]{64})$' "$LOCK")" -eq 0 ]; check "plugin: keel.lock has no other lines" $?
dev="$(sed -n 's/^VERSION ?= //p' "$REPO_ROOT/cli/kh/Makefile" | head -1)"
want="${dev%-dev}"
locked="$(sed -n 's/^version=//p' "$LOCK")"
case "$locked" in "$want" | "$want"-rc.*) ok=0 ;; *) ok=1 ;; esac
[ "$ok" -eq 0 ]; check "plugin: the lock version ($locked) is cli/kh's $want or one of its release candidates" $?

# ------------------------------------------------------------------ the references (B5)
REF="$P/skills/harness/references"
for f in rubric discovery rounds gates protection memory git review agents verify; do
  [ -s "$REF/$f.md" ]; check "references/$f.md exists" $?
done
# every relative Markdown link in the references resolves
bad="$(python3 -I - "$REF" <<'PY'
import os, re, sys
ref = sys.argv[1]
for name in sorted(os.listdir(ref)):
    if not name.endswith(".md"):
        continue
    text = open(os.path.join(ref, name)).read()
    for m in re.finditer(r"\]\(([^)\s]+)\)", text):
        t = m.group(1)
        if "://" in t or t.startswith(("#", "mailto:")):
            continue
        path = os.path.normpath(os.path.join(ref, t.split("#")[0]))
        if not os.path.exists(path):
            print(f"{name}: {t}")
PY
)"
[ -z "$bad" ]; check "references: every relative link resolves" $?
[ -z "$bad" ] || printf '%s\n' "$bad"
hits="$(grep -nE 'scripts/keel|contracts/|assets/|state\.yml|\.env\b|render\.sh|/keel-harness:|CODEOWNERS|mandatory' "$REF"/*.md || true)"
[ -z "$hits" ]; check "references mention none of: scripts/keel, contracts/, assets/, state.yml, .env, render.sh, /keel-harness:, CODEOWNERS, mandatory" $?
[ -z "$hits" ] || printf '%s\n' "$hits" | head
over=""
for f in "$REF"/*.md; do [ "$(wc -l < "$f" | tr -d ' ')" -le 300 ] || over="$over $(basename "$f")"; done
[ -z "$over" ]; check "every reference is at most 300 lines${over:+ (over:$over)}" $?

# ------------------------------------------------------------------ SKILL.md (B6)
SK="$P/skills/harness/SKILL.md"
[ -s "$SK" ]; check "SKILL.md exists" $?
[ "$(wc -l < "$SK" | tr -d ' ')" -le 200 ]; check "SKILL.md is at most 200 lines" $?
[ "$(head -1 "$SK")" = "---" ]; check "SKILL.md starts with frontmatter" $?
fm="$(awk 'NR == 1 { next } /^---$/ { exit } { print }' "$SK")"
printf '%s\n' "$fm" | grep -qx 'name: harness'; check "frontmatter: name: harness" $?
printf '%s\n' "$fm" | grep -q '^description: .\{40,\}'; check "frontmatter: description present" $?
printf '%s\n' "$fm" | grep -qF "command: 'sh \"\${CLAUDE_PLUGIN_ROOT}/kh/bin/kh\" hook pre-tool-use --setup'"; check "frontmatter: the setup-session hook command" $?
printf '%s\n' "$fm" | grep -qF 'matcher: "Write|Edit|MultiEdit|NotebookEdit|Bash"' && printf '%s\n' "$fm" | grep -q 'timeout: 10$'; check "frontmatter: hook matcher and timeout 10" $?
if python3 -I -c 'import yaml' 2>/dev/null; then
  printf '%s\n' "$fm" | python3 -I -c '
import sys, yaml
d = yaml.safe_load(sys.stdin)
h = d["hooks"]["PreToolUse"][0]
assert d["name"] == "harness" and h["matcher"] == "Write|Edit|MultiEdit|NotebookEdit|Bash"
assert h["hooks"][0]["command"] == "sh \"${CLAUDE_PLUGIN_ROOT}/kh/bin/kh\" hook pre-tool-use --setup" and h["hooks"][0]["timeout"] == 10 and h["hooks"][0]["type"] == "command"
'
  check "frontmatter parses as YAML and carries the hook" $?
else
  echo "  skip frontmatter YAML parse: PyYAML not installed (text checks above ran)"
fi
miss=""
for f in "$REF"/*.md; do grep -qF "(references/$(basename "$f"))" "$SK" || miss="$miss $(basename "$f")"; done
[ -z "$miss" ]; check "every file in references/ is linked directly from SKILL.md${miss:+ (missing:$miss)}" $?
# every template is referenced by rounds.md or SKILL.md (architecture templates by tool prefix and style)
TPL="$P/skills/harness/templates"
miss=""
for f in $(cd "$TPL" && find . -type f -not -path './architecture/*' | sed 's|^\./||'); do
  grep -qF "$f" "$REF/rounds.md" "$SK" || miss="$miss $f"
done
for tool in dependency-cruiser import-linter archunit; do
  grep -qF "$tool-<style>" "$REF/rounds.md" || miss="$miss $tool-<style>"
done
for st in hexagonal layered clean modular; do grep -qF "$st" "$REF/rounds.md" || miss="$miss $st"; done
n_arch="$(find "$TPL/architecture" -type f | wc -l | tr -d ' ')"
[ "$n_arch" -eq 12 ] || miss="$miss architecture-count-$n_arch"
[ -z "$miss" ]; check "every template is referenced by rounds.md or SKILL.md${miss:+ (missing:$miss)}" $?
first_kh="$(grep -n 'kh/bin/kh" version' "$SK" | head -1 | cut -d: -f1)"; first_disc="$(grep -n 'discover.sh' "$SK" | head -1 | cut -d: -f1)"
{ [ -n "$first_kh" ] && [ -n "$first_disc" ] && [ "$first_kh" -lt "$first_disc" ]; }; check "SKILL.md: the first action is the plugin's kh version (before discover.sh)" $?
grep -qi 'until .kh. is cached' "$SK" && grep -q 'asks the human to confirm every' "$SK"; check "SKILL.md says why: until kh is cached the setup hook asks for every call" $?
grep -q '/keel-harness:harness' "$SK"; check "SKILL.md names its own invocation" $?
if command -v claude >/dev/null 2>&1; then
  claude plugin validate "$P" --strict >/dev/null 2>&1; check "claude plugin validate ./plugins/keel-harness --strict passes" $?
else
  echo "  skip claude plugin validate: claude not installed"
fi

# ------------------------------------------------------------------ the v0.3 plugin is gone, the README states the limits (B7)
cd "$REPO_ROOT" || exit 1
refs="$(git grep -nE --untracked 'assets/core|scripts/keel|contracts/|render\.sh|state\.yml|skills/(assess|build|rules)' -- . ':!docs/specs/*keel*' ':!docs/plans/*keel*' ':!tests/keel_skill_test.sh' 2>/dev/null || true)"
[ -z "$refs" ]; check "no file outside the old keel docs references a removed path (assets/core, scripts/keel, contracts/, render.sh, state.yml, skills/assess|build|rules)" $?
[ -z "$refs" ] || printf '%s\n' "$refs" | head -20
for gone in assets contracts evals scripts skills/assess skills/build skills/rules; do
  [ ! -e "$P/$gone" ]; check "plugin: $gone is removed" $?
done
README="$P/README.md"
[ "$(wc -l < "$README" | tr -d ' ')" -le 150 ]; check "plugin README is at most 150 lines" $?
grep -qi 'friction' "$README" && grep -qi 'not a security boundary' "$README"; check "README declares: protection is friction, not a security boundary" $?
grep -qi 'not measured' "$README" && grep -qi 'effect' "$README"; check "README declares: the effect on agent success was not measured" $?
grep -qi 'copilot' "$README" && grep -qi 'devin' "$README" && grep -qi 'assum' "$README"; check "README declares: the Copilot and Devin cross-reads are assumed" $?
! grep -q '/keel-harness:' "$README" || grep -q 'harness' "$README"; check "README names the skill" $?
[ "$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$P/.claude-plugin/plugin.json")" = "$(sed -n 's/^version=//p' "$P/kh/keel.lock")" ]; check "plugin.json version equals the lock version (aligned, spec V26)" $?

# ------------------------------------------------------------------ the consolidated spec replaces the old keel docs (C1)
SPEC="$REPO_ROOT/docs/specs/2026-11-04-keel-harness-v0.5-design.md"
[ -s "$SPEC" ]; check "docs/specs/2026-11-04-keel-harness-v0.5-design.md exists" $?
for old in 2026-09-19-keel-harness-design 2026-10-20-keel-harness-v0.2-design 2026-10-23-keel-harness-v0.3-design 2026-10-24-keel-cli-design 2026-11-03-keel-cli-v0.4-design; do
  [ ! -e "$REPO_ROOT/docs/specs/$old.md" ]; check "docs/specs/$old.md is removed" $?
done
[ "$(ls "$REPO_ROOT"/docs/plans | grep -c keel)" -eq 0 ]; check "docs/plans/*keel* are removed" $?
dead="$(git grep -nE --untracked '2026-09-19-keel-harness-design|2026-10-20-keel-harness-v0\.2-design|2026-10-23-keel-harness-v0\.3-design|2026-10-24-keel-cli-design|2026-11-03-keel-cli-v0\.4-design|docs/plans/[^ )`]*keel' -- . ':!docs/specs/2026-11-04-keel-harness-v0.5-design.md' ':!tests/keel_skill_test.sh' 2>/dev/null || true)"
[ -z "$dead" ]; check "no file links to a deleted keel doc" $?
[ -z "$dead" ] || printf '%s\n' "$dead" | head -10
for ev in keel-v0.3-e1 keel-v0.3-e2 keel-v0.3-f0; do [ ! -e "$REPO_ROOT/docs/evals/$ev" ]; check "docs/evals/$ev (v0.3 eval results of the removed skills) is removed" $?; done
sed -n 4p "$SPEC" | grep -q '^\*\*Status:\*\* approved by the owner on 2026-11-04'; check "spec header: approved by the owner on 2026-11-04" $?
grep -qF 'tracked or untracked, not ignored, match' "$SPEC"; check "spec: --all passes every tracked or untracked, not ignored, match" $?
grep -qF 'secrets: { run: "gitleaks detect --no-banner --report-format sarif --report-path {report}",' "$SPEC"; check "spec section 6: the secrets run: is quoted (valid YAML)" $?
grep -qF '  merge-check: { builtin: merge-check }' "$SPEC"; check "spec section 6: merge-check is declared" $?
if python3 -I -c 'import yaml' 2>/dev/null; then
  python3 -I - "$SPEC" <<'PY'
import re, sys, yaml
t = open(sys.argv[1]).read()
m = re.search(r"```yaml\n(version: 1\n.*?)```", t, re.S)
d = yaml.safe_load(m.group(1))
assert "merge-check" in d["scripts"] and d["scripts"]["secrets"]["run"].endswith("{report}")
PY
  check "spec section 6 example parses as YAML" $?
else
  echo "  skip spec YAML parse: PyYAML not installed"
fi
ls "$REPO_ROOT"/docs/specs | grep -E 'second-brain|solutions' >/dev/null; check "the docs of the other plugins are untouched (second-brain specs still there)" $?

finish
