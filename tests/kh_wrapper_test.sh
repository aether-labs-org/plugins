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
out="$(cd "$r1" && printf '{}' | KH_RELEASE_URL="$MIRROR1" $SH .agents/bin/kh hook pre-tool-use 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '"permissionDecision":"ask"' && printf '%s' "$out" | grep -q 'checksum mismatch for' && printf '%s' "$out" | grep -q 'delete it'; check "wrapper hook mode: a tampered cached binary is named and the advice is to delete it (setup alone would refuse it too)" $?
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
printf '%s' "$out" | grep -q 'no keel.lock' && ! printf '%s' "$out" | grep -q 'kh setup'; check "wrapper hook mode: a missing keel.lock says so and does not advise kh setup (setup cannot fix it)" $?
out="$(cd "$r4" && $SH .agents/bin/kh version 2>&1)"; rc=$?
[ "$rc" -eq 3 ] && printf '%s' "$out" | grep -q 'no keel.lock'; check "wrapper: a missing keel.lock is an error outside hook mode" $?
export XDG_CACHE_HOME="$W/cache"


# the plugin's own wrapper (not .agents/bin/kh): the fail-safe names the wrapper's path, not a repository command
pl="$W/plug dir"; mkdir -p "$pl/kh/bin"; cp "$WRAPPER" "$pl/kh/bin/kh"; lock_of "$V1" "$W/d1" > "$pl/kh/keel.lock"
export XDG_CACHE_HOME="$W/emptycache2"
out="$(cd "$W" && printf '%s' "$PAYLOAD" | KH_RELEASE_URL="file://$W/missing" $SH "$pl/kh/bin/kh" hook pre-tool-use 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | PL="$pl/kh/bin/kh" python3 -I -c 'import json,os,sys; d=json.load(sys.stdin); assert d["permissionDecisionReason"] == "kh unavailable: run sh " + os.environ["PL"] + " version", d["permissionDecisionReason"]; assert d["hookSpecificOutput"]["permissionDecisionReason"] == d["permissionDecisionReason"]'; check "plugin wrapper, hook mode: the ask names the wrapper's own path (a path with a space stays valid JSON)" $?
printf '%s' "$out" | grep -q '.agents/bin/kh setup'; [ $? -ne 0 ]; check "plugin wrapper, hook mode: no .agents/bin/kh setup advice where .agents/bin does not exist" $?
out="$(cd "$W" && printf '{}' | $SH "$pl/kh/bin/kh" hook stop 2>&1)"
printf '%s' "$out" | PL="$pl/kh/bin/kh" python3 -I -c 'import json,os,sys; d=json.load(sys.stdin); assert os.environ["PL"] + " version" in d["systemMessage"] and "decision" not in d'; check "plugin wrapper, hook mode: stop names the wrapper's path too" $?
out="$(cd "$W" && PL="$pl/kh/bin/kh" $SH "$pl/kh/bin/kh" hook commit-msg MSG 2>&1)"
printf '%s' "$out" | grep -qF "kh unavailable: run sh $pl/kh/bin/kh version"; check "plugin wrapper, hook mode: commit-msg notice names the wrapper's path" $?
out="$(cd "$W" && KH_RELEASE_URL="$MIRROR1" $SH "$pl/kh/bin/kh" version 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "kh $V1" ]; check "plugin wrapper: 'version' downloads and verifies the pinned kh (the first action of the skill)" $?
out="$(cd "$W" && printf '%s' "$PAYLOAD" | KH_RELEASE_URL="file://$W/missing" $SH "$pl/kh/bin/kh" hook pre-tool-use 2>&1)"
printf '%s' "$out" | grep -qF "$pl/kh/bin/kh version"; [ $? -ne 0 ]; check "plugin wrapper: once kh is cached the real hook answers, not the wrapper's fail-safe" $?
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

