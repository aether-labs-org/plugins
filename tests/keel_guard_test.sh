#!/usr/bin/env bash
set -uo pipefail
qgrep() { grep "$@" >/dev/null; } # reads all its input: `| grep -q` can SIGPIPE the writer under pipefail
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
[ $rc -eq 1 ] && printf '%s\n' "$out" | qgrep -F '.agents/baselines/file-size.tsv: src/big.txt 0 -> 20'
check "D-1: guard names the baseline row that appeared" $?
printf '%s\n' "$out" | qgrep '^  guidance: undo the loosening'; check "guidance on fail" $?

printf '# ADR 0007\nWe keep `.agents/baselines/file-size.tsv.bak` and `x.agents/baselines/file-size.tsv` around.\n' > "$r/docs/adr/0007-freeze-big.md"
run "$r"; [ $rc -eq 1 ]; check "an ADR naming a longer path (file-size.tsv.bak) does not cover the file" $?
printf '# ADR 0007\nWe freeze `.agents/baselines/file-size.tsv` for src/big.txt until the split lands.\n' > "$r/docs/adr/0007-freeze-big.md"
run "$r"; [ $rc -eq 0 ] && printf '%s' "$out" | head -1 | qgrep '1 loosening(s)'; check "an ADR added in the change that names the file passes" $?
(cd "$r" && git add -A && git commit -q -m adr)
printf 'src/big.txt\t25\n' > "$r/.agents/baselines/file-size.tsv.tmp"; printf '# measured_at: 2026-10-24 review_by: 2027-04-24\n' | cat - "$r/.agents/baselines/file-size.tsv.tmp" > "$r/.agents/baselines/file-size.tsv"; rm "$r/.agents/baselines/file-size.tsv.tmp"
run "$r"; [ $rc -eq 1 ]; check "an ADR from an earlier commit does not cover a new loosening" $?

r="$(mk)"; printf '# measured_at: 2026-10-24 review_by: 2027-04-24\n' > "$r/.agents/baselines/lint.tsv"; printf 'src/a.ts\t3\n' >> "$r/.agents/baselines/lint.tsv"
run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | qgrep -F 'lint.tsv: src/a.ts 0 -> 3'; check "a new baseline file counts as loosening" $?

r="$(mk)"; printf 'src/x.ts\t2\n' >> "$r/.agents/baselines/file-size.tsv"; (cd "$r" && git add -A && git commit -q -m b)
printf '# measured_at: 2026-10-24 review_by: 2027-04-24\nsrc/x.ts\t1\n' > "$r/.agents/baselines/file-size.tsv"
run "$r"; [ $rc -eq 0 ]; check "shrinking a baseline passes" $?

r="$(mk)"; sed -i.bak 's/LIMIT=10/LIMIT=500/' "$r/.agents/rules/file-size.env"; rm -f "$r/.agents/rules/file-size.env.bak"
run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | qgrep -F 'LIMIT raised from 10 to 500'; check "raising LIMIT fails" $?
r="$(mk)"; sed -i.bak 's/LIMIT=10/LIMIT=8/' "$r/.agents/rules/file-size.env"; rm -f "$r/.agents/rules/file-size.env.bak"
run "$r"; [ $rc -eq 0 ]; check "lowering LIMIT passes" $?
r="$(mk)"; printf 'MUTATION_MIN_SCORE=60\n' >> "$r/.agents/rules/file-size.env"; (cd "$r" && git add -A && git commit -q -m m)
sed -i.bak 's/MUTATION_MIN_SCORE=60/MUTATION_MIN_SCORE=40/' "$r/.agents/rules/file-size.env"; rm -f "$r/.agents/rules/file-size.env.bak"
run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | qgrep -F 'MUTATION_MIN_SCORE lowered from 60 to 40'; check "lowering a *MIN* key fails" $?
r="$(mk)"; printf "EXCLUDE='src/gen/'\n" >> "$r/.agents/rules/file-size.env"
run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | qgrep -F 'EXCLUDE widened'; check "widening EXCLUDE fails" $?
r="$(mk)"; sed -i.bak 's/ENFORCEMENT=sensor:file-size/ENFORCEMENT=inferential/' "$r/.agents/rules/file-size.env"; rm -f "$r/.agents/rules/file-size.env.bak"
run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | qgrep -F 'ENFORCEMENT changed'; check "changing ENFORCEMENT fails" $?
r="$(mk)"; rm "$r/.agents/rules/file-size.env"
run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | qgrep -F 'rule deleted'; check "deleting a rule fails" $?
r="$(mk)"; sed -i.bak 's/CEILING_SECONDS=30/CEILING_SECONDS=300/' "$r/.agents/gate.env"; rm -f "$r/.agents/gate.env.bak"
run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | qgrep -F 'CEILING_SECONDS raised from 30 to 300'; check "raising the fast budget fails" $?
r="$(mk)"; mkdir -p "$r/scripts/sensors/disabled"; (cd "$r" && git mv scripts/sensors/file-size.sh scripts/sensors/disabled/file-size.sh)
run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | qgrep -F 'scripts/sensors/file-size.sh: sensor removed or disabled'; check "disabling a sensor fails" $?

