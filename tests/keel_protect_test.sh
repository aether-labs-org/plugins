#!/usr/bin/env bash
# F3c-1: claude-protect.sh (the Claude Code PreToolUse hook for Write, Edit and NotebookEdit) denies edits to
# harness files outside an approved build/rules flow, asks about the other consequential paths and says
# nothing about everything else. The consequence map it reads is contracts/consequence.md.
# shellcheck disable=SC2319  # "check ... $?" after a test is this suite's idiom (see keel_helpers.sh)
set -uo pipefail
. "$(dirname "$0")/keel_helpers.sh"
HOOK_SRC="$KEEL/assets/adapters/claude/claude-protect.sh"
MAP_SRC="$KEEL/assets/core/consequence.yml"
W="$(mktemp -d)"; _keel_tmps="$_keel_tmps $W"

[ -f "$HOOK_SRC" ]; check "claude-protect.sh exists" $?
[ -f "$MAP_SRC" ]; check "assets/core/consequence.yml (the default map) exists" $?
[ -f "$HOOK_SRC" ] || { echo "  (claude-protect.sh is missing: the remaining assertions are skipped)"; finish; }
[ "$(head -n 1 "$HOOK_SRC")" = '#!/usr/bin/env bash' ]; check "claude-protect.sh starts with the bash shebang" $?
sed -n 2p "$HOOK_SRC" | grep -q '^# Managed by keel-harness'; check "claude-protect.sh carries the managed-by header" $?
# shellcheck disable=SC1090
. "$HOOK_SRC" 2>/dev/null

# --- json_string: the value of the first string-valued key, however the JSON is spaced or escaped
[ "$(json_string file_path '{"tool_input":{"file_path":"/a/b.ts"}}')" = '/a/b.ts' ]; check "json_string: compact" $?
[ "$(json_string file_path '{"tool_input": { "file_path"  :   "/a/b.ts" , "content": "x"}}')" = '/a/b.ts' ]; check "json_string: spaces around the colon" $?
[ "$(json_string file_path "$(printf '{\n  "tool_input": {\n    "file_path":\n      "/a/b.ts",\n    "content": "x"\n  }\n}\n')")" = '/a/b.ts' ]; check "json_string: pretty-printed over several lines" $?
[ "$(json_string file_path '{"file_path":"/a/b\"c.ts"}')" = '/a/b"c.ts' ]; check "json_string: an escaped quote in the value" $?
[ "$(json_string file_path '{"file_path":"/a/b\\c.ts"}')" = '/a/b\c.ts' ]; check "json_string: an escaped backslash in the value" $?
[ "$(json_string file_path '{"file_path":"\/a\/b.ts"}')" = '/a/b.ts' ]; check "json_string: escaped slashes" $?
[ "$(json_string file_path '{"file_path":"/a/\u002eagents/x"}')" = '/a/.agents/x' ]; check "json_string: an ASCII \\u escape is decoded" $?
[ "$(json_string file_path '{"tool_input":{"content":"say \"file_path\": \"/etc/x\" here","file_path":"/real.ts"}}')" = '/real.ts' ]; check "json_string: a key quoted inside another string is not the key" $?
[ -z "$(json_string file_path '{"file_path":null}')" ] && [ -z "$(json_string file_path '{"other":"x"}')" ] && [ -z "$(json_string file_path 'not json')" ]; check "json_string: no string value -> empty" $?

