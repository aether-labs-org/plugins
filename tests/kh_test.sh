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
k "$r" version; [ "$rc" -eq 0 ] && [ "$out" = "kh 0.4.0-dev" ]; check "kh version prints kh 0.4.0-dev" $?
k "$r"; [ "$rc" -eq 64 ]; check "kh with no arguments exits 64" $?
k "$r" run true; [ "$rc" -eq 64 ]; check "usage: kh run without -- exits 64" $?
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
[ "$rc" -eq 2 ] && has "$out" "SKIP" && has "$out" "not found - run: make bootstrap"; check "not found: rc 2, SKIP, bootstrap hint" $?

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
n="$(mktemp -d "$W/plain.XXXXXX")"
k "$n" run -- true; [ "$rc" -eq 3 ] && has "$out" "no .agents/keel.yml"; check "no keel.yml: run exits 3" $?
k "$n" show 20000101-000000-dead; [ "$rc" -eq 3 ] && has "$out" "no .agents/keel.yml"; check "no keel.yml: show exits 3" $?

finish
