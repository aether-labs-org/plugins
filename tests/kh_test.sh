#!/usr/bin/env bash
# kh v0.4 M0: end-to-end acceptance of `kh run -- <cmd>` and `kh show` through the built binary
# (spec section 14, M0), plus the Go unit tests and static checks via `make -C cli/kh test`.
# shellcheck disable=SC2319  # "check ... $?" after a test is this suite's idiom (see keel_helpers.sh)
set -uo pipefail
. "$(dirname "$0")/keel_helpers.sh"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v go >/dev/null 2>&1; then
  if [ -n "${CI:-}" ]; then fail "kh: go is required in CI"; finish; fi
  echo "  skip kh: go not installed"; exit 0
fi

W="$(mktemp -d)"; _keel_tmps="$_keel_tmps $W"

# KH_BIN lets a caller point the suite at a prebuilt binary; by default it is built here.
if [ -n "${KH_BIN:-}" ]; then
  KH="$KH_BIN"
else
  KH="$W/kh"
  (cd "$REPO_ROOT/cli/kh" && CGO_ENABLED=0 go build -trimpath -buildvcs=false -o "$KH" .) 2>&1 | cat
  [ "${PIPESTATUS[0]}" -eq 0 ]; check "kh builds" $?
  [ -x "$KH" ] || finish
  make -C "$REPO_ROOT/cli/kh" test 2>&1 | cat
  [ "${PIPESTATUS[0]}" -eq 0 ]; check "kh: gofmt, go vet and go test pass" $?
fi