# the very first commit of a repository with no commit yet passes the commit gate (guard has no base: nothing to loosen)
r7="$(newrepo "$V1" "$W/d1")"; write_keel "$r7"
mkdir -p "$r7/.agents/githooks"
printf '#!/bin/sh\nexec sh "$(git rev-parse --show-toplevel)/.agents/bin/kh" gate commit\n' > "$r7/.agents/githooks/pre-commit"
printf '#!/bin/sh\nexec sh "$(git rev-parse --show-toplevel)/.agents/bin/kh" gate slow\n' > "$r7/.agents/githooks/pre-push"
chmod 644 "$r7/.agents/githooks/"*
out="$(cd "$r7" && KH_RELEASE_URL="$MIRROR1" $SH .agents/bin/kh setup 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ -z "$(git -C "$r7" rev-parse -q --verify HEAD 2>/dev/null)" ]; check "first commit: kh setup in a repository with no commit" $?
out="$(cd "$r7" && KH_RELEASE_URL="$MIRROR1" $SH .agents/bin/kh gate commit 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'gate: commit - PASSED'; check "first commit: the commit gate passes with no base commit (guard passes)" $?
(cd "$r7" && git add -A && KH_RELEASE_URL="$MIRROR1" git commit -q -m "first" >"$W/first.out" 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ -n "$(git -C "$r7" rev-parse -q --verify HEAD)" ]; check "first commit: the pre-commit hook lets the very first commit through" $?
[ "$rc" -eq 0 ] || cat "$W/first.out"

# ---- round 3: the root of a command does not follow the working directory ----
# 1. the wrapper exports KH_ROOT (repository mode), overrides an inherited one, unsets it (plugin mode)
STUB="$W/stub-kh"; printf '#!/bin/sh\nprintf "KH_ROOT=%%s\\n" "${KH_ROOT-unset}"\n' > "$STUB"; chmod +x "$STUB"
stubsum="$(sha256sum "$STUB" | cut -d' ' -f1)"
stub_lock() { printf 'version=0.0.0-stub\nlinux-amd64=%s\nlinux-arm64=%s\ndarwin-amd64=%s\ndarwin-arm64=%s\n' "$stubsum" "$stubsum" "$stubsum" "$stubsum" > "$1"; }
sr="$W/stubrepo"; mkdir -p "$sr/.agents/bin" "$sr/sub/deep"; cp "$WRAPPER" "$sr/.agents/bin/kh"; stub_lock "$sr/.agents/keel.lock"
out="$(cd "$sr/sub/deep" && env -u KH_ROOT KH_BINARY="$STUB" $SH ../../.agents/bin/kh run x 2>&1)"
[ "$out" = "KH_ROOT=$sr" ]; check "wrapper (repository mode): exports KH_ROOT as the directory two levels above itself" $?
out="$(cd "$sr" && KH_ROOT=/somewhere/else KH_BINARY="$STUB" $SH .agents/bin/kh run x 2>&1)"
[ "$out" = "KH_ROOT=$sr" ]; check "wrapper (repository mode): overrides an inherited KH_ROOT" $?
out="$(cd "$sr" && KH_ROOT=/somewhere/else KH_BINARY="$STUB" sh "$sr/.agents/bin/kh" run x 2>&1)"
[ "$out" = "KH_ROOT=$sr" ]; check "wrapper (repository mode): absolute path of the wrapper" $?
spl="$W/stub plug"; mkdir -p "$spl/kh/bin"; cp "$WRAPPER" "$spl/kh/bin/kh"; stub_lock "$spl/kh/keel.lock"
out="$(cd "$W" && KH_ROOT=/somewhere/else KH_BINARY="$STUB" $SH "$spl/kh/bin/kh" run x 2>&1)"
[ "$out" = "KH_ROOT=unset" ]; check "wrapper (plugin mode): unsets an inherited KH_ROOT" $?