# pattern rules (F3d-1): a changed PATTERN or RULE_FILE, or an edited rule file, is a loosening
mkp() { # -> repo with a pattern rule (PATTERN) and an ast-grep rule (RULE_FILE), committed
  local g; g="$(mk)"
  printf 'RULE_ID=no-todo\nENFORCEMENT=sensor:no-todo\nPATTERN=TODO\nINCLUDE=src\n' > "$g/.agents/rules/no-todo.env"
  printf 'RULE_ID=no-any\nENFORCEMENT=sensor:no-any\nENGINE=ast-grep\nRULE_FILE=.agents/rules/no-any.yml\n' > "$g/.agents/rules/no-any.env"
  printf 'id: no-any\nrule:\n  pattern: any\n' > "$g/.agents/rules/no-any.yml"
  (cd "$g" && git add -A && git commit -q -m patterns)
  printf '%s\n' "$g"
}
r="$(mkp)"; run "$r"; [ $rc -eq 0 ]; check "pattern rules: unchanged passes" $?
r="$(mkp)"; sed -i.bak 's/^PATTERN=TODO$/PATTERN=FIXME/' "$r/.agents/rules/no-todo.env"; rm -f "$r/.agents/rules/no-todo.env.bak"
run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | qgrep -F '.agents/rules/no-todo.env: PATTERN changed'; check "pattern rules: a changed PATTERN fails" $?
r="$(mkp)"; sed -i.bak 's/^PATTERN=TODO$/PATTERN=TODO|FIXME/' "$r/.agents/rules/no-todo.env"; rm -f "$r/.agents/rules/no-todo.env.bak"
run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | qgrep -F 'PATTERN changed'; check "pattern rules: a widened PATTERN fails too (any change alters what is caught)" $?
printf '# ADR 0010\nWe change `.agents/rules/no-todo.env`: FIXME is the marker now.\n' > "$r/docs/adr/0010-pattern.md"
run "$r"; [ $rc -eq 0 ] && printf '%s' "$out" | head -1 | qgrep '1 loosening(s)'; check "pattern rules: an ADR added in the change that names the env file passes" $?
r="$(mkp)"; sed -i.bak 's|^RULE_FILE=.*|RULE_FILE=.agents/rules/other.yml|' "$r/.agents/rules/no-any.env"; rm -f "$r/.agents/rules/no-any.env.bak"
run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | qgrep -F 'RULE_FILE changed'; check "pattern rules: a changed RULE_FILE fails" $?
r="$(mkp)"; printf '  pattern: unknown\n' >> "$r/.agents/rules/no-any.yml"
run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | qgrep -F '.agents/rules/no-any.yml: pattern rule file changed'; check "pattern rules: an edited rule file fails, naming the rule file" $?
printf '# ADR 0011\nWe edit `.agents/rules/no-any.yml` to cover unknown.\n' > "$r/docs/adr/0011-rule-file.md"
run "$r"; [ $rc -eq 0 ]; check "pattern rules: an ADR naming the rule file passes" $?
r="$(mkp)"; printf 'RULE_ID=new\nPATTERN=NEW\n' > "$r/.agents/rules/new.env"
run "$r"; [ $rc -eq 0 ]; check "pattern rules: a new pattern rule is not a loosening" $?
r="$(mkp)"; printf 'LIMIT=10\n' >> "$r/.agents/rules/no-todo.env"; printf 'EXEMPLAR=src/a.ts\n' >> "$r/.agents/rules/no-todo.env"
run "$r"; [ $rc -eq 0 ]; check "pattern rules: adding an EXEMPLAR or a key other than PATTERN is left alone" $?

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
out="$(cd "$r" && KEEL_GUARD_BASE=nope bash scripts/sensors/guard.sh)"; [ $? -eq 1 ] && printf '%s' "$out" | qgrep 'is not a commit'; check "a bad KEEL_GUARD_BASE fails" $?

