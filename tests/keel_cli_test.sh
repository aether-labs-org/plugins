#!/usr/bin/env bash
# keel CLI behaviour that has no bash-engine counterpart: keel.yaml validation, the pin and the lock,
# import, single-sensor runs, and guard over keel.yaml.
set -uo pipefail
. "$(dirname "$0")/keel_helpers.sh"
BIN="${KEEL_BIN:-$(cd "$(dirname "$0")/.." && pwd)/cli/keel/dist/keel}"
SUMS="$(dirname "$BIN")/SHA256SUMS"
if [ ! -x "$BIN" ]; then
  if [ -n "${CI:-}" ]; then fail "keel CLI not built (make -C cli/keel build is required in CI)"; finish; fi
  echo "  skip keel CLI: $BIN not built (make -C cli/keel build)"; exit 0
fi
k() { out="$(cd "$r" && "$BIN" "$@" 2>&1)"; rc=$?; }
# stub_guard REPO -> a scripts/sensors/guard.sh that obeys the contract; `keel import` maps the file
# name to the native guard adapter, so its content never runs.
stub_guard() { printf '#!/usr/bin/env bash\nprintf "guard\\tsecurity\\tpass\\tstub\\n"\n' > "$1/scripts/sensors/guard.sh"; }
has() { printf '%s\n' "$out" | grep -qF -- "$1"; }

# mk -> committed repo with one exec sensor, guard, state.yml, keel.yaml and keel.lock imported
mk() {
  r="$(new_repo)"
  mkdir -p "$r/scripts/sensors" "$r/.agents" "$r/docs/adr"
  printf '#!/usr/bin/env bash\nprintf "lint\\theuristic\\tpass\\tok\\n"\n[ "${KEEL_MEASURE:-}" = 1 ] && echo measured\nprintf "%%s" "$SCOPE" > scope.out\n' > "$r/scripts/sensors/lint.sh"
  stub_guard "$r"
  printf 'schema_version: 2\n' > "$r/.agents/state.yml"
  # As /keel-harness:build will: a wrapper replaced by a native adapter leaves the repository.
  (cd "$r" && "$BIN" import --sums "$SUMS" >/dev/null && rm scripts/sensors/guard.sh && git add -A && git commit -qm harness)
}
yaml_set() { sed -i "$1" "$r/.agents/keel.yaml"; }

mk; k version; [ "$out" = "keel 0.1.0" ]; check "version" $?
k validate; [ $rc -eq 0 ] && has 'is valid (2 sensors, keel 0.1.0 pinned)'; check "imported layout validates" $?
grep -q '^    adapter: guard$' "$r/.agents/keel.yaml" && grep -q '^    exec: scripts/sensors/lint.sh$' "$r/.agents/keel.yaml"; check "import: guard becomes the native adapter, lint stays exec" $?
k import; [ $rc -eq 3 ] && has 'pass --force'; check "import refuses to overwrite keel.yaml" $?

# validation: every problem is exit 3, never a pass
for c in 's/^version: 1$/version: 2/|version must be 1' \
         's/^requires: .*/requires: ">=0.1,<0.2"/|exact version' \
         's/^gate:$/bogus: 1\ngate:/|field bogus not found' \
         's#exec: scripts/sensors/lint.sh#exec: scripts/sensors/nope.sh#|does not exist' \
         's#exec: scripts/sensors/lint.sh#exec: ../lint.sh#|clean path inside the repository' \
         's#    adapter: guard#    adapter: guard\n    exec: scripts/sensors/guard.sh#|exactly one of exec and adapter' \
         's#adapter: guard#adapter: nope#|unknown adapter' \
         's#  - id: lint#  - id: other#|id must equal the exec file name' \
         's#  - id: lint#  - id: guard#|duplicate id' \
         's#gate: fast#gate: medium#|gate must be fast or slow'; do
  mk; yaml_set "${c%%|*}"; k gate fast; [ $rc -eq 3 ] && has "${c#*|}"; check "invalid keel.yaml -> exit 3: ${c#*|}" $?
done
mk; printf '#!/usr/bin/env bash\nexit 0\n' > "$r/scripts/sensors/extra.sh"; k gate fast
[ $rc -eq 3 ] && has 'scripts/sensors/extra.sh is not listed under sensors:'; check "an unlisted sensor file fails validation" $?
mk; mkdir -p "$r/scripts/sensors/disabled"; : > "$r/scripts/sensors/_util.sh"; : > "$r/scripts/sensors/disabled/x.sh"; k validate
[ $rc -eq 0 ]; check "_files and disabled/ are not unlisted sensors" $?