# k DIR ARGS... -> out (stdout and stderr together), rc
k() { out="$(cd "$1" && "$KH" "${@:2}" 2>&1)"; rc=$?; }
# krepo -> a git repository with an empty .agents/keel.yml committed
krepo() {
  local d
  d="$(mktemp -d "$W/repo.XXXXXX")"
  (cd "$d" && git init -q . && git config user.email t@t && git config user.name t \
    && mkdir -p .agents && : > .agents/keel.yml && git add -A && git commit -q -m seed)
  printf '%s\n' "$d"
}
runs_dir() { printf '%s/.agents/run/runs\n' "$1"; }
# jget FILE KEY -> the value of a top-level key of a JSON file
jget() { python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$1" "$2"; }
# first_id -> the id in the first line of $out ("... [run <id>]")
first_id() { printf '%s\n' "$out" | head -n 1 | sed -E 's/.*\[run ([^]]+)\]$/\1/'; }
nlines() { printf '%s\n' "$1" | wc -l | tr -d ' '; }
# has FILE_OR_TEXT NEEDLE (fixed string); for files pass via has_file
has() { printf '%s' "$1" | grep -F -- "$2" >/dev/null; }
has_file() { grep -F -- "$2" "$1" >/dev/null; }
alive() { pgrep -f "$1" >/dev/null 2>&1; }
TOK="ghp_$(printf 'a1B2%.0s' 1 2 3 4 5 6 7 8 9)" # ghp_ + 36 alphanumerics
SECRET='wJalrXUtnFEMI/K7MDENG'

# ------------------------------------------------------------------ version and usage
r="$(krepo)"
k "$r" version; [ "$rc" -eq 0 ] && [ "$out" = "kh 0.5.0-dev" ]; check "kh version prints kh 0.5.0-dev" $?
k "$r"; [ "$rc" -eq 64 ]; check "kh with no arguments exits 64" $?
k "$r" run a b; [ "$rc" -eq 64 ]; check "usage: kh run <script> <extra> without -- exits 64" $?
k "$r" run --timeout x -- true; [ "$rc" -eq 64 ]; check "usage: kh run with a bad --timeout exits 64" $?
k "$r" run --; [ "$rc" -eq 64 ]; check "usage: kh run -- with no command exits 64" $?

# ------------------------------------------------------------------ pass
k "$r" run -- true
[ "$rc" -eq 0 ] && [ "$(nlines "$out")" -eq 2 ]; check "pass: rc 0 and exactly 2 lines" $?
printf '%s\n' "$out" | head -n 1 | grep -E '^true  PASS  exit=0  [0-9.]+m?s  completed  \[run [0-9]{8}-[0-9]{6}-[0-9a-f]{4}\]$' >/dev/null
check "pass: header format" $?
id="$(first_id)"
[ -f "$(runs_dir "$r")/$id/meta.json" ] && [ -f "$(runs_dir "$r")/$id/output.log" ]; check "pass: evidence directory holds meta.json and output.log" $?

# ------------------------------------------------------------------ exit codes
for n in 1 2 137; do
  r="$(krepo)"
  k "$r" run -- sh -c "exit $n"
  id="$(first_id)"; m="$(runs_dir "$r")/$id/meta.json"
  [ "$rc" -eq 1 ] && has "$out" "exit=$n" && [ "$(jget "$m" exit_code)" = "$n" ] && [ "$(jget "$m" status)" = "fail" ]
  check "exit codes: exit $n -> rc 1, exit=$n, meta exit_code $n, status fail" $?
done

# ------------------------------------------------------------------ not found
r="$(krepo)"
k "$r" run -- kh-no-such-cmd
[ "$rc" -eq 2 ] && has "$out" "SKIP" && has "$out" "not found - install it (see AGENTS.md)"; check "not found: rc 2, SKIP, install hint" $?

# ------------------------------------------------------------------ timeout
r="$(krepo)"; u="$RANDOM$RANDOM"
k "$r" run --timeout 300ms -- sh -c "sleep 30.$u & sleep 30.$u"
[ "$rc" -eq 3 ] && has "$out" "ERROR  exit=-" && has "$out" "timed out after 300ms"; check "timeout: rc 3, ERROR exit=-, timed out after 300ms" $?
! alive "sleep 30.$u"; check "timeout: no child process left" $?

# ------------------------------------------------------------------ SIGINT
r="$(krepo)"; u="$RANDOM$RANDOM"
( cd "$r" && exec "$KH" run -- sleep "31.$u" ) >"$W/int.out" 2>&1 &
pid=$!
for _ in $(seq 1 100); do alive "sleep 31.$u" && break; sleep 0.1; done
kill -INT "$pid"
wait "$pid"; rc=$?
id="$(ls "$(runs_dir "$r")" | head -n 1)"; m="$(runs_dir "$r")/$id/meta.json"
[ "$rc" -eq 3 ]; check "SIGINT: kh exits 3" $?
! alive "sleep 31.$u"; check "SIGINT: the command's process group is gone" $?
[ -f "$m" ] && [ "$(jget "$m" status)" = "error" ] && [ "$(jget "$m" summary)" = "interrupted" ]; check "SIGINT: meta.json says error / interrupted" $?

# ------------------------------------------------------------------ redaction
r="$(krepo)"
AWS_SECRET_ACCESS_KEY="$SECRET" k "$r" run -- sh -c "echo \"\$AWS_SECRET_ACCESS_KEY\"; echo $TOK"
id="$(first_id)"; d="$(runs_dir "$r")/$id"
[ "$rc" -eq 0 ]; check "redaction: the command ran" $?
[ -n "$out" ] && ! has "$out" "$SECRET" && ! has "$out" "$TOK"; check "redaction: neither secret appears on stdout" $?
[ -f "$d/output.log" ] && ! has_file "$d/output.log" "$SECRET" && ! has_file "$d/output.log" "$TOK"; check "redaction: neither secret appears in output.log" $?
[ -f "$d/meta.json" ] && ! has_file "$d/meta.json" "$SECRET" && ! has_file "$d/meta.json" "$TOK"; check "redaction: neither secret appears in meta.json" $?
[ "$(grep -c '‹redacted›' "$d/output.log")" -eq 2 ]; check "redaction: output.log holds the placeholder twice" $?

# ------------------------------------------------------------------ secret in argv
r="$(krepo)"
k "$r" run -- echo "$TOK"
id="$(first_id)"; d="$(runs_dir "$r")/$id"
[ -f "$d/output.log" ] && [ -f "$d/meta.json" ] && [ -n "$out" ] && ! has "$out" "$TOK" && ! has_file "$d/output.log" "$TOK" && ! has_file "$d/meta.json" "$TOK"; check "secret in argv: absent from stdout, output.log and meta.json" $?
grep -F '‹redacted›' "$d/meta.json" >/dev/null; check "secret in argv: meta.json command carries the placeholder" $?

# ------------------------------------------------------------------ runs from the root
r="$(krepo)"; mkdir -p "$r/sub/deep"
k "$r/sub/deep" run -- pwd
id="$(first_id)"; phys="$(cd "$r" && pwd -P)"
[ "$(cat "$(runs_dir "$r")/$id/output.log")" = "$phys" ]; check "runs from the root: pwd from a subdirectory prints the repository root" $?

# ------------------------------------------------------------------ retention
r="$(krepo)"
for _ in $(seq 1 52); do k "$r" run -- true; done
[ "$(ls "$(runs_dir "$r")" | wc -l | tr -d ' ')" -eq 50 ]; check "retention: 52 runs leave exactly 50 directories" $?
[ -d "$(runs_dir "$r")/$(first_id)" ]; check "retention: the last run is kept" $?

# ------------------------------------------------------------------ show
r="$(krepo)"
k "$r" run -- sh -c 'echo before; echo "error: boom"; echo after; exit 1'
runout="$out"; id="$(first_id)"; log="$(runs_dir "$r")/$id/output.log"
k "$r" show "$id"; [ "$rc" -eq 0 ] && [ "$out" = "$runout" ]; check "show: default output equals the run's output" $?
(cd "$r" && "$KH" show "$id" --full >"$W/full.out" 2>&1); cmp -s "$W/full.out" "$log"; check "show --full equals output.log" $?
(cd "$r" && "$KH" show "$id" --json | python3 -I -c 'import json,sys; json.load(sys.stdin)'); check "show --json parses as JSON" $?
(cd "$r" && "$KH" show "$id" --json) | cmp -s - "$(runs_dir "$r")/$id/meta.json"; check "show --json is meta.json" $?
k "$r" show "$id" --failures
[ "$rc" -eq 0 ] && has "$out" "2: error: boom" && [ "$(printf '%s\n' "$out" | tail -n +2 | grep -cvE '^([0-9]+: |--$)')" -eq 0 ]; check "show --failures: lines start with <N>: " $?
k "$r" show 20000101-000000-dead; [ "$rc" -eq 64 ] && has "$out" "no run"; check "show: unknown id exits 64 with 'no run'" $?
k "$r" show ../x; [ "$rc" -eq 64 ] && has "$out" "no run"; check "show: malformed id exits 64 with 'no run'" $?

# ------------------------------------------------------------------ no keel.yml
n="$(mktemp -d "$W/plain.XXXXXX")"; git init -q "$n"
k "$n" run -- true; [ "$rc" -eq 3 ] && has "$out" "no .agents/keel.yml"; check "no keel.yml: run exits 3" $?
k "$n" show 20000101-000000-dead; [ "$rc" -eq 3 ] && has "$out" "no .agents/keel.yml"; check "no keel.yml: show exits 3" $?
ng="$(mktemp -d "$W/nogit.XXXXXX")"
k "$ng" run -- true; [ "$rc" -eq 3 ] && has "$out" "not a git repository"; check "not a git repository: run exits 3" $?

# ------------------------------------------------------------------ v0.5: config, scripts, gates, hooks (end to end)
# harness [extra-yml] -> a committed git repository with a v0.5 harness: scripts ok/bad/lint(files), gates fast/commit/slow
harness() {
  local d
  d="$(mktemp -d "$W/h.XXXXXX")"
  (cd "$d" && git init -q . && git config user.email t@t && git config user.name t && mkdir -p .agents docs/adr src \
    && printf '.agents/run/\n' > .gitignore \
    && cat > .agents/keel.yml <<YML
version: 1
guides: [AGENTS.md]
githooks: { mode: native, pre-commit: commit, commit-msg: cm }
scripts:
  ok: "true"
  bad: "false"
  test: { run: "./gradlew test" }
  check: { run: "test ! -e FAIL" }
  cm: { builtin: commit-message, with: { pattern: '^(feat|fix): .+' } }
gates:
  fast: { scripts: [guard, check] }
  commit: { scripts: [guard, ok], changes: staged }
  slow: { scripts: [guard, ok], changes: branch }
  broken: { scripts: [ok, bad] }
YML
    printf '# agents\n' > AGENTS.md && printf 'package main\n' > src/main.go && git add -A && git commit -q -m seed)
  printf '%s\n' "$d"
}
h="$(harness)"
k "$h" validate; [ "$rc" -eq 0 ] && [ -z "$out" ]; check "validate: a valid keel.yml is silent, exit 0" $?
k "$h" schema keel; [ "$rc" -eq 0 ] && printf '%s' "$out" | python3 -I -c 'import json,sys; json.load(sys.stdin)'; check "schema keel: valid JSON" $?
k "$h" schema nope; [ "$rc" -eq 64 ]; check "schema: unknown name exits 64" $?
k "$h" run ok; [ "$rc" -eq 0 ] && has "$out" "ok  PASS"; check "run <script>: pass" $?
k "$h" run bad; [ "$rc" -eq 1 ] && has "$out" "bad  FAIL"; check "run <script>: fail exits 1" $?
k "$h" run nope; [ "$rc" -eq 64 ] && has "$out" "unknown script"; check "run <script>: unknown script exits 64" $?
k "$h" gate fast; [ "$rc" -eq 0 ] && has "$out" "gate: fast - PASSED"; check "gate: PASSED exits 0 with the verdict line" $?
k "$h" gate broken; [ "$rc" -eq 1 ] && has "$out" "gate: broken - FAILED (1 of 2)"; check "gate: FAILED exits 1" $?
k "$h" gate broken --json; printf '%s' "$out" | python3 -I -c 'import json,sys; d=json.load(sys.stdin); assert d["status"]=="fail" and len(d["scripts"])==2'; check "gate --json parses" $?
printf 'version: 2\n' > "$h/.agents/keel.yml"
k "$h" validate; [ "$rc" -eq 3 ] && has "$out" "keel.yml: version: unsupported version 2"; check "validate: an invalid keel.yml exits 3 with one line per issue" $?
printf 'version: 1\nscripts: { a: "true" }\ngates: { fast: { scripts: [a] } }\n' > "$h/.agents/keel.yml"
k "$h" validate; [ "$rc" -eq 3 ] && has "$out" 'required gate "commit" is missing' && has "$out" 'gate "fast" must list guard'; check "validate: required gates and guard in them" $?
nested="$(harness)"; mkdir -p "$nested/pkg/.agents"; cp "$nested/.agents/keel.yml" "$nested/pkg/.agents/keel.yml"
k "$nested/pkg" validate; [ "$rc" -eq 3 ] && has "$out" "nested .agents/keel.yml at pkg"; check "a nested keel.yml is rejected" $?

# pin check: a lock for another version stops run/gate/measure/guard, not run -- / show / validate
h="$(harness)"
printf 'version=9.9.9\nlinux-amd64=%s\nlinux-arm64=%s\ndarwin-amd64=%s\ndarwin-arm64=%s\n' $(printf 'a%.0s' $(seq 64)) $(printf 'a%.0s' $(seq 64)) $(printf 'a%.0s' $(seq 64)) $(printf 'a%.0s' $(seq 64)) > "$h/.agents/keel.lock"
k "$h" run ok; [ "$rc" -eq 3 ] && has "$out" "pin mismatch: keel.lock pins 9.9.9"; check "pin: run <script> refuses a mismatch" $?
k "$h" gate fast; [ "$rc" -eq 3 ] && has "$out" "pin mismatch"; check "pin: gate refuses a mismatch" $?
k "$h" run -- true; [ "$rc" -eq 0 ]; check "pin: run -- <cmd> is exempt" $?
k "$h" validate; [ "$rc" -eq 0 ]; check "pin: validate is exempt" $?

# hooks: payloads piped into the built binary, answers read with python
hk() { # hk REPO FILE... -> out (stdout), rc ; the payload is $PAYLOAD
  out="$(cd "$1" && printf '%s' "$PAYLOAD" | "$KH" hook "${@:2}" 2>"$W/hk.err")"; rc=$?
}
jq_() { printf '%s' "$out" | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))' "$1"; }
h="$(harness)"; phys="$(cd "$h" && pwd -P)"
PAYLOAD='{"hook_event_name":"PreToolUse","tool_name":"Write","cwd":"'"$phys"'","permission_mode":"default","tool_input":{"file_path":"'"$phys"'/AGENTS.md","content":"x"}}'
hk "$h" pre-tool-use; [ "$rc" -eq 0 ] && [ "$(jq_ 'd["hookSpecificOutput"]["permissionDecision"]')" = ask ] && [ "$(jq_ 'd["permissionDecision"]')" = ask ] && [ "$(jq_ 'd["hookSpecificOutput"]["hookEventName"]')" = PreToolUse ]; check "hook pre-tool-use: protected Write asks, in both shapes" $?
has "$out" "AGENTS.md" && has "$out" "guides"; check "hook pre-tool-use: the reason names the file and its class" $?
PAYLOAD='{"hook_event_name":"PreToolUse","tool_name":"Write","cwd":"'"$phys"'","permission_mode":"bypassPermissions","tool_input":{"file_path":"AGENTS.md"}}'
hk "$h" pre-tool-use; [ "$(jq_ 'd["permissionDecision"]')" = deny ]; check "hook pre-tool-use: bypassPermissions denies" $?
PAYLOAD='{"hook_event_name":"PreToolUse","tool_name":"NotebookEdit","cwd":"'"$phys"'","permission_mode":"default","tool_input":{"notebook_path":"docs/../AGENTS.md"}}'
hk "$h" pre-tool-use; [ "$(jq_ 'd["permissionDecision"]')" = ask ]; check "hook pre-tool-use: notebook_path with .. resolves to the protected file" $?
PAYLOAD='{"hook_event_name":"PreToolUse","tool_name":"Write","cwd":"'"$phys"'","permission_mode":"default","tool_input":{"file_path":"src/main.go"}}'
hk "$h" pre-tool-use; [ "$rc" -eq 0 ] && [ -z "$out" ]; check "hook pre-tool-use: an unprotected path prints nothing" $?
PAYLOAD='{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"'"$phys"'","permission_mode":"default","tool_input":{"command":"sed -i '"'"'/guard/d'"'"' .agents/keel.yml"}}'
hk "$h" pre-tool-use; [ "$(jq_ 'd["permissionDecision"]')" = deny ]; check "hook pre-tool-use: the P-1 shell edit of keel.yml is denied" $?
PAYLOAD='{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"'"$phys"'","permission_mode":"default","tool_input":{"command":"git commit --no-verify -m x"}}'
hk "$h" pre-tool-use; [ "$(jq_ 'd["permissionDecision"]')" = deny ]; check "hook pre-tool-use: --no-verify is denied" $?
PAYLOAD='{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"'"$phys"'","permission_mode":"default","tool_input":{"command":"cd app && ./gradlew test | tail"}}'
hk "$h" pre-tool-use; [ "$(jq_ 'd["permissionDecision"]')" = deny ] && has "$out" "kh run test" && has "$out" "do not pipe its output"; check "hook pre-tool-use: a declared script is intercepted" $?
PAYLOAD='{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"'"$phys"'","permission_mode":"default","tool_input":{"command":"make foo"}}'
hk "$h" pre-tool-use; [ "$rc" -eq 0 ] && [ -z "$out" ]; check "hook pre-tool-use: an undeclared command is allowed" $?
PAYLOAD='{"hook_event_name":"PreToolUse","tool_name":"Write","cwd":"'"$phys"'","permission_mode":"default","tool_input":{"file_path":"AGENTS.md"}}'
mkdir -p "$h/sub dir"; hk "$h/sub dir" pre-tool-use; [ "$(jq_ 'd["permissionDecision"]')" = ask ]; check "hook pre-tool-use: works from a subdirectory (root from the payload cwd)" $?
nog="$(mktemp -d "$W/nogit.XXXXXX")"
PAYLOAD='{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"'"$nog"'","permission_mode":"default","tool_input":{"command":"ls"}}'
hk "$nog" pre-tool-use; [ "$rc" -eq 0 ] && [ "$(jq_ 'd["permissionDecision"]')" = ask ] && has "$out" "kh unavailable"; check "hook pre-tool-use: outside a repository fails safe (ask)" $?
PAYLOAD='{"hook_event_name":"PreToolUse","tool_name":"Write","cwd":"'"$nog"'","permission_mode":"default","tool_input":{"file_path":"AGENTS.md"}}'
hk "$nog" pre-tool-use --setup; [ "$rc" -eq 0 ] && [ "$(jq_ 'd["permissionDecision"]')" = ask ] && has "$out" "kh unavailable"; check "hook pre-tool-use --setup: outside a repository fails safe too" $?
sr="$(mktemp -d "$W/setup.XXXXXX")"; git init -q "$sr"; srp="$(cd "$sr" && pwd -P)"
PAYLOAD='{"hook_event_name":"PreToolUse","tool_name":"Write","cwd":"'"$srp"'","permission_mode":"default","tool_input":{"file_path":"'"$srp"'/AGENTS.md"}}'
hk "$sr" pre-tool-use --setup; [ "$(jq_ 'd["permissionDecision"]')" = ask ] && ! has "$out" "unavailable"; check "hook pre-tool-use --setup: a repository without keel.yml still protects the guides" $?

