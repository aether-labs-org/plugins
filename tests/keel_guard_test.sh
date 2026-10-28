#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/keel_helpers.sh"
G="$KEEL/assets/core/sensors/common/guard.sh"
[ -f "$G" ]; check "guard.sh exists" $?

# mk -> committed harness: file-size rule (LIMIT=10, empty baseline) and a lint sensor
mk() {
  local r; r="$(new_repo)"
  install_asset "$r" assets/core/gate.sh scripts/gate.sh
  install_asset "$r" assets/core/lib/baseline.sh scripts/lib/baseline.sh
  install_asset "$r" assets/core/lib/envparse.sh scripts/lib/envparse.sh
  install_asset "$r" assets/core/sensors/common/guard.sh scripts/sensors/guard.sh
  install_asset "$r" assets/core/sensors/rules/file-size.sh scripts/sensors/file-size.sh
  mkdir -p "$r/.agents/rules" "$r/.agents/baselines" "$r/src" "$r/docs/adr"
  cp "$KEEL/assets/core/gate.env" "$r/.agents/gate.env"
  printf 'schema_version: 2\n' > "$r/.agents/state.yml"
  printf 'RULE_ID=file-size\nENFORCEMENT=sensor:file-size\nLIMIT=10\nINCLUDE=src\n' > "$r/.agents/rules/file-size.env"
  printf '# measured_at: 2026-10-24 review_by: 2027-04-24\n' > "$r/.agents/baselines/file-size.tsv"
  (cd "$r" && git add -A && git commit -q -m harness)
  printf '%s\n' "$r"
}
run() { out="$(cd "$1" && bash scripts/sensors/guard.sh)"; rc=$?; }
head1() { printf '%s\n' "$out" | head -1 | cut -f1-3; }

r="$(mk)"; run "$r"
[ $rc -eq 0 ] && [ "$(head1)" = "guard	security	pass" ]; check "clean harness passes" $?

# D-1 reproduction: an oversize file fails file-size; adding it to the baseline must not pass the gate
seq 1 20 > "$r/src/big.txt"
(cd "$r" && bash scripts/gate.sh fast >/dev/null); [ $? -eq 1 ]; check "D-1: 20-line file over LIMIT=10 fails the gate" $?
printf 'src/big.txt\t20\n' >> "$r/.agents/baselines/file-size.tsv"
(cd "$r" && bash scripts/gate.sh fast >/dev/null); [ $? -eq 1 ]; check "D-1: baselining it in the same change still fails the gate" $?
run "$r"
[ $rc -eq 1 ] && printf '%s\n' "$out" | grep -qF '.agents/baselines/file-size.tsv: src/big.txt 0 -> 20'
check "D-1: guard names the baseline row that appeared" $?
printf '%s\n' "$out" | grep -q '^  guidance: undo the loosening'; check "guidance on fail" $?

printf '# ADR 0007\nWe freeze `.agents/baselines/file-size.tsv` for src/big.txt until the split lands.\n' > "$r/docs/adr/0007-freeze-big.md"
run "$r"; [ $rc -eq 0 ] && printf '%s' "$out" | head -1 | grep -q '1 loosening(s)'; check "an ADR added in the change that names the file passes" $?
(cd "$r" && git add -A && git commit -q -m adr)
printf 'src/big.txt\t25\n' > "$r/.agents/baselines/file-size.tsv.tmp"; printf '# measured_at: 2026-10-24 review_by: 2027-04-24\n' | cat - "$r/.agents/baselines/file-size.tsv.tmp" > "$r/.agents/baselines/file-size.tsv"; rm "$r/.agents/baselines/file-size.tsv.tmp"
run "$r"; [ $rc -eq 1 ]; check "an ADR from an earlier commit does not cover a new loosening" $?

r="$(mk)"; printf '# measured_at: 2026-10-24 review_by: 2027-04-24\n' > "$r/.agents/baselines/lint.tsv"; printf 'src/a.ts\t3\n' >> "$r/.agents/baselines/lint.tsv"
run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | grep -qF 'lint.tsv: src/a.ts 0 -> 3'; check "a new baseline file counts as loosening" $?

r="$(mk)"; printf 'src/x.ts\t2\n' >> "$r/.agents/baselines/file-size.tsv"; (cd "$r" && git add -A && git commit -q -m b)
printf '# measured_at: 2026-10-24 review_by: 2027-04-24\nsrc/x.ts\t1\n' > "$r/.agents/baselines/file-size.tsv"
run "$r"; [ $rc -eq 0 ]; check "shrinking a baseline passes" $?