# --- norm_path and glob_match
[ "$(norm_path /r/src/../.agents//x/./y)" = '/r/.agents/x/y' ]; check "norm_path: collapses ., .. and //" $?
[ "$(norm_path /../../x)" = '/x' ]; check "norm_path: .. at the root stays at the root" $?
gm() { glob_match "$1" "$2"; }
gm '.agents/**' '.agents/baselines/x.tsv'; check "glob: dir/** covers everything under the directory" $?
! gm '.agents/**' '.agentsx/y'; check "glob: dir/** does not cover a sibling with the same prefix" $?
gm '**/auth/**' 'src/auth/x.ts' && gm '**/auth/**' 'auth/x.ts' && gm '**/auth/**' 'a/b/auth/c/d.ts'; check "glob: **/dir/** matches at any depth, root included" $?
! gm '**/auth/**' 'src/authz/x.ts'; check "glob: **/auth/** does not match authz" $?
gm 'scripts/*.sh' 'scripts/gate.sh'; check "glob: * matches inside a segment" $?
! gm 'scripts/*.sh' 'scripts/lib/x.sh'; check "glob: * does not cross a slash" $?
gm '**/*.pem' 'a/b/k.pem' && gm '**/*.pem' 'k.pem'; check "glob: **/*.pem matches with and without a directory" $?
gm 'openapi*.y*ml' 'openapi.yaml' && gm 'openapi*.y*ml' 'openapi-v2.yml'; check "glob: several * in one segment" $?
! gm 'openapi*.y*ml' 'api/openapi.yaml'; check "glob: a pattern without a slash is anchored at the repository root" $?
gm 'a.b' 'a.b' && ! gm 'a.b' 'axb'; check "glob: a dot is a literal dot" $?
gm 'f(1)+[x]' 'f(1)+[x]'; check "glob: regex characters are literals" $?
gm 'x?z' 'xyz' && ! gm 'x?z' 'x/z'; check "glob: ? is one character that is not a slash" $?

# --- the hook as a process
mkrepo() {
  local r; r="$(new_repo)"
  install_asset "$r" assets/adapters/claude/claude-protect.sh scripts/hooks/claude-protect.sh
  mkdir -p "$r/.agents" "$r/src/auth" "$r/.agents/baselines"
  cp "$MAP_SRC" "$r/.agents/consequence.yml"
  printf 'auth: **/auth/**\ndata: **/migrations/**\ninfra: terraform/**\npublic-contract: openapi*.y*ml\n' >> "$r/.agents/consequence.yml"
  printf '%s\n' "$r"
}
# fx TOOL FIELD PATH [EXTRA] -> a PreToolUse payload
fx() {
  printf '{"session_id":"s1","transcript_path":"/t","cwd":"/work","permission_mode":"default","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"%s":"%s"%s},"tool_use_id":"toolu_1"}' "$1" "$2" "$3" "${4:-}"
}
EDIT_X=',"old_string":"a","new_string":"b","replace_all":false'
WRITE_X=',"content":"hello"'
# hook REPO STDIN [ENV...] -> out (stdout), err (stderr), rc; runs from the repository root
hook() {
  local r="$1" in="$2"; shift 2
  out="$(cd "$r" && printf '%s' "$in" | env -u CLAUDE_PROJECT_DIR "$@" bash scripts/hooks/claude-protect.sh 2>"$W/err")"; rc=$?
  err="$(cat "$W/err")"
}
decision() { printf '%s' "$out" | sed -n 's/.*"permissionDecision":"\([a-z]*\)".*/\1/p'; }
reason() { printf '%s' "$out" | sed -n 's/.*"permissionDecisionReason":"\(.*\)"}}$/\1/p'; }
silent() { [ "$rc" -eq 0 ] && [ -z "$out" ] && [ -z "$err" ]; }
# approve REPO SKILL: what keel plan, approve and apply leave behind
approve() {
  local d="$1/.agents/run/flow"
  mkdir -p "$d"
  printf 'proposal text\n' > "$d/$2.proposal"
  printf '%s\t%s\n' "$(git hash-object "$d/$2.proposal")" "2026-10-29T10:00:00Z" > "$d/$2.approved"
  printf '2026-10-29T10:00:01Z\n' > "$d/$2.applied"
}

r="$(mkrepo)"
hook "$r" "$(fx Edit file_path "$r/.agents/baselines/x.tsv" "$EDIT_X")"
[ "$rc" -eq 0 ] && [ "$(decision)" = deny ]; check "Edit of .agents/baselines/x.tsv with no approval -> deny, exit 0" $?
reason | grep -q '/keel-harness:build' && reason | grep -q '/keel-harness:rules' && reason | grep -q 'ADR' && reason | grep -q '\.agents/baselines/x\.tsv' && reason | grep -q 'harness'; check "the deny reason names the path, the category and the route (build, rules, ADR)" $?
[ -z "$err" ]; check "a deny writes nothing to stderr" $?
if command -v python3 >/dev/null 2>&1; then
  printf '%s' "$out" | python3 -I -c '