# stop: silent on green, blocks once on a failure, lets the agent stop on the same failure, silent again when fixed
h="$(harness)"; phys="$(cd "$h" && pwd -P)"
PAYLOAD='{"hook_event_name":"Stop","cwd":"'"$phys"'","stop_hook_active":false}'
hk "$h" stop; [ "$rc" -eq 0 ] && [ -z "$out" ]; check "hook stop: green tree is silent" $?
: > "$h/FAIL"
hk "$h" stop; [ "$(jq_ 'd["decision"]')" = block ] && has "$out" "gate: fast - FAILED"; check "hook stop: a failure blocks with the gate result" $?
PAYLOAD='{"hook_event_name":"Stop","cwd":"'"$phys"'","stop_hook_active":true}'
hk "$h" stop; [ "$rc" -eq 0 ] && ! has "$out" '"decision"' && has "$out" "the agent stopped with this failure"; check "hook stop: the same failure with stop_hook_active lets the agent stop" $?
PAYLOAD='{"hook_event_name":"Stop","cwd":"'"$phys"'","stop_hook_active":false}'
hk "$h" stop; [ "$rc" -eq 0 ] && ! has "$out" '"decision"' && has "$out" "the agent stopped with this failure"; check "hook stop: the same failure on a new turn (stop_hook_active false) is not relayed again" $?
hk "$h" stop; ! has "$out" '"decision"'; check "hook stop: ... nor on the turn after that" $?
rm "$h/FAIL"; PAYLOAD='{"hook_event_name":"Stop","cwd":"'"$phys"'","stop_hook_active":false}'
hk "$h" stop; [ -z "$out" ]; check "hook stop: silent again once fixed" $?
: > "$h/FAIL"
hk "$h" stop; [ "$(jq_ 'd["decision"]')" = block ]; check "hook stop: the same failure after a green blocks again (a new occurrence)" $?
rm "$h/FAIL"