# 2. a project P with a harness, a nested repository N, and a real git worktree of P under P/.claude/worktrees/w
mk_world() { # mk_world NAME -> P with the wrapper, keel.yml, nested repo n/ (ignored) and a worktree
  local p="$W/$1"; mkdir -p "$p"
  (cd "$p" && git init -q . && git config user.email t@t && git config user.name t && mkdir -p .agents/bin \
    && cp "$WRAPPER" .agents/bin/kh && lock_of "$V1" "$W/d1" > .agents/keel.lock \
    && printf '.agents/run/\nn/\n.claude/worktrees/\n' > .gitignore)
  write_keel "$p"
  printf '# a\n' > "$p/AGENTS.md"
  (cd "$p" && git add -A && git commit -q -m seed && mkdir -p n && git -C n init -q . && git worktree add -q .claude/worktrees/w -b wt)
  printf '%s\n' "$(cd "$p" && pwd -P)"
}
P="$(mk_world world)"; N="$P/n"; WT="$P/.claude/worktrees/w"
OUTSIDE="$W/outside"; mkdir -p "$OUTSIDE"
(cd "$P" && KH_RELEASE_URL="$MIRROR1" $SH .agents/bin/kh version >/dev/null 2>&1)
payload() { # payload TOOL CWD KEY VALUE [MODE] (stderr dropped: the reader may not read it)
  python3 -I -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","tool_name":sys.argv[1],"cwd":sys.argv[2],"permission_mode":sys.argv[5] if len(sys.argv)>5 else "default","tool_input":{sys.argv[3]:sys.argv[4]}}))' "$@" 2>/dev/null
}
verdict() { # verdict JSON-OUTPUT -> ask|deny|allow
  if [ -z "$1" ]; then echo allow; else printf '%s' "$1" | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["permissionDecision"])'; fi
}
PLUGIN="$W/plugin-world/kh/bin/kh"; mkdir -p "$W/plugin-world/kh/bin"; cp "$WRAPPER" "$PLUGIN"; lock_of "$V1" "$W/d1" > "$W/plugin-world/kh/keel.lock"
for cwd in "$N" "$WT" "$OUTSIDE"; do
  label="$(basename "$cwd")"
  # setup mode, through the plugin's wrapper
  got="$(verdict "$(cd "$cwd" && payload Write "$cwd" file_path "$P/AGENTS.md" > "$W/pl.json" && KH_RELEASE_URL="$MIRROR1" $SH "$PLUGIN" hook pre-tool-use --setup < "$W/pl.json" 2>&1)")"
  [ "$got" = ask ]; check "cwd $label, setup mode: Write P/AGENTS.md asks ($got)" $?
  got="$(verdict "$(cd "$cwd" && payload Write "$cwd" file_path "$cwd/x" > "$W/pl.json" && KH_RELEASE_URL="$MIRROR1" $SH "$PLUGIN" hook pre-tool-use --setup < "$W/pl.json" 2>&1)")"
  [ "$got" = allow ]; check "cwd $label, setup mode: Write <cwd>/x is allowed ($got)" $?
  got="$(verdict "$(cd "$cwd" && payload Bash "$cwd" command "echo x > $P/AGENTS.md" > "$W/pl.json" && KH_RELEASE_URL="$MIRROR1" $SH "$PLUGIN" hook pre-tool-use --setup < "$W/pl.json" 2>&1)")"
  [ "$got" = deny ]; check "cwd $label, setup mode: Bash echo x > P/AGENTS.md is denied ($got)" $?
  # project mode, through the project's wrapper (found with CLAUDE_PROJECT_DIR)
  got="$(verdict "$(cd "$cwd" && payload Write "$cwd" file_path "$P/.agents/keel.yml" > "$W/pl.json" && KH_RELEASE_URL="$MIRROR1" $SH "$P/.agents/bin/kh" hook pre-tool-use < "$W/pl.json" 2>&1)")"
  [ "$got" = ask ]; check "cwd $label, project mode: Write P/.agents/keel.yml asks ($got)" $?
  got="$(verdict "$(cd "$cwd" && payload Write "$cwd" file_path "$cwd/x" > "$W/pl.json" && KH_RELEASE_URL="$MIRROR1" $SH "$P/.agents/bin/kh" hook pre-tool-use < "$W/pl.json" 2>&1)")"
  [ "$got" = allow ]; check "cwd $label, project mode: Write <cwd>/x is allowed ($got)" $?
  got="$(verdict "$(cd "$cwd" && payload Bash "$cwd" command "echo x > $P/.agents/keel.yml" > "$W/pl.json" && KH_RELEASE_URL="$MIRROR1" $SH "$P/.agents/bin/kh" hook pre-tool-use < "$W/pl.json" 2>&1)")"
  [ "$got" = deny ]; check "cwd $label, project mode: Bash echo x > P/.agents/keel.yml is denied ($got)" $?
done
got="$(verdict "$(cd "$N" && payload Bash "$N" command "echo x > ../.agents/keel.yml" > "$W/pl.json" && KH_RELEASE_URL="$MIRROR1" $SH "$P/.agents/bin/kh" hook pre-tool-use < "$W/pl.json" 2>&1)")"
[ "$got" = deny ]; check "cwd N, project mode: Bash echo x > ../.agents/keel.yml is denied ($got)" $?