r="$(mk)"; sed -i.bak 's/LIMIT=10/LIMIT=500/' "$r/.agents/rules/file-size.env"; rm -f "$r/.agents/rules/file-size.env.bak"
run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | grep -qF 'LIMIT raised from 10 to 500'; check "raising LIMIT fails" $?
r="$(mk)"; sed -i.bak 's/LIMIT=10/LIMIT=8/' "$r/.agents/rules/file-size.env"; rm -f "$r/.agents/rules/file-size.env.bak"
run "$r"; [ $rc -eq 0 ]; check "lowering LIMIT passes" $?
r="$(mk)"; printf 'MUTATION_MIN_SCORE=60\n' >> "$r/.agents/rules/file-size.env"; (cd "$r" && git add -A && git commit -q -m m)
sed -i.bak 's/MUTATION_MIN_SCORE=60/MUTATION_MIN_SCORE=40/' "$r/.agents/rules/file-size.env"; rm -f "$r/.agents/rules/file-size.env.bak"
run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | grep -qF 'MUTATION_MIN_SCORE lowered from 60 to 40'; check "lowering a *MIN* key fails" $?
r="$(mk)"; printf "EXCLUDE='src/gen/'\n" >> "$r/.agents/rules/file-size.env"
run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | grep -qF 'EXCLUDE widened'; check "widening EXCLUDE fails" $?
r="$(mk)"; sed -i.bak 's/ENFORCEMENT=sensor:file-size/ENFORCEMENT=inferential/' "$r/.agents/rules/file-size.env"; rm -f "$r/.agents/rules/file-size.env.bak"
run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | grep -qF 'ENFORCEMENT changed'; check "changing ENFORCEMENT fails" $?
r="$(mk)"; rm "$r/.agents/rules/file-size.env"
run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | grep -qF 'rule deleted'; check "deleting a rule fails" $?
r="$(mk)"; sed -i.bak 's/CEILING_SECONDS=30/CEILING_SECONDS=300/' "$r/.agents/gate.env"; rm -f "$r/.agents/gate.env.bak"
run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | grep -qF 'CEILING_SECONDS raised from 30 to 300'; check "raising the fast budget fails" $?
r="$(mk)"; mkdir -p "$r/scripts/sensors/disabled"; (cd "$r" && git mv scripts/sensors/file-size.sh scripts/sensors/disabled/file-size.sh)
run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | grep -qF 'scripts/sensors/file-size.sh: sensor removed or disabled'; check "disabling a sensor fails" $?

# adr_dir in state.yml (D45): only that folder's ADRs count
r="$(mk)"; printf 'adr_dir: docs/decisions\n' >> "$r/.agents/state.yml"; mkdir -p "$r/docs/decisions"; (cd "$r" && git add -A && git commit -q -m adr-dir)
sed -i.bak 's/LIMIT=10/LIMIT=50/' "$r/.agents/rules/file-size.env"; rm -f "$r/.agents/rules/file-size.env.bak"
printf 'Raise .agents/rules/file-size.env\n' > "$r/docs/adr/0009-raise.md"
run "$r"; [ $rc -eq 1 ]; check "adr_dir: an ADR outside the recorded folder does not count" $?
mv "$r/docs/adr/0009-raise.md" "$r/docs/decisions/0009-raise.md"
run "$r"; [ $rc -eq 0 ]; check "adr_dir: an ADR in the recorded folder counts" $?

# committed loosening is still caught against the merge-base with origin/HEAD
r="$(mk)"; (cd "$r" && git update-ref refs/remotes/origin/main HEAD && git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main)
sed -i.bak 's/LIMIT=10/LIMIT=99/' "$r/.agents/rules/file-size.env"; rm -f "$r/.agents/rules/file-size.env.bak"; (cd "$r" && git commit -qam loosen)
run "$r"; [ $rc -eq 1 ]; check "a committed loosening fails against the merge-base with origin/HEAD" $?
out="$(cd "$r" && KEEL_GUARD_BASE=HEAD bash scripts/sensors/guard.sh)"; [ $? -eq 0 ]; check "KEEL_GUARD_BASE overrides the base" $?
out="$(cd "$r" && KEEL_GUARD_BASE=nope bash scripts/sensors/guard.sh)"; [ $? -eq 1 ] && printf '%s' "$out" | grep -q 'is not a commit'; check "a bad KEEL_GUARD_BASE fails" $?

# install and edge cases
r="$(new_repo --no-commit)"; install_asset "$r" assets/core/lib/envparse.sh scripts/lib/envparse.sh; install_asset "$r" assets/core/sensors/common/guard.sh scripts/sensors/guard.sh
run "$r"; [ $rc -eq 0 ] && printf '%s' "$out" | grep -q 'No commits yet'; check "no commits: pass" $?
r="$(new_repo)"; install_asset "$r" assets/core/lib/envparse.sh scripts/lib/envparse.sh; install_asset "$r" assets/core/sensors/common/guard.sh scripts/sensors/guard.sh
mkdir -p "$r/.agents/baselines"; printf 'schema_version: 2\n' > "$r/.agents/state.yml"; printf 'src/a.ts\t9\n' > "$r/.agents/baselines/lint.tsv"
run "$r"; [ $rc -eq 0 ] && printf '%s' "$out" | grep -q 'Harness installed in this change'; check "harness installed in this change: pass" $?
r="$(mk)"; rm "$r/scripts/lib/envparse.sh"; run "$r"; [ $rc -eq 2 ]; check "missing envparse lib: skip" $?
finish
