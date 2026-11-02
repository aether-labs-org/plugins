#!/usr/bin/env bash
# Test stand-in for REVIEWER_CMD (C3). No model, no network. Reads the prompt on stdin.
# Calibrated: it fails exactly when an added line of the diff calls console.log and the prompt carries
# the no-console rule, so the two patches next to it (violates.patch, clean.patch) give FAIL and PASS.
# STUB_MODE overrides the verdict: pass | fail | both | chatter | garbage | silent | exit3 | hang.
# STUB_STDIN=<file> keeps a copy of the prompt; STUB_LOG=<file> logs argv.
printf '%s\n' "$*" >> "${STUB_LOG:-/dev/null}"
prompt="$(cat)"
[ -n "${STUB_STDIN:-}" ] && printf '%s\n' "$prompt" > "$STUB_STDIN"
case "${STUB_MODE:-}" in
  pass) echo PASS; exit 0 ;;
  fail) echo "FAIL: src/app.ts: calls console.log (no-console)"; exit 0 ;;
  both) printf 'PASS\nFAIL: src/app.ts: calls console.log (no-console)\nFAIL: src/b.ts: second violation\n'; exit 0 ;;
  chatter) printf 'I looked at the change.\nFAIL: src/app.ts: calls console.log (no-console)\nThat is all.\n'; exit 0 ;;
  garbage) echo "Looks fine to me, no problems found."; exit 0 ;;
  silent) exit 0 ;;
  exit3) echo "model overloaded" >&2; exit 3 ;;
  hang) exec sleep 30 ;;
esac
if printf '%s\n' "$prompt" | sed -n '/^## Diff since/,$p' | grep -E '^\+[^+].*console\.log' >/dev/null &&
   printf '%s\n' "$prompt" | grep 'docs/conventions.md#no-console' >/dev/null; then
  echo "FAIL: src/app.ts: adds console.log, which docs/conventions.md#no-console forbids"
else
  echo PASS
fi
exit 0