# 3. the commands of the settings.json template, run with sh -c from a nested repository
SETTINGS="$REPO_ROOT/plugins/keel-harness/skills/harness/templates/settings.json"
cmd_of() { python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["hooks"][sys.argv[2]][0]["hooks"][0]["command"])' "$SETTINGS" "$1"; }
PRE="$(cmd_of PreToolUse)"; STOP="$(cmd_of Stop)"
[ "$(printf '%s\n' "$PRE" | wc -l)" -eq 1 ] && [ "$(printf '%s\n' "$STOP" | wc -l)" -eq 1 ]; check "settings.json: each hook command is one line" $?
out="$(cd "$N" && payload Write "$N" file_path "$P/.agents/keel.yml" > "$W/pl.json" && env CLAUDE_PROJECT_DIR="$P" KH_RELEASE_URL="$MIRROR1" sh -c "$PRE" < "$W/pl.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(verdict "$out")" = ask ] && ! printf '%s' "$out" | grep -q "was not found"; check "settings.json PreToolUse, cwd N, CLAUDE_PROJECT_DIR=P: reaches P's wrapper, which asks" $?
out="$(cd "$N" && payload Write "$N" file_path "$P/.agents/keel.yml" > "$W/pl.json" && env -u CLAUDE_PROJECT_DIR sh -c "$PRE" < "$W/pl.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(verdict "$out")" = ask ] && printf '%s' "$out" | python3 -I -c 'import json,sys; d=json.load(sys.stdin); assert d["hookSpecificOutput"]["permissionDecision"]=="ask" and d["hookSpecificOutput"]["hookEventName"]=="PreToolUse" and d["permissionDecisionReason"]==d["hookSpecificOutput"]["permissionDecisionReason"] and "was not found" in d["permissionDecisionReason"]'; check "settings.json PreToolUse, cwd N, no CLAUDE_PROJECT_DIR, no wrapper: dual-shape ask, exit 0 (never 2)" $?
out="$(cd "$OUTSIDE" && payload Write "$OUTSIDE" file_path "$OUTSIDE/x" > "$W/pl.json" && env -u CLAUDE_PROJECT_DIR sh -c "$PRE" < "$W/pl.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(verdict "$out")" = ask ]; check "settings.json PreToolUse, cwd outside any repository: ask, exit 0" $?
out="$(cd "$N" && printf '{}' > "$W/pl.json" && env -u CLAUDE_PROJECT_DIR sh -c "$STOP" < "$W/pl.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | python3 -I -c 'import json,sys; d=json.load(sys.stdin); assert "decision" not in d and "kh unavailable" in d["systemMessage"]'; check "settings.json Stop, no wrapper: a systemMessage, exit 0 (never 2)" $?
printf '%s' "$PRE" | grep -q 'CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel'; check "settings.json: the wrapper is located with CLAUDE_PROJECT_DIR, falling back to git" $?

# Stop from a nested repository runs the project's gate through the chain settings command -> wrapper -> KH_ROOT -> kh
F="$(mk_world failing)"; FN="$F/n"
cat > "$F/.agents/keel.yml" <<'YML'
version: 1
scripts:
  broken: "false"
gates:
  fast: { scripts: [guard, broken] }
  commit: { scripts: [guard, broken], changes: staged }
  slow: { scripts: [guard, broken], changes: branch }
YML
out="$(cd "$FN" && printf '{"hook_event_name":"Stop","cwd":"%s"}' "$FN" > "$W/pl.json" && env CLAUDE_PROJECT_DIR="$F" KH_RELEASE_URL="$MIRROR1" sh -c "$STOP" < "$W/pl.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '"decision":"block"'; check "settings.json Stop, cwd nested repository: runs the project's fast gate, a failure blocks" $?

# the dogfood case: a worktree of the project, which has no wrapper of its own
D="$(mk_world dogfood)"; DW="$D/.claude/worktrees/w"
git -C "$DW" rm -q --cached -r .agents/bin 2>/dev/null; rm -rf "$DW/.agents/bin"
[ ! -e "$DW/.agents/bin/kh" ]; check "dogfood: the worktree has no wrapper" $?
out="$(cd "$DW" && payload Bash "$DW" command "ls" > "$W/pl.json" && env -u CLAUDE_PROJECT_DIR sh -c "$PRE" < "$W/pl.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(verdict "$out")" = ask ]; check "dogfood: PreToolUse in the wrapper-less worktree asks and exits 0 (it used to exit 2 and block every call)" $?
out="$(cd "$DW" && payload Write "$DW" file_path "$D/.agents/keel.yml" > "$W/pl.json" && env CLAUDE_PROJECT_DIR="$D" KH_RELEASE_URL="$MIRROR1" sh -c "$PRE" < "$W/pl.json" 2>&1)"
[ "$(verdict "$out")" = ask ] && ! printf '%s' "$out" | grep -q 'not found'; check "dogfood: with CLAUDE_PROJECT_DIR the project's wrapper answers" $?