import sys, json
d = json.load(sys.stdin)
h = d["hookSpecificOutput"]
assert h["hookEventName"] == "PreToolUse" and h["permissionDecision"] == "deny" and h["permissionDecisionReason"]
assert list(d) == ["hookSpecificOutput"]
'; check "the deny output is the documented hookSpecificOutput JSON" $?
fi
hook "$r" "$(fx Write file_path "$r/scripts/gate.sh" "$WRITE_X")"; [ "$(decision)" = deny ]; check "Write of scripts/gate.sh -> deny" $?
hook "$r" "$(fx NotebookEdit notebook_path "$r/scripts/lib/n.ipynb" ',"new_source":"x"')"; [ "$(decision)" = deny ]; check "NotebookEdit (notebook_path) of scripts/lib/n.ipynb -> deny" $?
hook "$r" "$(fx NotebookEdit notebook_path "$r/src/n.ipynb" ',"new_source":"x"')"; silent; check "NotebookEdit of src/n.ipynb -> no output" $?
hook "$r" "$(fx Edit file_path ".agents/state.yml" "$EDIT_X")"; [ "$(decision)" = deny ]; check "a repo-relative path is read against the repository" $?
hook "$r" "$(fx Edit file_path "$r/src/../.agents/state.yml" "$EDIT_X")"; [ "$(decision)" = deny ]; check "a path with .. that lands in .agents/ -> deny" $?
hook "$r" "$(fx Edit file_path "$r/./scripts//hooks/./claude-protect.sh" "$EDIT_X")"; [ "$(decision)" = deny ]; check "the hook protects itself (scripts/hooks/**), however the path is spelled" $?
hook "$r" "$(fx Edit file_path "$r/.claude/settings.json" "$EDIT_X")"; [ "$(decision)" = ask ]; check ".claude/settings.json asks (agent-config): a human confirms each edit of the hook entry" $?
hook "$r" "$(fx Edit file_path "$r/.agents/consequence.yml" "$EDIT_X")"; [ "$(decision)" = deny ]; check "the consequence map itself is a harness path" $?
for p in .agents/gate.env .agents/rules/file-size.env scripts/sensors/lint.sh scripts/sensors/slow/mutation.sh scripts/harness-check.sh .github/workflows/keel.yml; do
  hook "$r" "$(fx Edit file_path "$r/$p" "$EDIT_X")"; [ "$(decision)" = deny ]; check "harness path denied: $p" $?
done
for p in .agents/run/flow/build.proposal .agents/plans/p.md .agents/progress.md; do
  hook "$r" "$(fx Write file_path "$r/$p" "$WRITE_X")"; silent; check "harness exceptions (!glob) are not protected: $p" $?
done
for p in src/a.ts README.md docs/adr/0001.md tests/a_test.sh scripts/build.sh; do
  hook "$r" "$(fx Edit file_path "$r/$p" "$EDIT_X")"; silent; check "unprotected path -> no output: $p" $?
done
hook "$r" "$(fx Edit file_path "/tmp/outside/.agents/x" "$EDIT_X")"; silent; check "a path outside the repository -> no output" $?
hook "$r" "$(fx Edit file_path "$r/../other/.agents/x" "$EDIT_X")"; silent; check "a sibling directory that goes out via .. -> no output" $?

