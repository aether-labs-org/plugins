#!/usr/bin/env bash
# Sourced by the keel and kh test suites. Not a test itself.
_keel_fail=0
# KH_ROOT is the wrapper's hand-off to kh (the slow gate runs this suite under a wrapper that exports it): the suites
# build and run their own kh in temporary repositories, so they choose the root with the cwd or set KH_ROOT themselves
unset KH_ROOT
# check DESCRIPTION EXIT_CODE: prints "  ok" or "  FAIL"
check() { if [ "$2" -eq 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; _keel_fail=1; fi; }
fail() { echo "  FAIL $1"; _keel_fail=1; }
# directories created by a suite, removed on EXIT
_keel_tmps=""
_keel_cleanup() { for d in $_keel_tmps; do rm -rf "$d"; done; }
trap _keel_cleanup EXIT
# finish: exit with the accumulated status
finish() { exit $_keel_fail; }
