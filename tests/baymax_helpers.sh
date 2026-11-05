#!/usr/bin/env bash
# Sourced by the baymax and bmax test suites. Not a test itself.
_bmax_fail=0
# BMAX_ROOT is the wrapper's hand-off to bmax (the slow gate runs this suite under a wrapper that exports it): the suites
# build and run their own bmax in temporary repositories, so they choose the root with the cwd or set BMAX_ROOT themselves
unset BMAX_ROOT
# BMAX_BINARY and BMAX_RELEASE_URL steer the wrapper: an inherited value (an owner testing a build, a mirror) would replace the
# binaries and mirrors the suites set up for themselves
unset BMAX_BINARY BMAX_RELEASE_URL
# Same for the repository-local git variables a git hook exports (GIT_DIR, GIT_INDEX_FILE ...): the suites run git in temporary
# directories, which must not mean the repository that started them.
# shellcheck disable=SC2046
unset $(git rev-parse --local-env-vars 2>/dev/null)
# check DESCRIPTION EXIT_CODE: prints "  ok" or "  FAIL"
check() { if [ "$2" -eq 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; _bmax_fail=1; fi; }
fail() { echo "  FAIL $1"; _bmax_fail=1; }
# directories created by a suite, removed on EXIT
_bmax_tmps=""
_bmax_cleanup() { for d in $_bmax_tmps; do rm -rf "$d"; done; }
trap _bmax_cleanup EXIT
# finish: exit with the accumulated status
finish() { exit $_bmax_fail; }
