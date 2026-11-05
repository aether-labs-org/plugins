#!/usr/bin/env bash
# Round 3 correction 3: the test suites must be safe when they are started from a git hook, i.e. with GIT_DIR,
# GIT_WORK_TREE, GIT_INDEX_FILE ... exported. Everything here runs against a throwaway repository under a
# temporary directory; nothing touches the repository that holds these tests.
# shellcheck disable=SC2319  # "check ... $?" after a test is this suite's idiom (see keel_helpers.sh)
set -uo pipefail
. "$(dirname "$0")/keel_helpers.sh"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
W="$(mktemp -d)"; _keel_tmps="$_keel_tmps $W"

# a throwaway repository with a commit, a branch and a linked worktree: what a leaked git command would change
TR="$W/throwaway"; mkdir -p "$TR"
git -C "$TR" init -q . && git -C "$TR" config user.name original && git -C "$TR" config user.email o@o \
  && git -C "$TR" commit -q --allow-empty -m init && git -C "$TR" worktree add -q "$W/throwaway-wt" -b side
snapshot() { { cat "$TR/.git/config"; git -C "$TR" for-each-ref; git -C "$TR" worktree list; git -C "$TR" rev-parse HEAD; git -C "$TR" status --porcelain=v1; } 2>&1; }
before="$(snapshot)"
[ "$(git -C "$TR" config --get core.bare)" = false ]; check "throwaway repository: core.bare is false before" $?

# the run.sh of the suite clears the variables before running any suite (copy it next to a fake suite so that it does not recurse)
mkdir -p "$W/runsh"; cp "$REPO_ROOT/tests/run.sh" "$W/runsh/run.sh"
printf '#!/usr/bin/env bash\nprintf "%%s|%%s|%%s|%%s\\n" "${GIT_DIR-unset}" "${GIT_INDEX_FILE-unset}" "${GIT_WORK_TREE-unset}" "${GIT_EDITOR-unset}"\n' > "$W/runsh/fake_test.sh"
got="$(GIT_DIR="$TR/.git" GIT_INDEX_FILE="$TR/.git/index" GIT_WORK_TREE="$TR" GIT_EDITOR=true bash "$W/runsh/run.sh" 2>&1 | grep -v '^==')"
[ "$got" = "unset|unset|unset|true" ]; check "tests/run.sh clears the repository-local git variables and keeps the others (got: $got)" $?

# keel_helpers.sh (sourced by every bash suite) does the same
got="$(GIT_DIR="$TR/.git" GIT_COMMON_DIR="$TR/.git" bash -c '. "$1"; printf "%s|%s" "${GIT_DIR-unset}" "${GIT_COMMON_DIR-unset}"' _ "$REPO_ROOT/tests/keel_helpers.sh")"
[ "$got" = "unset|unset" ]; check "keel_helpers.sh clears the repository-local git variables" $?

# a suite that creates repositories and commits in temporary directories, started the way a pre-push hook starts it
GIT_DIR="$TR/.git" GIT_WORK_TREE="$TR" GIT_INDEX_FILE="$TR/.git/index" bash "$REPO_ROOT/tests/keel_scripts_test.sh" >"$W/scripts.out" 2>&1
rc=$?
[ "$rc" -eq 0 ]; check "keel_scripts_test.sh passes with GIT_DIR, GIT_WORK_TREE and GIT_INDEX_FILE exported" $?
[ "$rc" -eq 0 ] || grep FAIL "$W/scripts.out" | head -5
[ "$(snapshot)" = "$before" ]; check "...and the repository named by GIT_DIR is unchanged (config, refs, worktrees, HEAD, status)" $?

# the Go tests and the Makefile target
if command -v go >/dev/null 2>&1; then
  GIT_DIR="$TR/.git" GIT_WORK_TREE="$TR" GIT_INDEX_FILE="$TR/.git/index" make -C "$REPO_ROOT/cli/kh" test >"$W/gotest.out" 2>&1
  rc=$?
  [ "$rc" -eq 0 ]; check "make -C cli/kh test passes with GIT_DIR, GIT_WORK_TREE and GIT_INDEX_FILE exported" $?
  [ "$rc" -eq 0 ] || grep -v '^ok' "$W/gotest.out" | head -10
  [ "$(snapshot)" = "$before" ]; check "...and the repository named by GIT_DIR is unchanged after the Go tests" $?
  # go test itself, bypassing the Makefile: the TestMain of each package clears the variables
  (cd "$REPO_ROOT/cli/kh" && GIT_DIR="$TR/.git" GIT_WORK_TREE="$TR" GIT_INDEX_FILE="$TR/.git/index" go test -count=1 ./internal/... >"$W/gotest2.out" 2>&1)
  rc=$?
  [ "$rc" -eq 0 ]; check "go test ./... directly passes with the git variables exported (TestMain of every package)" $?
  [ "$(snapshot)" = "$before" ]; check "...and the repository named by GIT_DIR is unchanged after go test" $?
  # every package whose tests exist has the TestMain
  miss=""
  for d in "$REPO_ROOT"/cli/kh/internal/*/; do
    n="$(basename "$d")"
    ls "$d"*_test.go >/dev/null 2>&1 || continue
    [ "$n" = gitenv ] && continue
    grep -q 'func TestMain' "$d"*_test.go || miss="$miss $n"
  done
  [ -z "$miss" ]; check "every Go package with tests clears the git variables in a TestMain${miss:+ (missing:$miss)}" $?
else
  echo "  skip Go part: go not installed"
fi

finish