# the pin: keel.yaml, keel.lock and the running binary must agree
mk; yaml_set 's/^requires: .*/requires: 9.9.9/'; k gate fast
[ $rc -eq 3 ] && has 'requires keel 9.9.9, but this is keel 0.1.0'; check "pin: other version -> exit 3" $?
mk; rm "$r/.agents/keel.lock"; k gate fast; [ $rc -eq 3 ] && has 'no .agents/keel.lock'; check "pin: missing lock -> exit 3" $?
mk; sed -i 's/^version\t.*/version\t0.0.9/' "$r/.agents/keel.lock"; k gate fast; [ $rc -eq 3 ] && has 'pins keel 0.0.9'; check "pin: lock version differs -> exit 3" $?
mk; sed -i -E 's/\t[0-9a-f]{64}$/\t0000000000000000000000000000000000000000000000000000000000000000/' "$r/.agents/keel.lock"; k gate fast
[ $rc -eq 3 ] && has 'is not the build .agents/keel.lock pins'; check "pin: binary checksum differs -> exit 3" $?

# commands
mk; mkdir -p "$r/src/deep"; out="$(cd "$r/src/deep" && "$BIN" gate fast 2>&1)"; rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | grep -q '^gate: fast - PASSED (2 of 2)'; check "gate finds the root from a subdirectory" $?
mk; k gate bogus; [ $rc -eq 64 ]; check "gate bogus -> 64" $?
mk; k gate --sensor nope; [ $rc -eq 64 ] && has 'no sensor "nope"'; check "gate --sensor unknown -> 64" $?
mk; out="$(cd "$r" && SCOPE=$'a.ts\nb.ts' "$BIN" gate --sensor lint 2>&1)"; rc=$?
[ $rc -eq 0 ] && [ "$(printf '%s\n' "$out" | head -1)" = "$(printf 'lint\theuristic\tpass\tok')" ] && [ "$(cat "$r/scope.out")" = $'a.ts\nb.ts' ]
check "gate --sensor prints the raw contract output and passes SCOPE through" $?
mk; k measure lint; [ $rc -eq 0 ] && has 'measured'; check "measure sets KEEL_MEASURE=1" $?
mk; k guard; [ $rc -eq 0 ] && [ "$(printf '%s\n' "$out" | head -1 | cut -f1-3)" = "$(printf 'guard\tsecurity\tpass')" ]; check "guard on a clean harness passes" $?

# guard over keel.yaml: the loosenings an engine switch could otherwise hide
mk; yaml_set '/  - id: guard/,/adapter: guard/d'; k gate fast
[ $rc -eq 3 ] && has 'must list the guard sensor'; check "an installed harness cannot drop the guard entry (exit 3)" $?
mk; rm "$r/.agents/state.yml"; yaml_set '/  - id: guard/,/adapter: guard/d'; k validate
[ $rc -eq 0 ]; check "without .agents/state.yml the guard entry is optional" $?
mk; (cd "$r" && rm -f .agents/keel.yaml && "$BIN" import >/dev/null); grep -q '^    adapter: guard$' "$r/.agents/keel.yaml"
check "import adds the guard adapter to an installed harness that lacks guard.sh" $?
mk; mkdir -p "$r/scripts/sensors/disabled"; (cd "$r" && git mv scripts/sensors/lint.sh scripts/sensors/disabled/lint.sh); yaml_set '/  - id: lint/,/exec: /d'; k guard
[ $rc -eq 1 ] && has 'scripts/sensors/lint.sh: sensor removed or disabled'; check "guard: an exec entry dropped with its file names the file" $?
mk; yaml_set '0,/ceiling_seconds: 30/s//ceiling_seconds: 90/'; k guard
[ $rc -eq 1 ] && has '.agents/keel.yaml: gate.fast.ceiling_seconds raised from 30 to 90'; check "guard: a raised keel.yaml budget is a loosening" $?
printf '# ADR 0009\nThe fast gate needs 90s: `.agents/keel.yaml`.\n' > "$r/docs/adr/0009-budget.md"; k guard
[ $rc -eq 0 ] && has '1 loosening(s)'; check "guard: an added ADR naming .agents/keel.yaml covers it" $?

# engine switch: budgets move from gate.env at the base to keel.yaml now
r="$(new_repo)"; mkdir -p "$r/scripts/sensors" "$r/.agents"; printf 'schema_version: 2\n' > "$r/.agents/state.yml"
cp "$KEEL/skills/build/assets/gate.env" "$r/.agents/gate.env"; stub_guard "$r"
(cd "$r" && git add -A && git commit -qm bash-engine && "$BIN" import --sums "$SUMS" >/dev/null && git rm -q .agents/gate.env)
k guard; [ $rc -eq 0 ]; check "engine switch with the same budgets passes" $?
yaml_set '0,/ceiling_seconds: 30/s//ceiling_seconds: 300/'; k guard
[ $rc -eq 1 ] && has 'gate.fast.ceiling_seconds raised from 30 to 300'; check "engine switch cannot raise a budget" $?
finish