# the other categories ask, and the reason names the category
hook "$r" "$(fx Edit file_path "$r/src/auth/x.ts" "$EDIT_X")"
[ "$rc" -eq 0 ] && [ "$(decision)" = ask ] && reason | grep -q 'auth'; check "src/auth/x.ts -> ask, the reason names auth" $?
hook "$r" "$(fx Write file_path "$r/db/migrations/001.sql" "$WRITE_X")"; [ "$(decision)" = ask ] && reason | grep -q 'data'; check "db/migrations/001.sql -> ask (data)" $?
hook "$r" "$(fx Write file_path "$r/terraform/main.tf" "$WRITE_X")"; [ "$(decision)" = ask ] && reason | grep -q 'infra'; check "terraform/main.tf -> ask (infra)" $?
hook "$r" "$(fx Write file_path "$r/openapi.yaml" "$WRITE_X")"; [ "$(decision)" = ask ] && reason | grep -q 'public-contract'; check "openapi.yaml -> ask (public-contract)" $?
hook "$r" "$(fx Write file_path "$r/.env" "$WRITE_X")"; [ "$(decision)" = ask ] && reason | grep -q 'secrets'; check ".env -> ask (secrets; permissions.deny is the hard block)" $?
hook "$r" "$(fx Write file_path "$r/apps/web/.env.local" "$WRITE_X")"; [ "$(decision)" = ask ]; check "a nested .env.local -> ask" $?
hook "$r" "$(fx Write file_path "$r/.env.example" "$WRITE_X")"; silent; check ".env.example is carved out of secrets -> no output" $?
hook "$r" "$(fx Write file_path "$r/certs/server.pem" "$WRITE_X")"; [ "$(decision)" = ask ]; check "**/*.pem -> ask" $?
if command -v python3 >/dev/null 2>&1; then
  printf '%s' "$out" | python3 -I -c '
import sys, json
h = json.load(sys.stdin)["hookSpecificOutput"]
assert h["hookEventName"] == "PreToolUse" and h["permissionDecision"] == "ask" and h["permissionDecisionReason"]
'; check "the ask output is the documented hookSpecificOutput JSON" $?
fi
hook "$r" "$(fx Write file_path "$r/src/auth/migrations/x.sql" "$WRITE_X")"; reason | grep -q 'auth' && reason | grep -q 'data'; check "a path in two categories names both" $?
hook "$r" "$(fx Write file_path "$r/.agents/auth/x" "$WRITE_X")"; [ "$(decision)" = deny ]; check "harness without approval wins over a consequential category (deny, not ask)" $?

# a current approval lets harness edits through
r="$(mkrepo)"; approve "$r" build
hook "$r" "$(fx Edit file_path "$r/.agents/baselines/x.tsv" "$EDIT_X")"; silent; check "with a current build approval -> no output" $?
hook "$r" "$(fx Write file_path "$r/src/auth/x.ts" "$WRITE_X")"; [ "$(decision)" = ask ]; check "a current approval does not turn ask into allow" $?
r="$(mkrepo)"; approve "$r" rules
hook "$r" "$(fx Edit file_path "$r/.agents/rules/a.env" "$EDIT_X")"; silent; check "with a current rules approval -> no output" $?
r="$(mkrepo)"; approve "$r" assess
hook "$r" "$(fx Edit file_path "$r/.agents/state.yml" "$EDIT_X")"; [ "$(decision)" = deny ]; check "an approval for any other skill name is not a build/rules approval" $?
# expired: applied more than 2 hours ago
r="$(mkrepo)"; approve "$r" build
touch -d '4 hours ago' "$r/.agents/run/flow/build.approved"; touch -d '3 hours ago' "$r/.agents/run/flow/build.applied"
hook "$r" "$(fx Edit file_path "$r/.agents/state.yml" "$EDIT_X")"; [ "$(decision)" = deny ]; check "an approval applied 3 hours ago has expired -> deny" $?
r="$(mkrepo)"; approve "$r" build
touch -d '4 hours ago' "$r/.agents/run/flow/build.approved"; touch -d '90 minutes ago' "$r/.agents/run/flow/build.applied"
hook "$r" "$(fx Edit file_path "$r/.agents/state.yml" "$EDIT_X")"; silent; check "an approval applied 90 minutes ago is still current" $?
# applied older than approved: the proposal was re-approved and never applied
r="$(mkrepo)"; approve "$r" build
touch -d '30 minutes ago' "$r/.agents/run/flow/build.applied"; touch -d '10 minutes ago' "$r/.agents/run/flow/build.approved"
hook "$r" "$(fx Edit file_path "$r/.agents/state.yml" "$EDIT_X")"; [ "$(decision)" = deny ]; check "applied older than approved -> deny" $?
# stale hash: the proposal changed after the approval
r="$(mkrepo)"; approve "$r" build
printf 'something else\n' > "$r/.agents/run/flow/build.proposal"
hook "$r" "$(fx Edit file_path "$r/.agents/state.yml" "$EDIT_X")"; [ "$(decision)" = deny ]; check "an approval whose hash is not the proposal's -> deny" $?
r="$(mkrepo)"; approve "$r" build; rm "$r/.agents/run/flow/build.applied"
hook "$r" "$(fx Edit file_path "$r/.agents/state.yml" "$EDIT_X")"; [ "$(decision)" = deny ]; check "approved but never applied -> deny" $?
r="$(mkrepo)"; approve "$r" build; rm "$r/.agents/run/flow/build.proposal"
hook "$r" "$(fx Edit file_path "$r/.agents/state.yml" "$EDIT_X")"; [ "$(decision)" = deny ]; check "no proposal file -> deny" $?
r="$(mkrepo)"; approve "$r" build; printf '\n' > "$r/.agents/run/flow/build.approved"
hook "$r" "$(fx Edit file_path "$r/.agents/state.yml" "$EDIT_X")"; [ "$(decision)" = deny ]; check "an empty approval record -> deny" $?
# a build approval that expired does not hide a still-current rules approval
r="$(mkrepo)"; approve "$r" build; approve "$r" rules
touch -d '4 hours ago' "$r/.agents/run/flow/build.approved" "$r/.agents/run/flow/build.applied"
hook "$r" "$(fx Edit file_path "$r/.agents/state.yml" "$EDIT_X")"; silent; check "an expired build approval and a current rules approval -> allowed" $?

