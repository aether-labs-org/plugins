#!/usr/bin/env bash
# F2c-2: scripts/keel records a proposal, the approval of exactly that proposal and the self-verification
# (spec section 5.1). Every row of the CLI table and every `verify` item, pass and fail.
# shellcheck disable=SC2319  # "check ... $?" after a test is this suite's idiom (see keel_helpers.sh)
set -uo pipefail
. "$(dirname "$0")/keel_helpers.sh"
K="$KEEL/scripts/keel"
W="$(mktemp -d)"; _keel_tmps="$_keel_tmps $W"
nc=0

[ -f "$K" ]; check "scripts/keel exists" $?
[ -x "$K" ]; check "scripts/keel is executable" $?
[ "$(head -1 "$K" 2>/dev/null)" = '#!/usr/bin/env bash' ]; check "scripts/keel starts with the bash shebang" $?
[ ! -e "$KEEL/bin" ]; check "no bin/ directory (D34)" $?
# Without the script nothing below can pass; stop with a clear failure instead of 100 noisy ones.
[ -f "$K" ] || { echo "  (scripts/keel is missing: the remaining assertions are skipped)"; finish; }

# kr REPO ARGS... -> out (stdout and stderr), rc
kr() { out="$(cd "$1" && bash "$K" "${@:2}" 2>&1)"; rc=$?; }
# ko REPO ARGS... -> out (stdout only), err (stderr only), rc
ko() { out="$(cd "$1" && bash "$K" "${@:2}" 2>"$W/err")"; rc=$?; err="$(cat "$W/err")"; }
commit() { (cd "$1" && git add -A && git commit -q -m c); }
nlines() { seq 1 "$1" | sed 's/.*/x/'; }

# ------------------------------------------------------------------ usage and unknown names
r="$(new_repo)"
ko "$r"; [ "$rc" -eq 64 ] && [ -n "$err" ] && [ -z "$out" ]; check "no arguments: usage on stderr, exit 64" $?
ko "$r" bogus; [ "$rc" -eq 64 ] && [ -n "$err" ]; check "unknown command: usage on stderr, exit 64" $?
for c in "check pre" plan approve apply verify; do
  ko "$r" $c nosuch /dev/null; [ "$rc" -eq 64 ] && [ -n "$err" ]; check "$c: a skill other than assess/build/rules exits 64" $?
done
ko "$r" check pre; [ "$rc" -eq 64 ]; check "check pre without a skill exits 64" $?
ko "$r" check nosuch; [ "$rc" -eq 64 ]; check "check <unknown> exits 64" $?
ko "$r" plan build; [ "$rc" -eq 64 ]; check "plan without a file exits 64" $?
ko "$r" approve build; [ "$rc" -eq 64 ]; check "approve without a hash exits 64" $?
ko "$r" verify; [ "$rc" -eq 64 ]; check "verify without a skill exits 64" $?

