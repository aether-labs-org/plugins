#!/usr/bin/env bash
# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.
# architecture - correctness rule sensor. Runs the stack's native architecture tool (ArchUnit,
# dependency-cruiser or import-linter) generated from the approved map in
# .agents/rules/architecture.env, and translates its result. The tool keeps its own baseline
# (FreezingArchRule store, depcruise known violations, import-linter ignore_imports), so
# KEEL_MEASURE=1 only points at the rule doc.
# Out: line 1 = id<TAB>class<TAB>status<TAB>summary. Exit 0 pass / 1 fail / 2 skip.
set -uo pipefail
id=architecture
class=correctness

RULE_ENV="${RULE_ENV:-.agents/rules/$id.env}"
if [ ! -f "$RULE_ENV" ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "no .agents/rules/$id.env - run the rules skill"
  exit 2
fi
# The env file may define LANG (java|kotlin|ts|python); keep the shell's own locale variable intact.
orig_lang="${LANG-}"
# shellcheck disable=SC1090,SC1091
. "${KEEL_ENVPARSE_LIB:-scripts/lib/envparse.sh}" 2>/dev/null || {
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "scripts/lib/envparse.sh is missing - run /keel-harness:build"
  exit 2
}
keel_env_load_sensor "$id" "$class" "$RULE_ENV"
LANG="$orig_lang"

# --- keel:repo-specific begin ---
ENGINE="archunit"
CMD=(./gradlew -q test --tests '*ArchitectureTest')
# other engines: ENGINE="depcruise"   CMD=(node_modules/.bin/depcruise src --config .dependency-cruiser.cjs --ignore-known .agents/baselines/depcruise-known-violations.json --output-type err)
#                ENGINE="importlinter" CMD=(.venv/bin/lint-imports)
GUIDANCE="Move the dependency behind a port owned by the inner layer, or move the code to the layer allowed to depend on it (docs/architecture.md#architecture). Do not edit the generated rule or the native baseline to make this pass."
# --- keel:repo-specific end ---

if [ "${KEEL_MEASURE:-}" = 1 ]; then
  echo "# native baseline - see docs/architecture.md#architecture"
  exit 0
fi

case "${CMD[0]}" in
  */*) [ -x "${CMD[0]}" ] && have=1 || have=0 ;;
  *) command -v "${CMD[0]}" >/dev/null 2>&1 && have=1 || have=0 ;;
esac
if [ "$have" -ne 1 ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "${CMD[0]} not found ($ENGINE) - run: make bootstrap"
  exit 2
fi

# No known-violations file yet (greenfield, or nothing frozen): run without --ignore-known, which
# dependency-cruiser would otherwise reject as an unreadable file.
run=(); k=0
while [ "$k" -lt "${#CMD[@]}" ]; do
  if [ "${CMD[$k]}" = "--ignore-known" ] && [ ! -f "${CMD[$((k + 1))]:-}" ]; then
    k=$((k + 2)); continue
  fi
  run[${#run[@]}]="${CMD[$k]}"; k=$((k + 1))
done

# The ArchUnit engine runs through a quiet build: its violation text is in the JUnit reports.
# shellcheck disable=SC1091
[ "$ENGINE" = archunit ] && [ -f scripts/lib/junit.sh ] && . scripts/lib/junit.sh
# A temp file: TMPDIR, else .agents/run/tmp/ (git-ignored), else none.
keel_tmpfile() { mktemp 2>/dev/null || { mkdir -p .agents/run/tmp 2>/dev/null && mktemp .agents/run/tmp/XXXXXX 2>/dev/null; }; }
since="$(keel_tmpfile)" || since=""
if [ -z "$since" ] || [ ! -f "$since" ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "no writable temp directory (TMPDIR or .agents/run/tmp/)"
  exit 2
fi
trap 'rm -f "$since"' EXIT
out="$("${run[@]}" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "No new architecture violations ($ENGINE)."
  exit 0
fi

case "$ENGINE" in
  archunit)
    if ! printf '%s\n' "$out" | grep -q 'was violated (' && type junit_messages >/dev/null 2>&1; then
      out="$out
$(junit_messages "$since")"
    fi
    n=$(printf '%s\n' "$out" | sed -n 's/.*was violated (\([0-9][0-9]*\) times\{0,1\}).*/\1/p' | awk '{ s += $1 } END { print s + 0 }')
    details=$(printf '%s\n' "$out" | awk '/was violated \(/ { on = 1; next } /Architecture Violation/ { on = 0 } on && NF { sub(/^[ \t]+/, ""); print; if (++k >= 5) exit }') ;;
  depcruise)
    n=$(printf '%s\n' "$out" | grep -cE '^ *(error|warn) ')
    details=$(printf '%s\n' "$out" | grep -E '^ *(error|warn) ' | head -5 | sed 's/^ *//') ;;
  importlinter)
    n=$(printf '%s\n' "$out" | sed -n 's/.*Contracts: [0-9]* kept, \([0-9]*\) broken.*/\1/p' | tail -1)
    # The offending import edges first ("- a.b -> c.d (l.3)"), then the names of broken contracts.
    details=$({ printf '%s\n' "$out" | grep -E '^[[:space:]]*-[[:space:]].*->'; printf '%s\n' "$out" | grep -E 'BROKEN[[:space:]]*$'; } | head -5 | sed 's/^[[:space:]]*//') ;;
  *) n=0; details="" ;;
esac
: "${n:=0}"
if [ "$n" -eq 0 ]; then
  # Non-zero exit without a parsable violation: the tool itself could not run.
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "$ENGINE exited $rc without reporting a violation - check its configuration."
  printf '%s\n' "$out" | sed '/^[[:space:]]*$/d' | head -5 | sed 's/^/  /'
  printf '  guidance: %s\n' "Run ${run[*]} by hand from the repository root and fix the configuration problem it reports before trusting this sensor."
  exit 1
fi
printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "$n architecture violation(s) ($ENGINE)."
printf '%s\n' "$details" | head -5 | sed 's/^/  /'
printf '  guidance: %s\n' "$GUIDANCE"
exit 1
