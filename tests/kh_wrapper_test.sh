#!/usr/bin/env bash
# kh v0.5 M5: the wrapper (POSIX sh), reproducible dist and kh setup, end to end.
# Builds dist/ twice with `make -C cli/kh dist` and serves it as a mirror through KH_RELEASE_URL=file://...
# shellcheck disable=SC2319  # "check ... $?" after a test is this suite's idiom (see keel_helpers.sh)
set -uo pipefail
. "$(dirname "$0")/keel_helpers.sh"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v go >/dev/null 2>&1; then
  if [ -n "${CI:-}" ]; then fail "kh wrapper: go is required in CI"; finish; fi
  echo "  skip kh wrapper: go not installed"; exit 0
fi

W="$(mktemp -d)"; _keel_tmps="$_keel_tmps $W"
WRAPPER="$REPO_ROOT/cli/kh/wrapper/kh"
V1="0.5.0-wrapper.1"; V2="0.5.0-wrapper.2"

# the wrapper itself
dash -n "$WRAPPER" 2>/dev/null || sh -n "$WRAPPER"; check "wrapper: valid POSIX sh syntax" $?
if command -v dash >/dev/null 2>&1; then SH=dash; else SH=sh; echo "  note: dash not installed, the wrapper runs under sh"; fi
if command -v shellcheck >/dev/null 2>&1; then shellcheck -s sh "$WRAPPER"; check "wrapper: shellcheck (sh) clean" $?; fi
! grep -nE '\[\[ |\bfunction\b|\blocal\b|<\(|\$\(\(.*\)\)=|echo -e|\$'"'" "$WRAPPER" >/dev/null; check "wrapper: no bashisms ([[, function, local, <(, echo -e, \$'..')" $?

# reproducible dist: twice, identical SHA256SUMS
build_dist() { # build_dist VERSION DIR
  make -C "$REPO_ROOT/cli/kh" dist VERSION="$1" DIST="$2" >"$W/dist-$1.log" 2>&1
}
build_dist "$V1" "$W/d1"; check "dist: make dist builds the four platforms" $?
ls "$W/d1" | LC_ALL=C sort | tr '\n' ' ' | grep -q '^SHA256SUMS kh-darwin-amd64 kh-darwin-arm64 kh-linux-amd64 kh-linux-arm64 $'; check "dist: four binaries and SHA256SUMS" $?
build_dist "$V1" "$W/d1b"
cmp -s "$W/d1/SHA256SUMS" "$W/d1b/SHA256SUMS"; check "dist: make dist twice gives an identical SHA256SUMS (reproducible)" $?
build_dist "$V2" "$W/d2"; check "dist: a second version builds" $?
lock_of() { make -s -C "$REPO_ROOT/cli/kh" lock VERSION="$1" DIST="$2"; }
lockv="$(lock_of "$V1" "$W/d1")"; printf '%s\n' "$lockv" | grep -qx "version=$V1"; check "lock: make lock prints the version line" $?
[ "$(printf '%s\n' "$lockv" | grep -cE '^(linux|darwin)-(amd64|arm64)=[0-9a-f]{64}$')" -eq 4 ]; check "lock: four platform lines with 64 hex" $?

# newrepo VERSION DIST -> a git repository with the wrapper at .agents/bin/kh and the lock
newrepo() {
  local d; d="$(mktemp -d "$W/repo.XXXXXX")"
  (cd "$d" && git init -q . && git config user.email t@t && git config user.name t && mkdir -p .agents/bin .agents/githooks \
    && cp "$WRAPPER" .agents/bin/kh && lock_of "$1" "$2" > .agents/keel.lock \
    && printf '.agents/run/\n' > .gitignore)
  printf '%s\n' "$d"
}
write_keel() { # write_keel REPO
  cat > "$1/.agents/keel.yml" <<'YML'
version: 1
githooks: { mode: native, pre-commit: commit, pre-push: slow }
scripts:
  ok: "true"
gates:
  fast: { scripts: [guard, ok] }
  commit: { scripts: [guard, ok], changes: staged }
  slow: { scripts: [guard, ok], changes: branch }
YML
}
export XDG_CACHE_HOME="$W/cache"
export HOME="$W/home"; mkdir -p "$HOME"
MIRROR1="file://$W/d1"; MIRROR2="file://$W/d2"