# install and edge cases
r="$(new_repo --no-commit)"; install_asset "$r" assets/core/lib/envparse.sh scripts/lib/envparse.sh; install_asset "$r" assets/core/sensors/common/guard.sh scripts/sensors/guard.sh
run "$r"; [ $rc -eq 0 ] && printf '%s' "$out" | qgrep 'No commits yet'; check "no commits: pass" $?
r="$(new_repo)"; install_asset "$r" assets/core/lib/envparse.sh scripts/lib/envparse.sh; install_asset "$r" assets/core/sensors/common/guard.sh scripts/sensors/guard.sh
mkdir -p "$r/.agents/baselines"; printf 'schema_version: 2\n' > "$r/.agents/state.yml"; printf 'src/a.ts\t9\n' > "$r/.agents/baselines/lint.tsv"
run "$r"; [ $rc -eq 0 ] && printf '%s' "$out" | qgrep 'Harness installed in this change'; check "harness installed in this change: pass" $?
r="$(mk)"; rm "$r/scripts/lib/envparse.sh"; run "$r"; [ $rc -eq 2 ]; check "missing envparse lib: skip" $?

# --- mandatory rules (D43): ENFORCEMENT_LEVEL=mandatory, exceptions that only shrink, a superseding ADR
ENVF=.agents/rules/file-size.env
# wenv REPO LIMIT LEVEL_LINE EXCEPTIONS_BODY -> writes the file-size rule env (LEVEL_LINE and the body may be empty)
wenv() {
  { printf 'RULE_ID=file-size\nENFORCEMENT=sensor:file-size\n'
    [ -n "$3" ] && printf '%s\n' "$3"
    printf 'LIMIT=%s\nINCLUDE=src\n' "$2"
    [ -n "$4" ] && printf "EXCEPTIONS='%s'\n" "$4"
  } > "$1/$ENVF"
}
EXC2='src/old.txt 2027-03-01
src/older.txt 2026-12-01'
# mkm -> committed harness whose file-size rule is mandatory, with two exceptions and an existing ADR
mkm() {
  local r; r="$(mk)"
  wenv "$r" 10 ENFORCEMENT_LEVEL=mandatory "$EXC2"
  printf '# ADR 0001\nFile size is mandatory.\n' > "$r/docs/adr/0001-file-size.md"
  (cd "$r" && git add -A && git commit -q -m mandatory)
  printf '%s\n' "$r"
}
r="$(mkm)"; run "$r"; [ $rc -eq 0 ]; check "mandatory: an unchanged mandatory rule passes" $?