# nothing to say: no map, a garbled payload, another tool
r="$(mkrepo)"; rm "$r/.agents/consequence.yml"
hook "$r" "$(fx Edit file_path "$r/.agents/state.yml" "$EDIT_X")"; silent; check "no consequence map -> no output, exit 0" $?
r="$(mkrepo)"
for bad in '' 'not json at all' '{' '{"tool_name":"Write","tool_input":{"file_path":' '{"tool_name":"Edit","tool_input":{"file_path":null}}' '{"tool_name":"Edit","tool_input":{}}' '[1,2,3]' '{"tool_name":"Edit","tool_input":{"file_path":""}}' '{"tool_name":"Edit","tool_input":{"file_path":"\u"}}'; do
  hook "$r" "$bad"; silent; check "malformed stdin -> no output, exit 0, no stderr: ${bad:-<empty>}" $?
done
hook "$r" '{"tool_name":"Bash","tool_input":{"command":"echo x > .agents/state.yml"}}'; silent; check "a Bash command is not this hook's business (known limit)" $?
hook "$r" '{"tool_name":"Read","tool_input":{"file_path":"'"$r"'/.agents/state.yml"}}'; silent; check "a Read of a harness file -> no output" $?
hook "$r" '{"tool_input":{"file_path":"'"$r"'/.agents/state.yml"},"tool_name":"Edit"}'; [ "$(decision)" = deny ]; check "the key order does not matter" $?
hook "$r" '{ "tool_name" : "Edit" , "tool_input" : { "file_path" : "'"$r"'/.agents/state.yml" } }'; [ "$(decision)" = deny ]; check "spacing around colons and braces does not matter" $?
hook "$r" "$(fx Edit file_path "$r/.agents/we\\\"ird/x" "$EDIT_X")"; [ "$(decision)" = deny ] && printf '%s' "$out" | grep -q 'we\\"ird'; check "a path with an escaped quote is read and re-escaped in the reason" $?
# a map with junk lines is read without an error; the valid lines still count
r="$(mkrepo)"; printf 'this line has no colon\n:\n\n   \n# a comment\nharness:\nBAD CAT: x\nharness: scripts/extra.sh   # trailing comment\n' >> "$r/.agents/consequence.yml"
hook "$r" "$(fx Edit file_path "$r/scripts/extra.sh" "$EDIT_X")"; [ "$(decision)" = deny ] && [ -z "$err" ]; check "junk lines, an empty glob and a trailing comment in the map do not break it" $?
printf 'harness: scripts/crlf.sh\r\n' >> "$r/.agents/consequence.yml"
hook "$r" "$(fx Edit file_path "$r/scripts/crlf.sh" "$EDIT_X")"; [ "$(decision)" = deny ]; check "a CRLF map line works" $?
# last match wins: a negation, then the same category again
r="$(mkrepo)"; printf 'harness: scripts/x/**\n!scripts/x/keep/**\n' >> "$r/.agents/consequence.yml"
hook "$r" "$(fx Edit file_path "$r/scripts/x/a.sh" "$EDIT_X")"; [ "$(decision)" = deny ]; check "map: a glob matches" $?
hook "$r" "$(fx Edit file_path "$r/scripts/x/keep/a.sh" "$EDIT_X")"; silent; check "map: !glob removes matches from the category above it" $?