# download + verify + exec
r1="$(newrepo "$V1" "$W/d1")"
out="$(cd "$r1" && KH_RELEASE_URL="$MIRROR1" $SH .agents/bin/kh version 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "kh $V1" ]; check "wrapper: first run downloads, verifies and execs (kh version prints the pinned version)" $?
[ -x "$XDG_CACHE_HOME/keel/$V1/kh" ]; check "wrapper: the binary is cached per version under XDG_CACHE_HOME" $?
out="$(cd "$r1" && KH_RELEASE_URL="file://$W/missing" $SH .agents/bin/kh version 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "kh $V1" ]; check "wrapper: a cached, verified binary needs no network" $?

# two repositories pinned to two versions, side by side
r2="$(newrepo "$V2" "$W/d2")"
out2="$(cd "$r2" && KH_RELEASE_URL="$MIRROR2" $SH .agents/bin/kh version 2>&1)"
out1="$(cd "$r1" && KH_RELEASE_URL="$MIRROR1" $SH .agents/bin/kh version 2>&1)"
[ "$out1" = "kh $V1" ] && [ "$out2" = "kh $V2" ] && [ -x "$XDG_CACHE_HOME/keel/$V2/kh" ]; check "wrapper: two repositories pinned to two versions run side by side" $?

# tampered cached binary refused
cp "$XDG_CACHE_HOME/keel/$V1/kh" "$W/kh.orig"
printf 'tampered' >> "$XDG_CACHE_HOME/keel/$V1/kh"
out="$(cd "$r1" && KH_RELEASE_URL="$MIRROR1" $SH .agents/bin/kh version 2>&1)"; rc=$?
[ "$rc" -eq 3 ] && printf '%s' "$out" | grep -q 'checksum mismatch for'; check "wrapper: a tampered cached binary is refused (exit 3)" $?
cp "$W/kh.orig" "$XDG_CACHE_HOME/keel/$V1/kh"

# KH_BINARY verified like a download
out="$(cd "$r1" && KH_BINARY=/bin/true $SH .agents/bin/kh version 2>&1)"; rc=$?
[ "$rc" -eq 3 ] && printf '%s' "$out" | grep -q 'checksum mismatch for /bin/true'; check "wrapper: KH_BINARY with a wrong hash is refused" $?
out="$(cd "$r1" && KH_BINARY="$W/d1/kh-linux-amd64" $SH .agents/bin/kh version 2>&1)"; rc=$?
if [ "$(uname -s)" = Linux ] && [ "$(uname -m)" = x86_64 ]; then
  [ "$rc" -eq 0 ] && [ "$out" = "kh $V1" ]; check "wrapper: KH_BINARY with the right hash runs" $?
fi

# a wrong download is refused and leaves no binary behind
r3="$(newrepo "$V1" "$W/d1")"
mkdir -p "$W/evil"; cp "$W/d1/"kh-* "$W/evil/"; printf 'x' >> "$W/evil/kh-linux-amd64"; printf 'x' >> "$W/evil/kh-linux-arm64"; printf 'x' >> "$W/evil/kh-darwin-amd64"; printf 'x' >> "$W/evil/kh-darwin-arm64"
rm -rf "$XDG_CACHE_HOME/keel/$V1"
out="$(cd "$r3" && KH_RELEASE_URL="file://$W/evil" $SH .agents/bin/kh version 2>&1)"; rc=$?
[ "$rc" -eq 3 ] && printf '%s' "$out" | grep -q 'checksum mismatch'; check "wrapper: a downloaded binary that fails verification is refused" $?
[ ! -e "$XDG_CACHE_HOME/keel/$V1/kh" ] && [ -z "$(ls "$XDG_CACHE_HOME/keel/$V1" 2>/dev/null)" ]; check "wrapper: a refused download leaves nothing in the cache" $?
out="$(cd "$r3" && KH_RELEASE_URL="file://$W/missing" $SH .agents/bin/kh version 2>&1)"; rc=$?
[ "$rc" -eq 3 ] && printf '%s' "$out" | grep -q 'cannot download'; check "wrapper: an unreachable release host is a clear error" $?