r="$(mkm)"; wenv "$r" 50 ENFORCEMENT_LEVEL=mandatory "$EXC2"
run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | qgrep -F 'LIMIT raised from 10 to 50'; check "mandatory: raising LIMIT fails" $?
printf '%s\n' "$out" | qgrep -F 'Supersedes: <path of an existing ADR>' && printf '%s\n' "$out" | qgrep '^  guidance: .*mandatory.*superseding ADR'; check "mandatory: the guidance names the superseding-ADR route" $?
printf 'Raise %s to 50.\n' "$ENVF" > "$r/docs/adr/0002-raise.md"
run "$r"; [ $rc -eq 1 ]; check "mandatory: an ADR naming the file is not enough" $?
printf 'Raise %s to 50.\nSupersedes: docs/adr/0001-file-size.md\n' "$ENVF" > "$r/docs/adr/0002-raise.md"
run "$r"; [ $rc -eq 0 ] && printf '%s' "$out" | head -1 | qgrep '1 loosening(s)'; check "mandatory: a superseding ADR that names the file passes" $?
printf 'Raise %s to 50.\nSupersedes: docs/adr/0099-missing.md\n' "$ENVF" > "$r/docs/adr/0002-raise.md"
run "$r"; [ $rc -eq 1 ]; check "mandatory: Supersedes pointing at a missing ADR does not count" $?
printf 'Raise something else.\nSupersedes: docs/adr/0001-file-size.md\n' > "$r/docs/adr/0002-raise.md"
run "$r"; [ $rc -eq 1 ]; check "mandatory: a superseding ADR that does not name the file does not count" $?
printf 'Raise %s to 50.\nSupersedes: docs/adr/0002-raise.md\n' "$ENVF" > "$r/docs/adr/0002-raise.md"
run "$r"; [ $rc -eq 1 ]; check "mandatory: an ADR cannot supersede itself (the target must exist at the base)" $?

# a superseding ADR from an earlier commit does not cover a later loosening
r="$(mkm)"; wenv "$r" 50 ENFORCEMENT_LEVEL=mandatory "$EXC2"
printf 'Raise %s.\nSupersedes: docs/adr/0001-file-size.md\n' "$ENVF" > "$r/docs/adr/0002-raise.md"
(cd "$r" && git add -A && git commit -q -m adr2)
wenv "$r" 60 ENFORCEMENT_LEVEL=mandatory "$EXC2"
out="$(cd "$r" && KEEL_GUARD_BASE=HEAD bash scripts/sensors/guard.sh)"; rc=$?
[ $rc -eq 1 ]; check "mandatory: an earlier superseding ADR does not cover a new loosening" $?

# the same loosening on a ratchet rule keeps the ordinary ADR route
r="$(mk)"; wenv "$r" 50 "" ""; printf 'Raise %s.\n' "$ENVF" > "$r/docs/adr/0002-raise.md"
run "$r"; [ $rc -eq 0 ]; check "ratchet: an ADR naming the file still passes" $?

# EXCEPTIONS only shrink
r="$(mkm)"; wenv "$r" 10 ENFORCEMENT_LEVEL=mandatory "$EXC2
src/new.txt 2027-01-01"
run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | qgrep -F 'EXCEPTIONS gained src/new.txt'; check "mandatory: a new EXCEPTIONS line fails" $?
printf 'Allow src/new.txt in %s.\n' "$ENVF" > "$r/docs/adr/0002-exc.md"
run "$r"; [ $rc -eq 1 ]; check "mandatory: a new EXCEPTIONS line fails even with an ADR naming the file" $?
printf 'Allow src/new.txt in %s.\nSupersedes: docs/adr/0001-file-size.md\n' "$ENVF" > "$r/docs/adr/0002-exc.md"
run "$r"; [ $rc -eq 0 ]; check "mandatory: a new EXCEPTIONS line passes with a superseding ADR" $?

r="$(mkm)"; wenv "$r" 10 ENFORCEMENT_LEVEL=mandatory 'src/old.txt 2027-09-01
src/older.txt 2026-12-01'
run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | qgrep -F 'EXCEPTIONS deadline for src/old.txt moved later (2027-03-01 -> 2027-09-01)'; check "mandatory: moving a deadline later fails" $?
r="$(mkm)"; wenv "$r" 10 ENFORCEMENT_LEVEL=mandatory 'src/old.txt 2027-01-15
src/older.txt 2026-12-01'
run "$r"; [ $rc -eq 0 ]; check "mandatory: moving a deadline earlier passes" $?
r="$(mkm)"; wenv "$r" 10 ENFORCEMENT_LEVEL=mandatory 'src/old.txt 2027-03-01'
run "$r"; [ $rc -eq 0 ]; check "mandatory: removing an exception passes" $?
r="$(mkm)"; wenv "$r" 10 ENFORCEMENT_LEVEL=mandatory ""
run "$r"; [ $rc -eq 0 ]; check "mandatory: emptying EXCEPTIONS passes" $?
r="$(mkm)"; wenv "$r" 10 ENFORCEMENT_LEVEL=mandatory 'src/with space.txt 2027-03-01
src/older.txt 2026-12-01'
run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | qgrep -F 'EXCEPTIONS gained src/with space.txt'; check "mandatory: an exception path with a space is one path" $?