# ------------------------------------------------------------------ mkbuild: a clean, installed, applied fixture
mkbuild() {
  local r; r="$(new_repo)"
  install_asset "$r" assets/core/harness-check.sh scripts/harness-check.sh
  install_asset "$r" assets/core/gate.sh scripts/gate.sh
  install_asset "$r" assets/core/lib/baseline.sh scripts/lib/baseline.sh
  install_asset "$r" assets/core/lib/envparse.sh scripts/lib/envparse.sh
  install_asset "$r" assets/core/sensors/common/guard.sh scripts/sensors/guard.sh
  install_asset "$r" assets/adapters/claude/claude-stop.sh scripts/hooks/claude-stop.sh
  mkdir -p "$r/.agents/baselines" "$r/.agents/rules" "$r/.claude" "$r/docs/decisions" "$r/scripts/sensors/slow" "$r/src"
  cp "$KEEL/assets/core/gate.env" "$r/.agents/gate.env"
  cp "$KEEL/assets/adapters/claude/settings-stop.json" "$r/.claude/settings.json"
  printf '.agents/run/\n' > "$r/.gitignore"
  cat > "$r/Makefile" <<'MK'
bootstrap:
	npm install

gate-fast:
	@bash scripts/gate.sh fast

gate-slow:
	@bash scripts/gate.sh slow

harness-check:
	@bash scripts/harness-check.sh
MK
  printf '{ "scripts": { "build": "tsc", "test": "vitest run" } }\n' > "$r/package.json"
  cat > "$r/scripts/sensors/lint.sh" <<'S'
#!/usr/bin/env bash
# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.
id=lint
class=heuristic
printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "0 problems"
S
  chmod +x "$r/scripts/sensors/lint.sh"
  printf '# measured_at: 2026-10-20 review_by: 2027-04-20\n' > "$r/.agents/baselines/lint.tsv"
  cat > "$r/AGENTS.md" <<'MD'
# AGENTS.md - demo
Demo repo. Last updated: 2026-10-20.

## Commands
| Purpose | Command | Pass signal |
| --- | --- | --- |
| Install | `make bootstrap` | exit 0 |
| Fast gate | `make gate-fast` | `gate: fast - PASSED` |
| Slow gate | `make gate-slow` | `gate: slow - PASSED` |
| Build | `npm run build` | exit 0 |
| Validate | `make harness-check` | `harness is clean` |

## Before you finish
Run `make gate-fast` and read it.
MD
  printf '@AGENTS.md\n' > "$r/CLAUDE.md"
  cat > "$r/.agents/state.yml" <<'Y'
schema_version: 3
installed_at: 2026-10-20
harness_review_by: 2027-04-20
mode: brownfield
layers: { bootstrap: installed, guides: installed, fast_gate: installed, slow_gate: not_installed, hook: installed, rules: not_installed }
not_installed: {}
Y
  echo 1 > "$r/src/a.ts"
  commit "$r"
  (cd "$r" && bash scripts/gate.sh fast >/dev/null 2>&1)
  printf 'Proposed for this repository: demo\n' > "$W/proposal-build.md"
  (cd "$r" && bash "$K" plan build "$W/proposal-build.md" > "$W/plan.out" 2>&1 \
    && bash "$K" approve build "$(awk '{print $3}' "$W/plan.out")" >/dev/null 2>&1 \
    && bash "$K" apply build >/dev/null 2>&1)
  printf '%s\n' "$r"
}