# where the repository root comes from
r="$(mkrepo)"; mkdir -p "$r/src/deep"
out="$(cd "$r/src/deep" && printf '%s' "$(fx Edit file_path ".agents/state.yml" "$EDIT_X")" | env -u CLAUDE_PROJECT_DIR bash "$r/scripts/hooks/claude-protect.sh" 2>/dev/null)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; check "run from a subdirectory: a relative path is read against the root (git top level), not the directory" $?
out="$(cd "$r/src/deep" && printf '%s' "$(fx Edit file_path "$r/.agents/state.yml" "$EDIT_X")" | env -u CLAUDE_PROJECT_DIR bash "$r/scripts/hooks/claude-protect.sh" 2>/dev/null)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; check "run from a subdirectory: an absolute path is denied against the git top level" $?
out="$(cd "$W" && printf '%s' "$(fx Edit file_path ".agents/state.yml" "$EDIT_X")" | CLAUDE_PROJECT_DIR="$r" bash "$r/scripts/hooks/claude-protect.sh" 2>/dev/null)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; check "CLAUDE_PROJECT_DIR is the root, whatever the current directory" $?
# a symlinked directory that leads into the harness
r="$(mkrepo)"; ln -s ../.agents "$r/src/link"
hook "$r" "$(fx Write file_path "$r/src/link/state.yml" "$WRITE_X")"; [ "$(decision)" = deny ]; check "a path through a symlinked directory into .agents/ -> deny" $?
# a root reached through a symlink
r="$(mkrepo)"; ln -s "$r" "$W/rootlink"
hook "$r" "$(fx Edit file_path "$W/rootlink/.agents/state.yml" "$EDIT_X")" CLAUDE_PROJECT_DIR="$r"; [ "$(decision)" = deny ]; check "a path spelled through a symlink to the root -> deny" $?
hook "$r" "$(fx Edit file_path "$r/.agents/state.yml" "$EDIT_X")" CLAUDE_PROJECT_DIR="$W/rootlink"; [ "$(decision)" = deny ]; check "CLAUDE_PROJECT_DIR spelled through a symlink -> deny" $?
# a repository path with a space
r="$(mkrepo)"; mkdir -p "$r/my dir"; cp -R "$r/.agents" "$r/my dir/" 2>/dev/null
hook "$r" "$(fx Edit file_path "$r/.agents/a b.txt" "$EDIT_X")"; [ "$(decision)" = deny ]; check "a file name with a space -> deny" $?

# the hook never writes
r="$(mkrepo)"; (cd "$r" && git add -A && git commit -q -m m)
before="$(cd "$r" && git status --porcelain)"
hook "$r" "$(fx Edit file_path "$r/.agents/state.yml" "$EDIT_X")"
[ "$before" = "$(cd "$r" && git status --porcelain)" ] && [ ! -e "$r/.agents/run" ]; check "the hook writes nothing in the repository" $?

# --- the default map (assets/core/consequence.yml) says what the plan says
r="$(mkrepo)"
for p in .agents/baselines/lint.tsv .agents/state.yml .agents/gate.env scripts/gate.sh scripts/harness-check.sh scripts/sensors/guard.sh scripts/lib/baseline.sh scripts/hooks/claude-stop.sh .github/workflows/keel.yml; do
  hook "$r" "$(fx Edit file_path "$r/$p" "$EDIT_X")"; [ "$(decision)" = deny ]; check "default map: harness: $p" $?