# the level itself
r="$(mkm)"; wenv "$r" 10 ENFORCEMENT_LEVEL=ratchet "$EXC2"
run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | qgrep -F 'ENFORCEMENT_LEVEL changed from mandatory to ratchet'; check "mandatory: mandatory -> ratchet fails" $?
printf 'Make it ratchet: %s\n' "$ENVF" > "$r/docs/adr/0002-ratchet.md"
run "$r"; [ $rc -eq 1 ]; check "mandatory: mandatory -> ratchet fails even with an ADR naming the file" $?
r="$(mkm)"; wenv "$r" 10 "" "$EXC2"
run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | qgrep -F 'ENFORCEMENT_LEVEL removed'; check "mandatory: deleting the ENFORCEMENT_LEVEL key fails" $?
r="$(mk)"; wenv "$r" 10 ENFORCEMENT_LEVEL=mandatory ""
run "$r"; [ $rc -eq 0 ]; check "ratchet -> mandatory is tightening and passes" $?
r="$(mkm)"; rm "$r/$ENVF"; printf 'Drop %s.\n' "$ENVF" > "$r/docs/adr/0002-drop.md"
run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | qgrep -F 'rule deleted'; check "mandatory: deleting the rule fails even with an ADR naming the file" $?
r="$(mkm)"; mkdir -p "$r/scripts/sensors/disabled"; (cd "$r" && git mv scripts/sensors/file-size.sh scripts/sensors/disabled/file-size.sh)
printf 'Disable scripts/sensors/file-size.sh.\n' > "$r/docs/adr/0002-off.md"
run "$r"; [ $rc -eq 1 ]; check "mandatory: disabling the rule's sensor fails even with an ADR naming it" $?

# a TSV baseline may not appear for a mandatory rule
r="$(mkm)"; printf 'src/big.txt\t20\n' >> "$r/.agents/baselines/file-size.tsv"
printf 'Baseline src/big.txt in .agents/baselines/file-size.tsv.\n' > "$r/docs/adr/0002-base.md"
run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | qgrep -F '.agents/baselines/file-size.tsv: src/big.txt 0 -> 20'; check "mandatory: a baseline row for a mandatory rule fails even with an ADR naming the file" $?
printf 'Baseline src/big.txt in .agents/baselines/file-size.tsv.\nSupersedes: docs/adr/0001-file-size.md\n' > "$r/docs/adr/0002-base.md"
run "$r"; [ $rc -eq 0 ]; check "mandatory: a baseline row for a mandatory rule passes with a superseding ADR naming the baseline" $?
r="$(mk)"; printf 'src/big.txt\t20\n' >> "$r/.agents/baselines/file-size.tsv"; printf 'Baseline .agents/baselines/file-size.tsv.\n' > "$r/docs/adr/0002-base.md"
run "$r"; [ $rc -eq 0 ]; check "ratchet: the same baseline row passes with an ADR naming the file" $?