# hook mode: no verified binary -> the wrapper answers, downloads nothing, in under a second
r4="$(newrepo "$V1" "$W/d1")"
export XDG_CACHE_HOME="$W/emptycache"
now_ms() { python3 -I -c 'import time; print(int(time.time()*1000))'; }
PAYLOAD='{"hook_event_name":"PreToolUse","tool_name":"Write","cwd":"/x","permission_mode":"default","tool_input":{"file_path":"/x/AGENTS.md"}}'
t0="$(now_ms)"
out="$(cd "$r4" && printf '%s' "$PAYLOAD" | KH_RELEASE_URL="file://$W/missing" $SH .agents/bin/kh hook pre-tool-use 2>&1)"; rc=$?
t1="$(now_ms)"
[ "$rc" -eq 0 ] && printf '%s' "$out" | python3 -I -c 'import json,sys; d=json.load(sys.stdin); assert d["permissionDecision"]=="ask" and d["hookSpecificOutput"]["permissionDecision"]=="ask" and d["hookSpecificOutput"]["hookEventName"]=="PreToolUse" and "kh unavailable" in d["permissionDecisionReason"]'; check "wrapper hook mode: no binary -> ask in both shapes" $?
[ $((t1 - t0)) -lt 1000 ]; check "wrapper hook mode: answers in under 1 s ($((t1 - t0)) ms)" $?
[ ! -e "$W/emptycache" ]; check "wrapper hook mode: no download, no cache directory created" $?
out="$(cd "$r4" && printf '%s' "${PAYLOAD/default/bypassPermissions}" | $SH .agents/bin/kh hook pre-tool-use 2>&1)"
printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; check "wrapper hook mode: bypassPermissions -> deny" $?
out="$(cd "$r4" && printf '%s' '{"permission_mode" : "dontAsk","tool_name":"Bash"}' | $SH .agents/bin/kh hook pre-tool-use 2>&1)"
printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; check "wrapper hook mode: dontAsk with spaces around the colon -> deny" $?
out="$(cd "$r4" && printf '{}' | $SH .agents/bin/kh hook stop 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | python3 -I -c 'import json,sys; d=json.load(sys.stdin); assert "decision" not in d and "the gates did not run" in d["systemMessage"]'; check "wrapper hook mode: stop -> a non-blocking systemMessage" $?
out="$(cd "$r4" && $SH .agents/bin/kh hook commit-msg MSG 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'kh unavailable'; check "wrapper hook mode: commit-msg -> exit 0 with a notice" $?
rm -f "$r4/.agents/keel.lock"
out="$(cd "$r4" && printf '%s' "$PAYLOAD" | $SH .agents/bin/kh hook pre-tool-use 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '"permissionDecision":"ask"'; check "wrapper hook mode: a missing keel.lock still answers" $?
out="$(cd "$r4" && $SH .agents/bin/kh version 2>&1)"; rc=$?
[ "$rc" -eq 3 ] && printf '%s' "$out" | grep -q 'no keel.lock'; check "wrapper: a missing keel.lock is an error outside hook mode" $?
export XDG_CACHE_HOME="$W/cache"