# ------------------------------------------------------------------ check pre
r="$(new_repo)"
kr "$r" check pre build; [ "$rc" -eq 0 ]; check "check pre build: 0 inside a git work tree" $?
nogit="$(mktemp -d)"; _keel_tmps="$_keel_tmps $nogit"
for s in build assess rules; do
  kr "$nogit" check pre $s; [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q '^missing: '; check "check pre $s: 1 with a 'missing:' line outside a git work tree" $?
done
kr "$r" check pre rules
[ "$rc" -eq 1 ] && [ "$(printf '%s\n' "$out" | grep -c '^missing: ')" -eq 7 ]; check "check pre rules: one missing line per item in an empty repo (7)" $?
for item in scripts/gate.sh scripts/lib/baseline.sh scripts/lib/envparse.sh scripts/sensors/guard.sh .agents/state.yml gate-fast gate-slow; do
  printf '%s\n' "$out" | grep -qF "missing: $item"; check "check pre rules names: $item" $?
done
b="$(mkbuild)"
kr "$b" check pre rules; [ "$rc" -eq 0 ] && [ -z "$out" ]; check "check pre rules: 0 on an installed repository" $?
for item in scripts/gate.sh scripts/lib/baseline.sh scripts/lib/envparse.sh scripts/sensors/guard.sh .agents/state.yml; do
  c="$W/pre$((++nc))"; cp -a "$b" "$c"; rm "$c/$item"
  kr "$c" check pre rules; [ "$rc" -eq 1 ] && [ "$(printf '%s\n' "$out" | grep -c '^missing: ')" -eq 1 ] && printf '%s\n' "$out" | grep -qF "missing: $item"
  check "check pre rules: without $item exactly that line" $?
done
for t in gate-fast gate-slow; do
  c="$W/pre$((++nc))"; cp -a "$b" "$c"; sed "/^$t:/,/^\$/d" "$b/Makefile" > "$c/Makefile"
  kr "$c" check pre rules; [ "$rc" -eq 1 ] && [ "$(printf '%s\n' "$out" | grep -c '^missing: ')" -eq 1 ] && printf '%s\n' "$out" | grep -qF "missing: $t"
  check "check pre rules: Makefile without $t exactly that line" $?
done
c="$W/pre$((++nc))"; cp -a "$b" "$c"; rm "$c/Makefile"
kr "$c" check pre rules; [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -qF 'missing: gate-fast' && printf '%s\n' "$out" | grep -qF 'missing: gate-slow'; check "check pre rules: no Makefile names both targets" $?

# assess snapshot
a="$(new_repo)"; echo dirty > "$a/untracked.txt"
kr "$a" check pre assess; [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -qE '^snapshot [0-9a-f]{40}$'; check "check pre assess: 0 and prints snapshot <token>" $?
[ ! -e "$a/.agents" ]; check "check pre assess writes nothing (no .agents/ appears)" $?
t1="$(printf '%s\n' "$out" | sed -n 's/^snapshot //p')"; echo more > "$a/untracked.txt"; kr "$a" check pre assess
[ "$(printf '%s\n' "$out" | sed -n 's/^snapshot //p')" != "$t1" ]; check "the token changes with the status of the repository" $?

# ------------------------------------------------------------------ plan / approve / apply
r="$(new_repo)"
printf 'proposal one\n' > "$W/p1.md"
H1="$(git hash-object "$W/p1.md")"
ko "$r" plan build "$W/p1.md"
[ "$rc" -eq 0 ] && [ "$out" = "proposal build $H1" ]; check "plan: prints 'proposal build <git hash-object>'" $?
cmp -s "$W/p1.md" "$r/.agents/run/flow/build.proposal"; check "plan: copies the file to .agents/run/flow/build.proposal" $?
ko "$r" plan build "$W/missing.md"; [ "$rc" -eq 1 ] && [ -n "$err" ]; check "plan: 1 when the file is missing" $?
ko "$r" apply build; [ "$rc" -eq 1 ] && printf '%s\n' "$err$out" | grep -qF 'no approval for the current proposal - show it to the user, then run keel approve'; check "apply after plan, before approve: 1 with the approval message" $?
[ ! -e "$r/.agents/run/flow/build.applied" ]; check "apply refused: no .applied marker" $?
ko "$r" approve build "deadbeef"; [ "$rc" -eq 1 ] && [ ! -e "$r/.agents/run/flow/build.approved" ]; check "approve: 1 for a hash that is not the current proposal's" $?
ko "$r" approve rules "$H1"; [ "$rc" -eq 1 ]; check "approve: 1 with no proposal for that skill" $?
ko "$r" approve build "$H1"; [ "$rc" -eq 0 ]; check "approve: 0 for the current proposal's hash" $?
[ "$(cut -f1 "$r/.agents/run/flow/build.approved")" = "$H1" ] && cut -f2 "$r/.agents/run/flow/build.approved" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'; check "approve: build.approved is <hash><TAB><UTC ISO time>" $?
ko "$r" apply build; [ "$rc" -eq 0 ] && [ -s "$r/.agents/run/flow/build.applied" ]; check "apply after approve: 0 and writes build.applied" $?
printf 'proposal two\n' > "$W/p2.md"
H2="$(git hash-object "$W/p2.md")"
ko "$r" plan build "$W/p2.md"; [ "$rc" -eq 0 ] && [ "$out" = "proposal build $H2" ] && [ "$H1" != "$H2" ]; check "plan again: a new hash" $?
[ ! -e "$r/.agents/run/flow/build.approved" ] && [ ! -e "$r/.agents/run/flow/build.applied" ]; check "plan again: deletes .approved and .applied" $?
ko "$r" apply build; [ "$rc" -eq 1 ]; check "apply after the proposal changed (plan again): 1" $?
ko "$r" approve build "$H1"; [ "$rc" -eq 1 ]; check "approve: the old proposal's hash is refused after plan again" $?
ko "$r" approve build "$H2"; ko "$r" apply build; [ "$rc" -eq 0 ]; check "approve + apply the second proposal: 0" $?
printf 'edited behind keel\n' >> "$r/.agents/run/flow/build.proposal"
ko "$r" apply build; [ "$rc" -eq 1 ]; check "apply: 1 when the proposal file was edited after approve" $?
rm -f "$r/.agents/run/flow/build.proposal"
ko "$r" apply build; [ "$rc" -eq 1 ]; check "apply: 1 when the proposal is gone" $?
# approvals are per skill
ko "$r" plan rules "$W/p1.md"; ko "$r" apply rules; [ "$rc" -eq 1 ]; check "an approval for build does not open rules" $?

# ------------------------------------------------------------------ measure / render / check
m="$(new_repo)"; mkdir -p "$m/src"; seq 1 5 > "$m/src/a.txt"; seq 1 9 > "$m/src/b.txt"; commit "$m"
ko "$m" measure file-size src; krc=$rc; kout="$out"
direct="$(cd "$m" && bash "$KEEL/scripts/measure.sh" file-size src 2>/dev/null)"; drc=$?
[ "$krc" -eq "$drc" ] && [ "$kout" = "$direct" ] && [ -n "$kout" ]; check "measure: same output and exit as scripts/measure.sh" $?
ko "$m" measure bogus-subcommand; [ "$rc" -eq 64 ]; check "measure: passes measure.sh's exit 64 through" $?
ko "$m" render; [ "$rc" -eq 64 ]; check "render with no arguments: render.sh's exit 64" $?
ko "$m" render bogus x; [ "$rc" -eq 64 ]; check "render with a bad target: exit 64" $?
mkdir -p "$m/.agents/rules"
cat > "$m/.agents/rules/architecture.env" <<'E'
STYLE=layered
LANG=java
BASE=com.acme
LAYERS='domain|src/main/java/com/acme/domain|com.acme.domain||domainModels'
FORBIDDEN=''
E
ko "$m" render importlinter .agents/rules/architecture.env; krc=$rc; kout="$out"
direct="$(cd "$m" && bash "$KEEL/scripts/render.sh" importlinter .agents/rules/architecture.env 2>/dev/null)"; drc=$?
[ "$krc" -eq "$drc" ] && [ "$kout" = "$direct" ]; check "render: same output and exit as scripts/render.sh" $?

ko "$b" check; krc=$rc; kout="$out"
direct="$(cd "$b" && bash "$KEEL/assets/core/harness-check.sh" 2>/dev/null)"; drc=$?
[ "$krc" -eq "$drc" ] && [ "$kout" = "$direct" ] && [ -n "$kout" ]; check "check (no skill): runs the plugin's harness-check.sh, same output and exit" $?
c="$W/chk$((++nc))"; cp -a "$b" "$c"; echo '| X | `make nosuchtarget` | exit 0 |' >> "$c/AGENTS.md"
ko "$c" check; [ "$rc" -eq 1 ]; check "check (no skill): passes the validator's warning exit (1) through" $?

# ------------------------------------------------------------------ verify build
vb() { kr "$1" verify build; }
vb "$b"
[ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | grep -c '^ok ')" -eq "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" ] && ! printf '%s\n' "$out" | grep -q '^fail '
check "verify build: clean fixture exits 0, every line 'ok <item>'" $?
for it in agents-md state-schema run-ignored gate-ran harness-check baselines portable-scripts guard-installed hook-settings hook-executable hook-json applied; do
  printf '%s\n' "$out" | grep -q "^ok $it"; check "verify build reports item: $it" $?
done

# bcase LABEL ITEM BREAK-CMD (run inside a copy of the clean fixture): exit 1 and a 'fail ITEM:' line
bcase() {
  local c="$W/b$((++nc))"; cp -a "$b" "$c"
  (cd "$c" && eval "$3") >/dev/null 2>&1
  vb "$c"
  [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q "^fail $2: ."
  check "verify build: $1 -> fail $2" $?
}
bcase "AGENTS.md missing" agents-md 'rm AGENTS.md'
bcase "AGENTS.md over 100 lines" agents-md 'seq 1 101 | sed "s/.*/line/" >> AGENTS.md'
bcase "AGENTS.md has an unfilled {{...}}" agents-md 'echo "Run {{install command}}" >> AGENTS.md'
bcase "AGENTS.md has no Last updated line" agents-md 'sed -i.bak "s/Last updated: 2026-10-20/Updated sometime/" AGENTS.md; rm -f AGENTS.md.bak'
bcase "AGENTS.md Last updated is not a date" agents-md 'sed -i.bak "s/Last updated: 2026-10-20/Last updated: yesterday/" AGENTS.md; rm -f AGENTS.md.bak'
bcase "state.yml at schema_version 2" state-schema 'sed -i.bak "s/schema_version: 3/schema_version: 2/" .agents/state.yml; rm -f .agents/state.yml.bak'
bcase "state.yml missing" state-schema 'rm .agents/state.yml'
bcase ".agents/run/ not git-ignored" run-ignored ': > .gitignore'
bcase "no last-run.log" gate-ran 'rm .agents/run/last-run.log'
bcase "last-run.log does not end with a fast verdict" gate-ran 'echo "something else" >> .agents/run/last-run.log'
bcase "validator reports a warning" harness-check 'echo "| X | \`make nosuchtarget\` | exit 0 |" >> AGENTS.md'
bcase "a baseline lacks its measured_at header" baselines 'printf "src/a.ts\t3\n" > .agents/baselines/lint.tsv'
bcase "gate.sh cites \${CLAUDE_" portable-scripts 'echo "echo \${CLAUDE_PLUGIN_ROOT}" >> scripts/gate.sh'
bcase "a lib script calls claude" portable-scripts 'printf "\nclaude -p hello\n" >> scripts/lib/baseline.sh'
bcase "a sensor calls claude after a pipe" portable-scripts 'printf "\necho x | claude -p hello\n" >> scripts/sensors/lint.sh'
bcase "scripts/sensors/guard.sh missing" guard-installed 'rm scripts/sensors/guard.sh'
bcase "scripts/lib/envparse.sh missing" guard-installed 'rm scripts/lib/envparse.sh'
bcase "settings.json has no Stop entry" hook-settings 'printf "{ \"hooks\": {} }\n" > .claude/settings.json'
bcase "settings.json missing" hook-settings 'rm .claude/settings.json'
bcase "hook command has an absolute path, not \${CLAUDE_PROJECT_DIR}" hook-settings 'sed -i.bak "s#\${CLAUDE_PROJECT_DIR}#/abs/path#" .claude/settings.json; rm -f .claude/settings.json.bak'
bcase "a PostToolUse entry runs the gate" hook-settings 'printf "{ \"hooks\": { \"Stop\": [ { \"hooks\": [ { \"type\": \"command\", \"command\": \"\\\\\"\${CLAUDE_PROJECT_DIR}\\\\\"/scripts/hooks/claude-stop.sh\" } ] } ], \"PostToolUse\": [ { \"hooks\": [ { \"type\": \"command\", \"command\": \"make gate-fast\" } ] } ] } }\n" > .claude/settings.json'
bcase "hook script not executable" hook-executable 'chmod -x scripts/hooks/claude-stop.sh'
bcase "hook script missing" hook-executable 'rm scripts/hooks/claude-stop.sh'
bcase "settings.json is not valid JSON" hook-json 'printf "{ \"hooks\": { \"Stop\": [ scripts/hooks/claude-stop.sh \${CLAUDE_PROJECT_DIR}\n" > .claude/settings.json'
bcase "install did not go through keel apply" applied 'rm .agents/run/flow/build.applied'

# hook not installed: the hook items do not apply
c="$W/b$((++nc))"; cp -a "$b" "$c"
(cd "$c" && sed -i.bak 's/hook: installed/hook: not_installed/' .agents/state.yml && rm -f .agents/state.yml.bak .claude/settings.json scripts/hooks/claude-stop.sh)
vb "$c"; [ "$rc" -eq 0 ] && ! printf '%s\n' "$out" | grep -q '^fail '; check "verify build: hook not_installed -> no hook item can fail" $?

# F3c-1: the authority layer (consequence map, protect hook, its settings entry)
for it in authority-map authority-settings authority-executable; do
  printf '%s\n' "$out" | grep -q "^ok $it skip (authority is not installed)"; check "verify build: authority not installed -> $it is a skip" $?
done
a="$W/authority"; cp -a "$b" "$a"
(cd "$a" && sed -i.bak 's/rules: not_installed }/rules: not_installed, authority: installed }/' .agents/state.yml && rm -f .agents/state.yml.bak
  mkdir -p scripts/hooks && cp "$KEEL/assets/adapters/claude/claude-protect.sh" scripts/hooks/ && chmod +x scripts/hooks/claude-protect.sh
  cp "$KEEL/assets/core/consequence.yml" .agents/consequence.yml
  cat > .claude/settings.json <<'JSON'
{
  "hooks": {
    "Stop": [ { "hooks": [ { "type": "command", "command": "\"${CLAUDE_PROJECT_DIR}\"/scripts/hooks/claude-stop.sh", "timeout": 120 } ] } ],
    "PreToolUse": [ { "matcher": "Write|Edit|NotebookEdit", "hooks": [ { "type": "command", "command": "\"${CLAUDE_PROJECT_DIR}\"/scripts/hooks/claude-protect.sh", "timeout": 10 } ] } ]
  },
  "permissions": { "deny": [ "Read(**/.env)", "Edit(**/.env)" ] }
}
JSON
)
vb "$a"
[ "$rc" -eq 0 ] && ! printf '%s\n' "$out" | grep -q '^fail ' && ! printf '%s\n' "$out" | grep -q 'skip (authority'; check "verify build: a clean authority layer exits 0 and no authority item is skipped" $?
for it in authority-map authority-settings authority-executable; do
  printf '%s\n' "$out" | grep -qx "ok $it"; check "verify build reports item: $it" $?
done
acase() { # acase LABEL ITEM BREAK-CMD (run inside a copy of the clean authority fixture)
  local c="$W/a$((++nc))"; cp -a "$a" "$c"
  (cd "$c" && eval "$3") >/dev/null 2>&1
  vb "$c"
  [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q "^fail $2: ."
  check "verify build (authority): $1 -> fail $2" $?
}
acase "the consequence map is missing" authority-map 'rm .agents/consequence.yml'
acase "the map declares no harness path" authority-map 'grep -v "^harness:" .agents/consequence.yml > .agents/c.tmp && mv .agents/c.tmp .agents/consequence.yml'
acase "the map has a line that is neither a comment, a !glob nor category: glob" authority-map 'echo "this is not a map line" >> .agents/consequence.yml'
acase "settings.json has no PreToolUse entry" authority-settings 'sed -i.bak "/PreToolUse/d" .claude/settings.json; rm -f .claude/settings.json.bak'
acase "the PreToolUse command has an absolute path, not \${CLAUDE_PROJECT_DIR}" authority-settings 'sed -i.bak "/claude-protect/s#\${CLAUDE_PROJECT_DIR}#/abs/path#" .claude/settings.json; rm -f .claude/settings.json.bak'
acase "the PreToolUse matcher lost NotebookEdit" authority-settings 'sed -i.bak "s#Write|Edit|NotebookEdit#Write|Edit#" .claude/settings.json; rm -f .claude/settings.json.bak'
acase "settings.json is missing" authority-settings 'rm .claude/settings.json'
if command -v python3 >/dev/null 2>&1; then
  acase "settings.json is not valid JSON" authority-settings 'echo "{ \"hooks\": scripts/hooks/claude-protect.sh PreToolUse \${CLAUDE_PROJECT_DIR} Write|Edit|NotebookEdit" > .claude/settings.json'
fi
acase "the protect hook is not executable" authority-executable 'chmod -x scripts/hooks/claude-protect.sh'
acase "the protect hook is missing" authority-executable 'rm scripts/hooks/claude-protect.sh'

# no python3 on PATH: the JSON item is a skip that counts as ok
nopy="$W/nopybin"; mkdir -p "$nopy"
for t in bash git grep sed awk head tail wc cat date mkdir cp rm mktemp tr cut sort dirname basename ls env chmod find cmp expr uname seq mv printf test tee xargs stat readlink; do
  p="$(command -v "$t" 2>/dev/null)" && [ -x "$p" ] && ln -sf "$p" "$nopy/$t"
done
out="$(cd "$b" && PATH="$nopy" "$nopy/bash" "$K" verify build 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q '^ok hook-json.*skip (no python3)'; check "verify build: no python3 -> hook-json says 'skip (no python3)' and counts as ok" $?

# ------------------------------------------------------------------ verify rules
mkrules() {
  local r; r="$(mkbuild)"
  mkdir -p "$r/docs"
  printf '# Conventions\n\n<a id="file-size"></a>\n## File size\n\nKeep files at or under 300 lines.\n' > "$r/docs/conventions.md"
  cat > "$r/.agents/rules/file-size.env" <<'E'
# Managed by keel-harness - see .agents/README.md
RULE_ID=file-size
KIND=metric
ORIGIN=proposed
APPROVED_AT=2026-10-20
ENFORCEMENT=inferential
DOC=docs/conventions.md#file-size
LIMIT=300
E
  commit "$r"
  (cd "$r" && bash scripts/gate.sh fast >/dev/null 2>&1)
  printf 'rules proposal\n' > "$W/proposal-rules.md"
  (cd "$r" && bash "$K" plan rules "$W/proposal-rules.md" > "$W/plan.out" 2>&1 \
    && bash "$K" approve rules "$(awk '{print $3}' "$W/plan.out")" >/dev/null 2>&1 \
    && bash "$K" apply rules >/dev/null 2>&1)
  printf '%s\n' "$r"
}
rb="$(mkrules)"
kr "$rb" verify rules
[ "$rc" -eq 0 ] && ! printf '%s\n' "$out" | grep -q '^fail ' && [ "$(printf '%s\n' "$out" | grep -c '^ok ')" -ge 5 ]; check "verify rules: clean fixture exits 0, only 'ok' lines" $?
for it in harness-check gate-passed rule-env rule-doc applied; do
  printf '%s\n' "$out" | grep -q "^ok $it"; check "verify rules reports item: $it" $?
done
rcase() {
  local c="$W/r$((++nc))"; cp -a "$rb" "$c"
  (cd "$c" && eval "$3") >/dev/null 2>&1
  kr "$c" verify rules
  [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q "^fail $2: ."
  check "verify rules: $1 -> fail $2" $?
}
rcase "validator reports a warning" harness-check 'echo "| X | \`make nosuchtarget\` | exit 0 |" >> AGENTS.md'
rcase "last-run.log says FAILED" gate-passed 'echo "gate: fast - FAILED | ceiling 30s" >> .agents/run/last-run.log'
rcase "no last-run.log" gate-passed 'rm .agents/run/last-run.log'
rcase "an env file has a line that is not KEY=value" rule-env 'echo "not a valid line" >> .agents/rules/file-size.env'
rcase "an env file has a value with a command substitution" rule-env 'echo "LIMIT=\$(id)" >> .agents/rules/file-size.env'
rcase "an env file lacks RULE_ID" rule-env 'sed -i.bak "/^RULE_ID=/d" .agents/rules/file-size.env; rm -f .agents/rules/file-size.env.bak'
rcase "an env file lacks KIND" rule-env 'sed -i.bak "/^KIND=/d" .agents/rules/file-size.env; rm -f .agents/rules/file-size.env.bak'
rcase "an env file lacks ORIGIN" rule-env 'sed -i.bak "/^ORIGIN=/d" .agents/rules/file-size.env; rm -f .agents/rules/file-size.env.bak'
rcase "an env file lacks DOC" rule-env 'sed -i.bak "/^DOC=/d" .agents/rules/file-size.env; rm -f .agents/rules/file-size.env.bak'
rcase "DOC anchor is not in the file" rule-doc 'sed -i.bak "s/id=\"file-size\"/id=\"other\"/" docs/conventions.md; rm -f docs/conventions.md.bak'
rcase "DOC file is missing" rule-doc 'rm docs/conventions.md'
rcase "DOC has no #anchor" rule-doc 'sed -i.bak "s/^DOC=.*/DOC=docs\/conventions.md/" .agents/rules/file-size.env; rm -f .agents/rules/file-size.env.bak'
rcase "the install did not go through keel apply" applied 'rm .agents/run/flow/rules.applied'
c="$W/r$((++nc))"; cp -a "$rb" "$c"; (cd "$c" && rm .agents/rules/file-size.env docs/conventions.md)
kr "$c" verify rules; [ "$rc" -eq 0 ]; check "verify rules: no env files at all is not a failure" $?

# ------------------------------------------------------------------ verify assess
a="$(new_repo)"; echo base > "$a/tracked.txt"; commit "$a"
kr "$a" verify assess; [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -qF 'pass the token'; check "verify assess: without a token fails and asks for it" $?
kr "$a" check pre assess; tok="$(printf '%s\n' "$out" | sed -n 's/^snapshot //p')"
kr "$a" verify assess "$tok"; [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q '^ok '; check "verify assess: untouched repository exits 0" $?
[ ! -e "$a/.agents" ]; check "check pre and verify assess wrote nothing" $?
mkdir -p "$a/.agents/run"; echo noise > "$a/.agents/run/noise.log"
kr "$a" verify assess "$tok"; [ "$rc" -eq 0 ]; check "verify assess: changes under .agents/run/ are ignored" $?
echo "changed" >> "$a/tracked.txt"
kr "$a" verify assess "$tok"; [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q '^fail '; check "verify assess: a modified tracked file fails" $?
git -C "$a" checkout -q -- tracked.txt
echo new > "$a/new.txt"
kr "$a" verify assess "$tok"; [ "$rc" -eq 1 ]; check "verify assess: a new untracked file fails" $?
rm "$a/new.txt"
kr "$a" verify assess "$tok"; [ "$rc" -eq 0 ]; check "verify assess: back to the snapshot exits 0" $?
d="$(new_repo)"; echo pre-existing > "$d/wip.txt"
kr "$d" check pre assess; tokd="$(printf '%s\n' "$out" | sed -n 's/^snapshot //p')"; kr "$d" verify assess "$tokd"; [ "$rc" -eq 0 ]; check "verify assess: work in progress that predates the snapshot is not a failure" $?
echo more >> "$d/wip.txt"; echo more > "$d/wip2.txt"
kr "$d" verify assess "$tokd"; [ "$rc" -eq 1 ]; check "verify assess: a new file next to pre-existing work in progress fails" $?
rm "$d/wip2.txt"; kr "$d" verify assess "$tokd"; [ "$rc" -eq 1 ]; check "verify assess: a second edit to a file that was already modified fails" $?

# ------------------------------------------------------------------ H1: no stray temp files, no write outside the repository
r="$(new_repo)"
before="$(find "$r" -path "$r/.git" -prune -o -type f -print | wc -l | tr -d ' ')"
kr "$r" plan build "$W/p1.md"; H="$(awk '{print $3}' <<EOF
$out
EOF
)"
kr "$r" approve build "$H"; kr "$r" apply build
leftover="$(find "$r" -path "$r/.git" -prune -o -type f -print | grep -v '/\.agents/run/flow/' | wc -l | tr -d ' ')"
[ "$leftover" -eq "$((before))" ]; check "plan/approve/apply write only under .agents/run/flow/" $?

# ------------------------------------------------------------------ the skills call keel with commands that exist, for their own skill
for s in assess build rules; do
  calls="$(grep -ohE 'scripts/keel (check pre|plan|approve|apply|verify) [a-z]+' "$KEEL/skills/$s/SKILL.md")"
  [ -n "$calls" ]; check "$s/SKILL.md calls scripts/keel" $?
  bad="$(printf '%s\n' "$calls" | grep -vE "^scripts/keel (check pre|plan|approve|apply|verify) $s\$" | grep -c .)"
  [ "$bad" -eq 0 ]; check "$s/SKILL.md names only its own skill in every scripts/keel call" $?
done
grep -q 'scripts/keel' "$KEEL/skills/build/SKILL.md" && ! grep -q 'keel verify build' "$KEEL/skills/rules/SKILL.md"; check "build and rules do not call each other's verify" $?

# ------------------------------------------------------------------ the README explains the enforcement
grep -q "^## How the flow is enforced" "$KEEL/README.md" && grep -q "scripts/keel" "$KEEL/README.md"; check "README has a How the flow is enforced section naming scripts/keel" $?
grep -q "agent itself runs .keel approve." "$KEEL/README.md"; check "README states the limit: the agent runs keel approve" $?

# ------------------------------------------------------------------ contracts/flow.md documents what the script does
F="$KEEL/contracts/flow.md"
for s in 'keel check pre <skill>' 'keel plan <skill> <file>' 'keel approve <skill> <hash>' 'keel apply <skill>' 'keel verify <skill>' \
         'keel measure' 'keel render' '.agents/run/flow/' '<skill>.approved' '<skill>.proposal' 'snapshot <token>' \
         'No write before `keel apply <skill>` exits 0' 'Done means `keel verify <skill>` exits 0' 'Known limit' \
         'runs `keel approve`' 'PreToolUse' '## Traceability'; do
  grep -qF -- "$s" "$F"; check "contracts/flow.md contains: $s" $?
done
for it in agents-md state-schema run-ignored gate-ran harness-check baselines portable-scripts guard-installed hook-settings hook-executable hook-json applied \
          authority-map authority-settings authority-executable \
          gate-passed rule-env rule-doc status; do
  grep -qF "\`$it\`" "$F"; check "contracts/flow.md names the verify item: $it" $?
done
finish