# ===== type strictness (D44, F3d-2): tsconfig strict, mypy strict, pyright typeCheckingMode
# mkts PATH CONTENT -> the harness plus one committed config file
mkts() { local r; r="$(mk)"; mkdir -p "$r/$(dirname "$1")"; printf '%s\n' "$2" > "$r/$1"; (cd "$r" && git add -A && git commit -q -m cfg); printf '%s\n' "$r"; }
TSS='{
  // "strict": false
  "compilerOptions": { "target": "es2022", "strict": true, },
}'
r="$(mkts tsconfig.json "$TSS")"; run "$r"; [ $rc -eq 0 ]; check "type-strictness: an unchanged tsconfig passes (JSONC comments and trailing commas)" $?
printf '%s\n' "${TSS//\"strict\": true/\"strict\": false}" > "$r/tsconfig.json"; run "$r"
[ $rc -eq 1 ] && printf '%s' "$out" | qgrep -F 'tsconfig.json: type-strictness: strict true -> false'; check "type-strictness: tsconfig strict true -> false fails" $?
printf '# ADR 0011\nWe turn off strict in `tsconfig.json` while the migration runs.\n' > "$r/docs/adr/0011-strict.md"; run "$r"
[ $rc -eq 0 ] && printf '%s' "$out" | head -1 | qgrep '1 loosening(s)'; check "type-strictness: an ADR added in the change that names tsconfig.json passes" $?
r="$(mkts tsconfig.json "$TSS")"; printf '{ "compilerOptions": { "target": "es2022" } }\n' > "$r/tsconfig.json"; run "$r"
[ $rc -eq 1 ] && printf '%s' "$out" | qgrep -F 'tsconfig.json: type-strictness: strict true -> (unset)'; check "type-strictness: removing strict fails" $?
r="$(mkts tsconfig.json "$TSS")"; rm "$r/tsconfig.json"; run "$r"
[ $rc -eq 1 ] && printf '%s' "$out" | qgrep -F 'tsconfig.json: type-strictness: file removed'; check "type-strictness: deleting a strict tsconfig fails" $?
r="$(mkts tsconfig.json '{ "compilerOptions": { "strict": true, "noImplicitAny": true } }')"
printf '{ "compilerOptions": { "strict": true, "noImplicitAny": false } }\n' > "$r/tsconfig.json"; run "$r"
[ $rc -eq 1 ] && printf '%s' "$out" | qgrep -F 'type-strictness: noImplicitAny true -> false'; check "type-strictness: switching one strict flag off under strict fails" $?
r="$(mkts tsconfig.json '{ "compilerOptions": { "strict": true, "noImplicitAny": true } }')"
printf '{ "compilerOptions": { "strict": true } }\n' > "$r/tsconfig.json"; run "$r"; [ $rc -eq 0 ]; check "type-strictness: dropping a flag that strict already implies passes" $?
r="$(mkts tsconfig.json '{ "compilerOptions": { "strict": false } }')"
printf '{ "compilerOptions": { "strict": true } }\n' > "$r/tsconfig.json"; run "$r"; [ $rc -eq 0 ]; check "type-strictness: turning strict on passes" $?
r="$(mkts tsconfig.json '{ "compilerOptions": { "noUncheckedIndexedAccess": true } }')"
printf '{ "compilerOptions": { } }\n' > "$r/tsconfig.json"; run "$r"
[ $rc -eq 1 ] && printf '%s' "$out" | qgrep -F 'noUncheckedIndexedAccess true -> (unset)'; check "type-strictness: a flag outside the strict family is not implied by strict" $?
r="$(mkts packages/web/tsconfig.build.json "$TSS")"; sed -i.bak 's/"strict": true/"strict": false/' "$r/packages/web/tsconfig.build.json"; rm -f "$r/packages/web/tsconfig.build.json.bak"; run "$r"
[ $rc -eq 1 ] && printf '%s' "$out" | qgrep -F 'packages/web/tsconfig.build.json: type-strictness: strict true -> false'; check "type-strictness: a nested tsconfig.*.json is read too" $?
r="$(mkts tsconfig.json '{ "compilerOptions": { "target": "es5" } }')"; printf '{ "compilerOptions": { "target": "es2020", "strict": false } }\n' > "$r/tsconfig.json"; run "$r"
[ $rc -eq 0 ]; check "type-strictness: a tsconfig that was never strict is not loosened" $?

PYM='[project]
name = "x"