# ---- round 3 correction 2: KH_ROOT is the wrapper's hand-off to kh, not something scripts inherit ----
# (a kh binary started by a script, e.g. a test suite that builds kh, would work on the outer repository)
LK="$(newrepo "$V1" "$W/d1")"
cat > "$LK/.agents/keel.yml" <<'YML'
version: 1
scripts:
  showroot: "sh .agents/showroot.sh"
gates:
  fast: { scripts: [guard, showroot] }
  commit: { scripts: [guard, showroot], changes: staged }
  slow: { scripts: [guard, showroot], changes: branch }
YML
printf 'printf "%%s" "${KH_ROOT-unset}" > root.seen\n' > "$LK/.agents/showroot.sh"
(cd "$LK" && git add -A && git commit -q -m seed)
out="$(cd "$LK" && KH_ROOT=/somewhere/else KH_RELEASE_URL="$MIRROR1" $SH .agents/bin/kh run showroot 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(cat "$LK/root.seen" 2>/dev/null)" = unset ]; check "kh run <script>: the script sees no KH_ROOT" $?
rm -f "$LK/root.seen"
out="$(cd "$LK" && KH_RELEASE_URL="$MIRROR1" $SH .agents/bin/kh run -- sh -c 'printf "%s" "${KH_ROOT-unset}" > root.seen' 2>&1)"
[ "$(cat "$LK/root.seen" 2>/dev/null)" = unset ]; check "kh run -- <command>: the command sees no KH_ROOT" $?
rm -f "$LK/root.seen"
out="$(cd "$LK" && KH_RELEASE_URL="$MIRROR1" $SH .agents/bin/kh gate fast 2>&1)"
[ "$(cat "$LK/root.seen" 2>/dev/null)" = unset ]; check "kh gate: the scripts see no KH_ROOT" $?

# ---- round 3 correction 3: git exports GIT_DIR, GIT_INDEX_FILE ... to hooks; a gated script that runs git elsewhere must not act on the repository ----
# Everything below happens in throwaway repositories under $W: real hooks (pre-commit, commit-msg, pre-push) activated by kh setup.
GH="$REPO_ROOT/plugins/keel-harness/skills/harness/templates/githooks"
HR="$(newrepo "$V1" "$W/d1")"
cat > "$HR/.agents/keel.yml" <<'YML'
version: 1
githooks: { mode: native, pre-commit: commit, pre-push: slow, commit-msg: cm }
scripts:
  leak: "sh .agents/leak.sh"
  cm: { builtin: commit-message, with: { pattern: '^.+' } }
gates:
  fast: { scripts: [guard, leak] }
  commit: { scripts: [guard, leak], changes: staged }
  slow: { scripts: [guard, leak], changes: branch }
