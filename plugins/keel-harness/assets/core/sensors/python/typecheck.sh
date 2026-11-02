#!/usr/bin/env bash
# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.
# typecheck - correctness. Whole repo: a type checker resolves imports across the project.
# Out: line 1 = id<TAB>class<TAB>status<TAB>summary. Exit 0 pass / 1 fail / 2 skip.
set -uo pipefail
id=typecheck
class=correctness

# --- keel:repo-specific begin ---
TOOL="mypy"
CMD=(.venv/bin/mypy .)
# pyright: TOOL="pyright" CMD=(.venv/bin/pyright)
GUIDANCE='fix the FIRST error listed above and re-run; the ones below it are usually its cascade. If a value can genuinely be missing, model the absence (Optional, a union, a narrowing check) rather than silencing the checker with Any or # type: ignore - that makes this sensor blind to every future change in that file.'
# --- keel:repo-specific end ---

case "${CMD[0]}" in
  */*) [ -x "${CMD[0]}" ] && have=1 || have=0 ;;
  *) command -v "${CMD[0]}" >/dev/null 2>&1 && have=1 || have=0 ;;
esac
if [ "$have" -ne 1 ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "$TOOL is not installed - run: make bootstrap"
  exit 2
fi

out="$("${CMD[@]}" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
  sig=$(printf '%s\n' "$out" | grep -E 'Success: no issues found|0 errors' | tail -1)
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "${sig:-no type errors}"
  exit 0
fi

n=$(printf '%s\n' "$out" | grep -cE ':[0-9]+(:[0-9]+)?: error:| - error:')
if [ "$n" -eq 0 ]; then
  # Exit non-zero without a file:line error: the tool itself could not run (config, missing target).
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "$TOOL exited $rc without reporting a file error - check its configuration."
  printf '%s\n' "$out" | sed '/^[[:space:]]*$/d' | head -5 | sed 's/^/  /'
  printf '  guidance: %s\n' "Run ${CMD[*]} by hand from the repository root and fix the configuration problem it reports (a missing target, an unreadable config file) before trusting this sensor."
  exit 1
fi
printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "Found $n type error(s) ($TOOL)."
printf '%s\n' "$out" | grep -E ':[0-9]+(:[0-9]+)?: error:| - error:' | head -5 | sed 's/^/  /'
printf '  guidance: %s\n' "$GUIDANCE"
exit 1