# the verified binary runs hooks for real in hook mode
r5="$(newrepo "$V1" "$W/d1")"; write_keel "$r5"
(cd "$r5" && git add -A && git commit -q -m seed)
(cd "$r5" && KH_RELEASE_URL="$MIRROR1" $SH .agents/bin/kh version >/dev/null 2>&1)
phys="$(cd "$r5" && pwd -P)"
out="$(cd "$r5" && printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Write","cwd":"'"$phys"'","permission_mode":"default","tool_input":{"file_path":"'"$phys"'/.agents/keel.yml"}}' | KH_RELEASE_URL="$MIRROR1" $SH .agents/bin/kh hook pre-tool-use 2>&1)"
printf '%s' "$out" | grep -q '"permissionDecision":"ask"' && ! printf '%s' "$out" | grep -q unavailable; check "wrapper hook mode: with a verified binary the real hook answers" $?

# pin mismatch between the lock and the binary named by KH_BINARY: the binary's own pin check
cp "$W/d1/SHA256SUMS" "$W/sums.orig"
if [ "$(uname -s)" = Linux ] && [ "$(uname -m)" = x86_64 ]; then
  r6="$(newrepo "$V1" "$W/d1")"; write_keel "$r6"
  # a lock that pins V2 but is satisfied by the V1 binary's hash is impossible; check the kh-level message instead
  sed -i "s/^version=.*/version=$V2/" "$r6/.agents/keel.lock"
  sed -i "s/^linux-amd64=.*/linux-amd64=$(sha256sum "$W/d1/kh-linux-amd64" | cut -d' ' -f1)/" "$r6/.agents/keel.lock"
  out="$(cd "$r6" && KH_BINARY="$W/d1/kh-linux-amd64" $SH .agents/bin/kh gate fast 2>&1)"; rc=$?
  [ "$rc" -eq 3 ] && printf '%s' "$out" | grep -q "pin mismatch: keel.lock pins $V2, this kh is $V1"; check "kh: a binary that does not match the pinned version refuses to run a gate" $?
fi

# kh setup in a fresh clone: core.hooksPath and the exec bits
src="$(newrepo "$V1" "$W/d1")"; write_keel "$src"
printf '#!/bin/sh\nexec sh "$(git rev-parse --show-toplevel)/.agents/bin/kh" gate commit\n' > "$src/.agents/githooks/pre-commit"
printf '#!/bin/sh\nexec sh "$(git rev-parse --show-toplevel)/.agents/bin/kh" gate slow\n' > "$src/.agents/githooks/pre-push"
printf '#!/bin/sh\nexec sh "$(git rev-parse --show-toplevel)/.agents/bin/kh" hook commit-msg "$1"\n' > "$src/.agents/githooks/commit-msg"
chmod 644 "$src/.agents/githooks/"*
(cd "$src" && git add -A && git commit -q -m seed)
git clone -q "$src" "$W/clone"
[ -z "$(git -C "$W/clone" config --get core.hooksPath)" ]; check "kh setup: a fresh clone has no hooksPath yet" $?
out="$(cd "$W/clone" && KH_RELEASE_URL="$MIRROR1" $SH .agents/bin/kh setup 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(git -C "$W/clone" config --get core.hooksPath)" = ".agents/githooks" ]; check "kh setup: sets core.hooksPath to .agents/githooks" $?
[ -x "$W/clone/.agents/githooks/pre-commit" ] && [ -x "$W/clone/.agents/githooks/pre-push" ] && [ -x "$W/clone/.agents/githooks/commit-msg" ]; check "kh setup: makes the hook files executable" $?
printf '%s' "$out" | grep -q 'git hooks: core.hooksPath = .agents/githooks'; check "kh setup: says what it did" $?
printf '%s' "$out" | grep -q '^warn '; check "kh setup: runs kh check and prints its warnings" $?
# the activated pre-commit hook runs the commit gate for real
(cd "$W/clone" && git config user.email t@t && git config user.name t && echo change > file.txt && git add file.txt && KH_RELEASE_URL="$MIRROR1" git commit -q -m x >"$W/commit.out" 2>&1); rc=$?
[ "$rc" -eq 0 ]; check "git hooks: the commit gate (pre-commit) runs and passes on a clean change" $?

finish
