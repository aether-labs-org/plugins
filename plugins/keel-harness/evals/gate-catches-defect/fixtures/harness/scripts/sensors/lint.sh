#!/usr/bin/env bash
# lint — heuristic, ratcheted against the install-day snapshot.
set -uo pipefail
id=lint
class=heuristic

eslint="node_modules/.bin/eslint"
if [ ! -x "$eslint" ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "eslint is not installed - run: make bootstrap"
  exit 2
fi

changed=$(printf '%s\n' "${SCOPE:-}" | sed '/^$/d' | grep -E '^src/.*\.(ts|tsx)$')
if [ -n "$changed" ]; then
  # shellcheck disable=SC2086
  out="$("$eslint" $changed 2>&1)"
else
  out="$("$eslint" src 2>&1)"
fi
now=$(printf '%s\n' "$out" | grep -cE '^ +[0-9]+:[0-9]+ +(error|warning)')
snap=$(sed -n 's/.*problems: *\([0-9][0-9]*\).*/\1/p' .agents/state.yml | head -1)
: "${snap:=$now}"

if [ "$now" -le "$snap" ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "$now problems. same as snapshot ($snap)."
  exit 0
fi
printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "$now problems, up from snapshot ($snap)."
printf '%s\n' "$out" | grep -E '^ +[0-9]+:[0-9]+' | head -5 | sed 's/^/  /'
printf '  guidance: this gate only forbids getting worse. Clear the new problems listed above in\n'
printf '  the files you just touched - the %s pre-existing ones are not yours to fix now. Do not\n' "$snap"
printf '  raise the snapshot in .agents/state.yml to make this pass; that single edit is what turns\n'
printf '  the ratchet off.\n'
exit 1