[tool.mypy]
strict = true
disallow_untyped_defs = true
'
r="$(mkts pyproject.toml "$PYM")"; run "$r"; [ $rc -eq 0 ]; check "type-strictness: unchanged pyproject passes" $?
sed -i.bak 's/^strict = true/strict = false/' "$r/pyproject.toml"; rm -f "$r/pyproject.toml.bak"; run "$r"
[ $rc -eq 1 ] && printf '%s' "$out" | qgrep -F 'pyproject.toml: type-strictness: mypy strict true -> false'; check "type-strictness: pyproject [tool.mypy] strict true -> false fails" $?
r="$(mkts pyproject.toml "$PYM")"; sed -i.bak '/^disallow_untyped_defs/d' "$r/pyproject.toml"; rm -f "$r/pyproject.toml.bak"; run "$r"
[ $rc -eq 0 ]; check "type-strictness: disallow_untyped_defs removed while strict stays passes (strict implies it)" $?
r="$(mkts mypy.ini $'[mypy]\ndisallow_untyped_defs = True')"; sed -i.bak 's/True/False/' "$r/mypy.ini"; rm -f "$r/mypy.ini.bak"; run "$r"
[ $rc -eq 1 ] && printf '%s' "$out" | qgrep -F 'mypy.ini: type-strictness: mypy disallow_untyped_defs true -> false'; check "type-strictness: mypy.ini disallow_untyped_defs True -> False fails" $?
r="$(mkts setup.cfg $'[mypy]\nstrict = True   # all of it')"; printf '[mypy]\npython_version = 3.12\n' > "$r/setup.cfg"; run "$r"
[ $rc -eq 1 ] && printf '%s' "$out" | qgrep -F 'setup.cfg: type-strictness: mypy strict true -> (unset)'; check "type-strictness: setup.cfg [mypy] strict removed fails" $?
r="$(mkts mypy.ini $'[mypy]\nstrict = False')"; printf '[mypy]\nstrict = True\n' > "$r/mypy.ini"; run "$r"; [ $rc -eq 0 ]; check "type-strictness: mypy strict False -> True passes" $?

PYR='[tool.pyright]
typeCheckingMode = "strict"
'
r="$(mkts pyproject.toml "$PYR")"; sed -i.bak 's/"strict"/"standard"/' "$r/pyproject.toml"; rm -f "$r/pyproject.toml.bak"; run "$r"
[ $rc -eq 1 ] && printf '%s' "$out" | qgrep -F 'pyproject.toml: type-strictness: pyright typeCheckingMode strict -> standard'; check "type-strictness: pyproject pyright strict -> standard fails" $?
r="$(mkts pyrightconfig.json '{ "typeCheckingMode": "strict" }')"; run "$r"; [ $rc -eq 0 ]; check "type-strictness: unchanged pyrightconfig passes" $?
printf '{ "typeCheckingMode": "basic" }\n' > "$r/pyrightconfig.json"; run "$r"
[ $rc -eq 1 ] && printf '%s' "$out" | qgrep -F 'pyrightconfig.json: type-strictness: pyright typeCheckingMode strict -> basic'; check "type-strictness: pyrightconfig.json strict -> basic fails" $?
printf 'We lower typeCheckingMode in pyrightconfig.json.\n' > "$r/docs/adr/0012.md"; run "$r"; [ $rc -eq 0 ]; check "type-strictness: an ADR naming pyrightconfig.json passes" $?
r="$(mkts pyrightconfig.json '{ "typeCheckingMode": "strict" }')"; printf '{ }\n' > "$r/pyrightconfig.json"; run "$r"
[ $rc -eq 1 ] && printf '%s' "$out" | qgrep -F 'pyright typeCheckingMode strict -> standard'; check "type-strictness: removing the mode falls back to standard, which is lower than strict" $?
r="$(mkts pyrightconfig.json '{ "typeCheckingMode": "basic" }')"; printf '{ "typeCheckingMode": "strict" }\n' > "$r/pyrightconfig.json"; run "$r"; [ $rc -eq 0 ]; check "type-strictness: basic -> strict passes" $?
r="$(mkts pyrightconfig.json '{ "typeCheckingMode": "basic" }')"; printf '{ }\n' > "$r/pyrightconfig.json"; run "$r"; [ $rc -eq 0 ]; check "type-strictness: basic -> unset (standard) passes" $?
r="$(mkts pyrightconfig.json '{ "typeCheckingMode": "basic" }')"; printf '{ "typeCheckingMode": "off" }\n' > "$r/pyrightconfig.json"; run "$r"
[ $rc -eq 1 ] && printf '%s' "$out" | qgrep -F 'pyright typeCheckingMode basic -> off'; check "type-strictness: basic -> off fails" $?
finish
