#!/usr/bin/env bash
# F3a: the CI workflow and pre-commit assets run the same fast gate an agent runs locally.
set -uo pipefail
. "$(dirname "$0")/keel_helpers.sh"
CI="$KEEL/assets/core/ci/keel.yml"
PC="$KEEL/assets/core/precommit"

# --- the assets
[ -f "$CI" ]; check "ci/keel.yml exists" $?
head -1 "$CI" | grep -q '^# Managed by keel-harness'; check "ci/keel.yml carries the managed-by header" $?
grep -q 'keel:repo-specific begin' "$CI" && grep -q 'keel:repo-specific end' "$CI"; check "ci/keel.yml has the repo-specific markers" $?
! grep -E 'uses: ' "$CI" | grep -vqE 'uses: [^@]+@[0-9a-f]{40} '; check "every action is pinned to a full commit SHA" $?
grep -q 'fetch-depth: 0' "$CI"; check "checkout fetches history (guard needs the base)" $?
grep -q "KEEL_GUARD_BASE: .*github.base_ref" "$CI"; check "guard compares with the PR's target branch" $?
grep -q 'run: make gate-fast' "$CI"; check "CI runs make gate-fast" $?
grep -q 'contents: read' "$CI"; check "CI token is read-only" $?
! grep -qE 'CLAUDE|claude ' "$CI"; check "CI calls no model and no plugin path" $?
for f in lefthook.yml pre-commit-config.yaml husky-pre-commit; do
  grep -q 'make gate-fast' "$PC/$f" 2>/dev/null; check "precommit/$f runs make gate-fast" $?
done
# YAML syntax, where PyYAML is installed (it is on GitHub's ubuntu runners)
if python3 -c 'import yaml' 2>/dev/null; then
  for f in "$CI" "$PC/lefthook.yml" "$PC/pre-commit-config.yaml"; do
    python3 -c 'import sys, yaml; yaml.safe_load(open(sys.argv[1]))' "$f"; check "$(basename "$f") parses as YAML" $?
  done
else
  echo "  skip YAML syntax of the ci and precommit assets (PyYAML not installed)"
fi

# --- a repository with the fast gate, a file-size rule and guard
mkharness() {
  local r; r="$(new_repo)"
  install_asset "$r" assets/core/gate.sh scripts/gate.sh
  install_asset "$r" assets/core/lib/baseline.sh scripts/lib/baseline.sh
  install_asset "$r" assets/core/lib/envparse.sh scripts/lib/envparse.sh
  install_asset "$r" assets/core/sensors/common/guard.sh scripts/sensors/guard.sh
  install_asset "$r" assets/core/sensors/rules/file-size.sh scripts/sensors/file-size.sh
  mkdir -p "$r/.agents/rules" "$r/.agents/baselines" "$r/src"
  cp "$KEEL/assets/core/gate.env" "$r/.agents/gate.env"
  printf "LIMIT=5\nINCLUDE='src'\n" > "$r/.agents/rules/file-size.env"
  printf 'schema_version: 3\nlayers: { ci: installed, precommit: installed }\n' > "$r/.agents/state.yml"
  printf 'gate-fast:\n\t@bash scripts/gate.sh fast\n' > "$r/Makefile"
  printf '.agents/run/\n' > "$r/.gitignore"
  printf '1\n2\n' > "$r/src/a.ts"
  (cd "$r" && git add -A && git commit -q -m harness)
  printf '%s\n' "$r"
}
defect() { printf '1\n2\n3\n4\n5\n6\n7\n' > "$1/src/a.ts"; } # 7 lines, over LIMIT=5

# pre-commit: the husky line as a plain git hook (husky, lefthook and pre-commit all run it)
r="$(mkharness)"
{ printf '#!/usr/bin/env bash\n'; grep -v '^#' "$PC/husky-pre-commit"; } > "$r/.git/hooks/pre-commit"; chmod +x "$r/.git/hooks/pre-commit"
(cd "$r" && printf 'x\n' > src/b.ts && git add src/b.ts && git commit -q -m clean) >/dev/null 2>&1; check "pre-commit: a clean change commits" $?
defect "$r"; (cd "$r" && git add src/a.ts && git commit -q -m defect) >/dev/null 2>&1; [ $? -ne 0 ]; check "pre-commit: a planted defect blocks the commit" $?
(cd "$r" && git log -1 --format=%s) | grep -qx clean; check "pre-commit: the defect was not committed" $?

# CI: the workflow's gate step in a clone of a pull request branch, guard based on origin/main
ci_gate() { # ci_gate ORIGIN BRANCH -> rc of the workflow's gate step
  local c; c="$(mktemp -d)"; _keel_tmps="$_keel_tmps $c"
  git clone -q "$1" "$c/w" 2>/dev/null && (cd "$c/w" && git checkout -q "$2" && KEEL_GUARD_BASE=origin/main make gate-fast >/dev/null 2>&1)
}
r="$(mkharness)"; (cd "$r" && git branch -M main && git checkout -q -b pr && printf 'x\n' > src/b.ts && git add -A && git commit -q -m ok)
ci_gate "$r" pr; check "CI: a clean pull request is green" $?
r="$(mkharness)"; (cd "$r" && git branch -M main && git checkout -q -b pr); defect "$r"; (cd "$r" && git add -A && git commit -q -m defect)
ci_gate "$r" pr; [ $? -ne 0 ]; check "CI: a planted defect is red" $?
r="$(mkharness)"; (cd "$r" && git branch -M main && git checkout -q -b pr); defect "$r"
(cd "$r" && printf '# measured_at: 2026-10-28 review_by: 2027-04-28\nsrc/a.ts\t7\n' > .agents/baselines/file-size.tsv && git add -A && git commit -q -m loosen)
ci_gate "$r" pr; [ $? -ne 0 ]; check "CI: hiding the defect in a baseline without an ADR is red (guard)" $?
finish
