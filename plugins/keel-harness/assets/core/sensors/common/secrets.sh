#!/usr/bin/env bash
# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.
# secrets - security. No ratchet and no allow-list: the first leak fails, full stop.
# In:  SCOPE (newline-separated changed files; empty = SECRETS_ROOTS).
# Out: line 1 = id<TAB>class<TAB>status<TAB>summary. Exit 0 pass / 1 fail / 2 skip.
set -uo pipefail
id=secrets
class=security

# --- keel:repo-specific begin ---
GITLEAKS="gitleaks"
SECRETS_ROOTS="src"
GUIDANCE='rotate every credential in the paths listed above right now, then remove it from source and load it from an environment variable or secret manager at runtime - deleting it from the latest commit is not enough, it is still readable from git history. GitLeaks only matches contiguous patterns: a literal built from string concatenation (like "sk_live_" + "...") will not trip this sensor, so treat any provider-prefix-plus-suffix construction as a leak even when this sensor stays green.'
# --- keel:repo-specific end ---

if ! command -v "$GITLEAKS" >/dev/null 2>&1; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "gitleaks is not installed - install gitleaks and re-run make gate-fast"
  exit 2
fi

paths=""
if [ -n "${SCOPE:-}" ]; then
  paths=$(printf '%s\n' "$SCOPE" | while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done)
  if [ -z "$paths" ]; then
    printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "No files to scan."
    exit 0
  fi
else
  paths=$(printf '%s\n' $SECRETS_ROOTS)
fi

total=0; bad=""
while IFS= read -r p; do
  [ -n "$p" ] || continue
  total=$((total + 1))
  if ! "$GITLEAKS" dir "$p" --no-banner --exit-code 1 >/dev/null 2>&1; then
    bad="${bad}${p}
"
  fi
done <<LIST
$paths
LIST

if [ -z "$bad" ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "No leaks found in $total path(s)."
  exit 0
fi
nb=$(printf '%s' "$bad" | grep -c .)
printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "Leaked credentials found in $nb of $total path(s)."
printf '%s' "$bad" | head -5 | sed 's/^/  /'
printf '  guidance: %s\n' "$GUIDANCE"
exit 1