# commit-msg
h="$(harness)"; echo 'feat: ok' > "$h/MSG"; k "$h" hook commit-msg MSG; [ "$rc" -eq 0 ]; check "hook commit-msg: a matching message passes" $?
echo 'wip' > "$h/MSG"; k "$h" hook commit-msg MSG; [ "$rc" -eq 1 ] && has "$out" "^(feat|fix): .+"; check "hook commit-msg: a message that does not match exits 1 with the pattern" $?

# guard through the binary: a baseline row appended without an ADR (the D1 reproduction)
h="$(harness)"
(cd "$h" && mkdir -p .agents/baselines && printf '# measured_at: 2026-11-01 review_by: 2027-05-01\nsrc/main.go\t1\n' > .agents/baselines/x.tsv && git add -A && git commit -q -m base)
printf 'src/huge.go\t900\n' >> "$h/.agents/baselines/x.tsv"
k "$h" guard; [ "$rc" -eq 1 ] && has "$out" "baseline row added src/huge.go"; check "guard: a baseline row appended without an ADR fails" $?
printf 'ADR: we baseline .agents/baselines/x.tsv for the migration.\n' > "$h/docs/adr/0001-x.md"
k "$h" guard; [ "$rc" -eq 0 ]; check "guard: an ADR added in the change that names the file releases it" $?


finish