YML
cat > "$HR/.agents/leak.sh" <<'SH'
# what a test suite does: git in a fresh temporary directory
echo ran >> "$LEAK_MARK"
d="$(mktemp -d)"
cd "$d" || exit 0
git init -q
git config user.name ana
git config user.email ana@example.com
git commit --allow-empty -qm x
git branch leaked
exit 0
SH
cp "$GH/pre-commit" "$GH/commit-msg" "$GH/pre-push" "$HR/.agents/githooks/"
(cd "$HR" && git add -A && git commit -q -m "seed" && git branch -M main)
git init -q --bare "$W/hooks-remote.git"
(cd "$HR" && git remote add origin "$W/hooks-remote.git")
export LEAK_MARK="$W/leak.marks"; : > "$LEAK_MARK"
(cd "$HR" && KH_RELEASE_URL="$MIRROR1" $SH .agents/bin/kh setup >/dev/null 2>&1)
[ "$(git -C "$HR" config --get core.hooksPath)" = ".agents/githooks" ]; check "git hooks (R): kh setup activated the hooks in the throwaway repository" $?
marks() { wc -l < "$LEAK_MARK" | tr -d ' '; }
# clean_repo REPO LABEL EXPECTED-BRANCHES: nothing a hook-run script did in a temporary directory reached REPO
clean_repo() {
  local r="$1" label="$2" want="$3" got
  [ "$(git -C "$r" config --local --get user.name)" = t ]; check "$label: .git/config still has user.name=t (not ana)" $?
  [ "$(git -C "$r" config --local --get core.bare)" = false ]; check "$label: core.bare is false" $?
  got="$(git -C "$r" for-each-ref --format='%(refname:short)' refs/heads | sort | tr '\n' ' ')"
  [ "$got" = "$want" ]; check "$label: branches are exactly '$want' (got '$got'; none named leaked)" $?
}
wt_before="$(git -C "$HR" worktree list | sed 's/ [0-9a-f]\{7,\} / /')"
n0="$(git -C "$HR" rev-list --count HEAD)"
(cd "$HR" && echo one > f1.txt && git add f1.txt && KH_RELEASE_URL="$MIRROR1" git commit -q -m "feat: one" >"$W/hooks-commit.out" 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ "$(marks)" -ge 1 ]; check "git hooks (R): a real git commit ran pre-commit and the gated script" $?
[ "$rc" -eq 0 ] || cat "$W/hooks-commit.out"
[ "$(git -C "$HR" rev-list --count HEAD)" -eq $((n0 + 1))  ] && [ "$(git -C "$HR" log -1 --format=%s)" = "feat: one" ]; check "git hooks (R): HEAD moved by the intended commit only" $?
m1="$(marks)"
(cd "$HR" && KH_RELEASE_URL="$MIRROR1" git push -q origin HEAD:refs/heads/main >"$W/hooks-push.out" 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ "$(marks)" -gt "$m1" ]; check "git hooks (R): a real git push to a local bare remote ran pre-push and the gated script" $?
[ "$rc" -eq 0 ] || cat "$W/hooks-push.out"
clean_repo "$HR" "git hooks (R)" "main "
[ "$(git -C "$HR" worktree list | sed 's/ [0-9a-f]\{7,\} / /')" = "$wt_before" ]; check "git hooks (R): git worktree list is unchanged" $?

# from a linked worktree: git exports GIT_DIR=<R>/.git/worktrees/<name> (the shape of the incident)
git -C "$HR" worktree add -q "$W/hooks-wt" -b wtbranch
wt_before="$(git -C "$HR" worktree list | sed 's/ [0-9a-f]\{7,\} / /')"
main_before="$(git -C "$HR" rev-parse main)"
nw="$(git -C "$W/hooks-wt" rev-list --count HEAD)"; m1="$(marks)"
(cd "$W/hooks-wt" && echo two > f2.txt && git add f2.txt && KH_RELEASE_URL="$MIRROR1" git commit -q -m "feat: two" >"$W/hooks-commit2.out" 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ "$(marks)" -gt "$m1" ]; check "git hooks (linked worktree): a real git commit ran the hooks and the gated script" $?
[ "$rc" -eq 0 ] || cat "$W/hooks-commit2.out"
[ "$(git -C "$W/hooks-wt" rev-list --count HEAD)" -eq $((nw + 1)) ] && [ "$(git -C "$HR" rev-parse main)" = "$main_before" ]; check "git hooks (linked worktree): the worktree's branch moved by the intended commit only, main did not move" $?
m1="$(marks)"
(cd "$W/hooks-wt" && KH_RELEASE_URL="$MIRROR1" git push -q origin HEAD:refs/heads/wtbranch >"$W/hooks-push2.out" 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ "$(marks)" -gt "$m1" ]; check "git hooks (linked worktree): a real git push ran pre-push and the gated script" $?
[ "$rc" -eq 0 ] || cat "$W/hooks-push2.out"
clean_repo "$HR" "git hooks (linked worktree)" "main wtbranch "
[ "$(git -C "$W/hooks-wt" symbolic-ref --short HEAD)" = wtbranch ] && [ "$(git -C "$HR" symbolic-ref --short HEAD)" = main ]; check "git hooks (linked worktree): both worktrees are still on their own branch" $?
[ "$(git -C "$HR" worktree list | sed 's/ [0-9a-f]\{7,\} / /')" = "$wt_before" ]; check "git hooks (linked worktree): git worktree list is unchanged" $?
unset LEAK_MARK

finish