done
grep -qE '^harness:' "$MAP_SRC" && grep -qE '^secrets:' "$MAP_SRC"; check "default map declares harness and secrets" $?
hook "$r" "$(fx Edit file_path "$r/.claude/settings.json" "$EDIT_X")"; [ "$(decision)" = ask ]; check "default map: agent-config: .claude/settings.json asks" $?
! grep -qE '^(auth|data|infra|public-contract):' "$MAP_SRC"; check "default map declares no discovered category (build adds only what exists)" $?

# --- the settings fragment
FR="$KEEL/assets/adapters/claude/settings-protect.json"
[ -f "$FR" ]; check "settings-protect.json exists" $?
if command -v python3 >/dev/null 2>&1 && [ -f "$FR" ]; then
  python3 -I - "$FR" <<'PY'
import sys, json
d = json.load(open(sys.argv[1]))
e = d["hooks"]["PreToolUse"]
assert len(e) == 1 and e[0]["matcher"] == "Write|Edit|NotebookEdit", e
h = e[0]["hooks"]
assert len(h) == 1 and h[0]["type"] == "command" and h[0]["timeout"] == 10, h
assert h[0]["command"] == '"${CLAUDE_PROJECT_DIR}"/scripts/hooks/claude-protect.sh', h[0]["command"]
deny = d["permissions"]["deny"]
for r in ("Read(**/.env)", "Edit(**/.env)", "Read(**/.env.*)", "Edit(**/.env.*)", "Read(**/*.pem)", "Edit(**/*.pem)", "Read(**/*.key)", "Edit(**/*.key)"):
    assert r in deny, r
for r in deny:
    assert r.startswith(("Read(", "Edit(")) and r.endswith(")"), r
# a carve-out must come after the rules it carves from (permissions docs, "How path patterns match")
assert deny.index("Read(!**/.env.example)") > deny.index("Read(**/.env.*)")
assert deny.index("Edit(!**/.env.example)") > deny.index("Edit(**/.env.*)")
assert "Write(" not in "".join(deny) and "NotebookEdit(" not in "".join(deny)
PY
  check "settings-protect.json: one PreToolUse entry (exact matcher, timeout 10, literal CLAUDE_PROJECT_DIR) and Read/Edit deny rules for the secrets globs" $?
fi
grep -q 'code.claude.com/docs/en/permissions' "$FR" && grep -q 'code.claude.com/docs/en/hooks' "$FR"; check "settings-protect.json cites the permissions and hooks docs" $?
# the fragment merged into the stop-hook settings (what build does) keeps both hooks and stays valid
if command -v python3 >/dev/null 2>&1 && [ -f "$FR" ]; then
  python3 -I - "$FR" "$KEEL/assets/adapters/claude/settings-stop.json" <<'PY'
import sys, json
p = json.load(open(sys.argv[1])); s = json.load(open(sys.argv[2]))
s["hooks"]["PreToolUse"] = p["hooks"]["PreToolUse"]
s["permissions"] = {"deny": p["permissions"]["deny"]}
assert "Stop" in s["hooks"] and "PreToolUse" in s["hooks"]
json.dumps(s)
PY
  check "the fragment merges into the Stop-hook settings without touching the Stop entry" $?
fi
# every secrets glob of the default map has a Read and an Edit deny rule in the fragment
for g in '**/.env' '**/.env.*' '**/*.pem' '**/*.key'; do
  grep -qF "\"Read($g)\"" "$FR" && grep -qF "\"Edit($g)\"" "$FR"; check "fragment: Read and Edit deny rules for the secrets glob $g" $?
  grep -qF "secrets: $g" "$MAP_SRC"; check "default map: secrets glob $g" $?
done

# --- contracts/consequence.md
C="$KEEL/contracts/consequence.md"
[ -f "$C" ]; check "contracts/consequence.md exists" $?
for s in '.agents/consequence.yml' 'harness' 'secrets' 'auth' 'public-contract' '!glob' '/**' 'permissions.deny' 'Known limit' 'Bash' 'guard' \
         'code.claude.com/docs/en/hooks' 'code.claude.com/docs/en/permissions' 'notebook_path' '2 hours' 'applied' 'ask'; do
  grep -qF -- "$s" "$C"; check "consequence.md contains: $s" $?
done
finish
