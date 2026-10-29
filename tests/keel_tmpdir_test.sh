#!/usr/bin/env bash
# H1: no script may write outside the repository, or give a wrong verdict, when mktemp fails.
# Per script: (1) TMPDIR unusable -> the verdict is the one a normal TMPDIR gives, from a
# directory under .agents/run/tmp/ that is removed afterwards; (2) no temp directory at all ->
# the verdict the plan's table names; (3) structure: no "$tmp/..." can expand with an empty tmp.
set -uo pipefail
. "$(dirname "$0")/keel_helpers.sh"
RS=assets/core/sensors/rules
SD=assets/core/sensors
NOTMP="/nonexistent-keel-$$"
NOMSG='no writable temp directory (TMPDIR or .agents/run/tmp/)'
W="$(mktemp -d)"; _keel_tmps="$_keel_tmps $W"
TAB="$(printf '\t')"

commit() { (cd "$1" && git add -A && git commit -q -m c); }
nlines() { seq 1 "$1" | sed 's/.*/x/'; }
line1() { printf '%s\n' "$1" | head -1; }
# leftovers REPO -> number of entries under REPO/.agents/run/tmp (0 when the directory is absent)
leftovers() { if [ -d "$1/.agents/run/tmp" ]; then find "$1/.agents/run/tmp" -mindepth 1 | wc -l | tr -d ' '; else echo 0; fi; }
# same A B C D -> 0 when A equals C and B equals D
same() { [ "$1" = "$3" ] && [ "$2" = "$4" ]; }
# cleanrun REPO -> 0 when the fallback directory was used (it exists) and nothing is left in it
cleanrun() { [ -d "$1/.agents/run/tmp" ] && [ "$(leftovers "$1")" = 0 ]; }
# nolefts REPO -> 0 when nothing is left under .agents/run/tmp
nolefts() { [ "$(leftovers "$1")" = 0 ]; }
# blockrun REPO -> .agents/run is a regular file, so mkdir -p .agents/run/tmp must fail
blockrun() { rm -rf "$1/.agents/run"; mkdir -p "$1/.agents"; : > "$1/.agents/run"; }

mk() { # a repo with the libs installed
  local r; r="$(new_repo)"
  install_asset "$r" assets/core/lib/baseline.sh scripts/lib/baseline.sh
  install_asset "$r" assets/core/lib/envparse.sh scripts/lib/envparse.sh
  install_asset "$r" assets/core/lib/junit.sh scripts/lib/junit.sh
  mkdir -p "$r/.agents/rules" "$r/.agents/baselines" "$r/src"
  printf '%s\n' "$r"
}

# scase NAME REPO SCRIPT EXPECTED_RC KIND [ENV...]
#   KIND: sensor (case 2 -> exit 2, skip) or guard (case 2 -> exit 1, fail with guidance)
# Runs the script three ways in REPO: normal TMPDIR, unusable TMPDIR, no temp directory at all.
scase() {
  local name="$1" r="$2" s="$3" want="$4" kind="$5"; shift 5
  local o0 rc0 o1 rc1 e1 o2 rc2 e2 st l0 l1
  o0="$(cd "$r" && env "$@" bash "$s" 2>/dev/null)"; rc0=$?
  [ "$rc0" -eq "$want" ] && ! line1 "$o0" | grep -q "${TAB}skip${TAB}"; check "$name: normal TMPDIR reaches the verdict (rc $want)" $?
  rm -rf "$r/.agents/run/tmp"
  o1="$(cd "$r" && env TMPDIR="$NOTMP" "$@" bash "$s" 2>"$W/err1")"; rc1=$?; e1="$(cat "$W/err1")"
  l0="$(line1 "$o0")"; l1="$(line1 "$o1")"
  same "$rc1" "$l1" "$rc0" "$l0"; check "$name: unusable TMPDIR gives the same verdict" $?
  [ -z "$e1" ] || printf '%s\n' "$e1" | head -3 | sed 's/^/    stderr: /'
  ! printf '%s\n' "$e1" | grep -q 'mktemp'; check "$name: unusable TMPDIR prints no mktemp error" $?
  cleanrun "$r"; check "$name: fallback used and nothing left in .agents/run/tmp" $?
  blockrun "$r"
  o2="$(cd "$r" && env TMPDIR="$NOTMP" "$@" bash "$s" 2>"$W/err2")"; rc2=$?; e2="$(cat "$W/err2")"
  st="$(line1 "$o0" | cut -f1,2)"
  if [ "$kind" = guard ]; then
    [ "$rc2" -eq 1 ] && [ "$(line1 "$o2")" = "$(printf '%s\tfail\t%s' "$st" "$NOMSG")" ] \
      && printf '%s\n' "$o2" | grep -qF '  guidance: make TMPDIR writable or let the gate create .agents/run/tmp/; never delete this sensor'
  else
    [ "$rc2" -eq 2 ] && [ "$(line1 "$o2")" = "$(printf '%s\tskip\t%s' "$st" "$NOMSG")" ]
  fi
  check "$name: no temp directory at all -> $kind verdict" $?
  ! printf '%s\n' "$e2" | grep -q 'mktemp'; check "$name: no temp directory prints no mktemp error" $?
}

# ---------------------------------------------------------------- rule sensors
r="$(mk)"; install_asset "$r" "$RS/file-size.sh" scripts/sensors/file-size.sh
printf "LIMIT=5\nINCLUDE='src'\n" > "$r/.agents/rules/file-size.env"; nlines 7 > "$r/src/a.ts"; nlines 3 > "$r/src/s.ts"; commit "$r"
scase file-size "$r" scripts/sensors/file-size.sh 1 sensor
rm -rf "$r/.agents/run"; o="$(cd "$r" && TMPDIR="$NOTMP" bash scripts/sensors/file-size.sh 2>&1)"
printf '%s\n' "$o" | head -1 | grep -q '^file-size	heuristic	fail	1 of 2 files over 5 lines'; check "file-size: an oversize file still fails under an unusable TMPDIR" $?
printf '%s\n' "$o" | grep -qF '  src/a.ts: 7 lines (allowed 5)'; check "file-size: and names the file" $?

r="$(mk)"; install_asset "$r" "$RS/folder-layout.sh" scripts/sensors/folder-layout.sh
mkdir -p "$r/src/app" "$r/src/misc"; echo 1 > "$r/src/app/x.ts"; echo 1 > "$r/src/misc/y.ts"
printf "INCLUDE='src'\nALLOWED='src/app/*'\n" > "$r/.agents/rules/folder-layout.env"; commit "$r"
scase folder-layout "$r" scripts/sensors/folder-layout.sh 1 sensor

r="$(mk)"; install_asset "$r" "$RS/architecture-grep.sh" scripts/sensors/architecture-grep.sh
cat > "$r/.agents/rules/architecture.env" <<'ENV'
STYLE=hexagonal
LANG=java
BASE=com.acme
LAYERS='domain|src/main/java/com/acme/domain|com.acme.domain||domainModels
adapter|src/main/java/com/acme/adapter|com.acme.adapter|domain|adapter'
FORBIDDEN='domain|org.springframework'
ENV
J="$r/src/main/java/com/acme"; mkdir -p "$J/domain" "$J/adapter"
printf 'package com.acme.domain;\nimport com.acme.adapter.X;\nimport org.springframework.stereotype.Service;\n' > "$J/domain/Foo.java"
printf 'package com.acme.adapter;\npublic class X {}\n' > "$J/adapter/X.java"; commit "$r"
scase architecture-grep "$r" scripts/sensors/architecture-grep.sh 1 sensor

r="$(mk)"; install_asset "$r" "$RS/code-language.sh" scripts/sensors/code-language.sh
mkdir -p "$r/scripts/sensors/stoplists"; cp "$KEEL/$RS/stoplists/pt.txt" "$r/scripts/sensors/stoplists/pt.txt"
printf "INCLUDE='src'\n" > "$r/.agents/rules/code-language.env"
printf 'const nomeUsuario = 1; // calcula o valor\n' > "$r/src/a.ts"; commit "$r"
scase code-language "$r" scripts/sensors/code-language.sh 1 sensor

r="$(mk)"; install_asset "$r" "$RS/test-presence.sh" scripts/sensors/test-presence.sh
cat > "$r/.agents/rules/testing-strategy.env" <<'ENV'
INCLUDE='src/main'
MAPPINGS='^src/main/java/(.*)\.java$|src/test/java/\1Test.java'
ENV
mkdir -p "$r/src/main/java/a"; echo c > "$r/src/main/java/a/Bar.java"; commit "$r"
scase test-presence "$r" scripts/sensors/test-presence.sh 1 sensor SCOPE=src/main/java/a/Bar.java

r="$(mk)"; install_asset "$r" "$RS/architecture.sh" scripts/sensors/architecture.sh
printf "STYLE=hexagonal\nLANG=java\nBASE=com.acme\n" > "$r/.agents/rules/architecture.env"
use_stub "$r" gradlew gradlew; commit "$r"
scase architecture "$r" scripts/sensors/architecture.sh 0 sensor STUB_EXIT=0

r="$(mk)"; mkdir -p "$r/scripts/sensors/slow"; install_asset "$r" "$RS/slow/mutation.sh" scripts/sensors/slow/mutation.sh
printf "MUTATION_MIN_SCORE=70\n" > "$r/.agents/rules/testing-strategy.env"
mkdir -p "$r/src/main/java/a"; echo c > "$r/src/main/java/a/Foo.java"; use_stub "$r" pitest-maven mvnw; commit "$r"
scase mutation "$r" scripts/sensors/slow/mutation.sh 1 sensor SCOPE=src/main/java/a/Foo.java STUB_OUT="Generated 10 mutations Killed 6 (60%)" STUB_EXIT=0

r="$(mk)"; mkdir -p "$r/scripts/sensors/slow" "$r/coverage"; install_asset "$r" "$RS/slow/diff-coverage.sh" scripts/sensors/slow/diff-coverage.sh
printf "DIFF_COVERAGE_MIN=80\n" > "$r/.agents/rules/testing-strategy.env"; cp "$FIXTURES/coverage/lcov.info" "$r/coverage/lcov.info"
printf 'l1\nl2\nl3\nl4\n' > "$r/src/a.ts"; commit "$r"
sed -i.bak 's|^CMD=.*|CMD=(true)|' "$r/scripts/sensors/slow/diff-coverage.sh"; rm -f "$r/scripts/sensors/slow/diff-coverage.sh.bak"
sed -i.bak '4s/.*/l4 changed/' "$r/src/a.ts"; rm -f "$r/src/a.ts.bak"
scase diff-coverage "$r" scripts/sensors/slow/diff-coverage.sh 1 sensor SCOPE=src/a.ts

# ---------------------------------------------------------------- stack sensors
r="$(mk)"; install_asset "$r" "$SD/jvm/lint.sh" scripts/sensors/lint.sh
mkdir -p "$r/bin" "$r/src/main/kotlin/a"; use_stub "$r" ktlint bin/ktlint; echo c > "$r/src/main/kotlin/a/A.kt"; commit "$r"
OUTK="$r/src/main/kotlin/a/A.kt:3:5: Unexpected blank line (no-blank-line)"
scase jvm/lint "$r" scripts/sensors/lint.sh 1 sensor PATH="$r/bin:$PATH" STUB_EXIT=1 STUB_OUT="$OUTK"

r="$(mk)"; install_asset "$r" "$SD/jvm/tests.sh" scripts/sensors/tests.sh
use_stub "$r" gradlew gradlew; commit "$r"
scase jvm/tests "$r" scripts/sensors/tests.sh 0 sensor STUB_EXIT=0

r="$(mk)"; install_asset "$r" "$SD/python/lint.sh" scripts/sensors/lint.sh
mkdir -p "$r/pkg"; use_stub "$r" ruff .venv/bin/ruff; echo 1 > "$r/pkg/a.py"; commit "$r"
JSON="[{\"filename\":\"$r/pkg/a.py\",\"code\":\"E1\"},{\"filename\":\"$r/pkg/a.py\",\"code\":\"E2\"}]"
scase python/lint "$r" scripts/sensors/lint.sh 1 sensor STUB_EXIT=1 STUB_OUT="$JSON"

r="$(mk)"; install_asset "$r" "$SD/typescript/lint.sh" scripts/sensors/lint.sh
use_stub "$r" eslint node_modules/.bin/eslint; echo 1 > "$r/src/a.ts"; commit "$r"
JSON="[{\"filePath\":\"$r/src/a.ts\",\"messages\":[{\"ruleId\":\"no-console\"},{\"ruleId\":\"no-unused-vars\"}]}]"
scase typescript/lint "$r" scripts/sensors/lint.sh 1 sensor STUB_EXIT=1 STUB_OUT="$JSON"

# ---------------------------------------------------------------- guard
mkg() { # the harness of keel_guard_test.sh
  local g; g="$(new_repo)"
  install_asset "$g" assets/core/lib/baseline.sh scripts/lib/baseline.sh
  install_asset "$g" assets/core/lib/envparse.sh scripts/lib/envparse.sh
  install_asset "$g" assets/core/sensors/common/guard.sh scripts/sensors/guard.sh
  mkdir -p "$g/.agents/rules" "$g/.agents/baselines" "$g/src" "$g/docs/adr"
  printf 'schema_version: 2\n' > "$g/.agents/state.yml"
  printf '# measured_at: 2026-10-24 review_by: 2027-04-24\n' > "$g/.agents/baselines/file-size.tsv"
  commit "$g"
  printf '%s\n' "$g"
}
r="$(mkg)"
scase guard-clean "$r" scripts/sensors/guard.sh 0 guard KEEL_GUARD_BASE=HEAD
rm -rf "$r/.agents/run"
o="$(cd "$r" && TMPDIR="$NOTMP" KEEL_GUARD_BASE=HEAD bash scripts/sensors/guard.sh 2>&1)"
printf '%s\n' "$o" | head -1 | grep -q '^guard	security	pass	No harness file loosened since '; check "guard: no change passes under an unusable TMPDIR" $?
r="$(mkg)"; printf 'src/big.txt\t20\n' >> "$r/.agents/baselines/file-size.tsv"
scase guard-loosened "$r" scripts/sensors/guard.sh 1 guard KEEL_GUARD_BASE=HEAD
rm -rf "$r/.agents/run"
o="$(cd "$r" && TMPDIR="$NOTMP" KEEL_GUARD_BASE=HEAD bash scripts/sensors/guard.sh 2>&1)"
printf '%s\n' "$o" | head -1 | grep -q '^guard	security	fail	1 loosening(s) of the harness since '; check "guard: a grown baseline fails with '1 loosening(s)' under an unusable TMPDIR" $?
printf '%s\n' "$o" | grep -qF '.agents/baselines/file-size.tsv: src/big.txt 0 -> 20'; check "guard: and names the row" $?

# ---------------------------------------------------------------- baseline_compare
r="$(mk)"; printf 'a\t3\n' > "$W/counts"
bc() { (cd "$r" && . scripts/lib/baseline.sh && TMPDIR="$NOTMP" baseline_compare "$r/.agents/baselines/none.tsv" "$W/counts" 2>"$W/bcerr"); }
bo="$(bc)"; brc=$?
[ "$brc" -eq 1 ] && [ "$bo" = "$(printf 'a\t3\t0')" ] && ! grep -q mktemp "$W/bcerr" && cleanrun "$r"
check "baseline_compare: an empty baseline works from .agents/run/tmp when TMPDIR is unusable" $?
blockrun "$r"; bo="$(bc)"; brc=$?
[ "$brc" -eq 2 ] && [ -z "$bo" ] && ! grep -q mktemp "$W/bcerr"; check "baseline_compare: returns 2 when no temp file can be made" $?

# ---------------------------------------------------------------- harness-check
r="$(new_repo)"
install_asset "$r" assets/core/harness-check.sh scripts/harness-check.sh
mkdir -p "$r/.agents"; printf 'schema_version: 2\nlayers: { hook: not_installed }\n' > "$r/.agents/state.yml"
printf '.agents/run/\n' > "$r/.gitignore"; { echo '# AGENTS.md'; nlines 129; } > "$r/AGENTS.md"; commit "$r"
hc() { (cd "$r" && env "$@" bash scripts/harness-check.sh 2>"$W/hcerr"); }
o0="$(hc KEEL_TODAY=2026-10-29)"; rc0=$?
printf '%s\n' "$o0" | grep -q "^warn${TAB}agents-size${TAB}AGENTS.md${TAB}130 lines"; check "harness-check: a 130-line AGENTS.md reports agents-size (normal TMPDIR)" $?
o1="$(hc KEEL_TODAY=2026-10-29 TMPDIR="$NOTMP")"; rc1=$?
same "$rc1" "$o1" "$rc0" "$o0"; check "harness-check: unusable TMPDIR gives the same report and exit code" $?
printf '%s\n' "$o1" | grep -q "^warn${TAB}agents-size${TAB}AGENTS.md${TAB}130 lines"; check "harness-check: agents-size is still reported under an unusable TMPDIR" $?
! grep -q mktemp "$W/hcerr"; check "harness-check: unusable TMPDIR prints no mktemp error" $?
cleanrun "$r"; check "harness-check: fallback used and nothing left in .agents/run/tmp" $?
blockrun "$r"
o2="$(hc KEEL_TODAY=2026-10-29 TMPDIR="$NOTMP")"; rc2=$?
hcmsg="$(cat "$W/hcerr")"
same "$rc2" "$hcmsg" 3 "harness-check: $NOMSG" && [ -z "$o2" ]; check "harness-check: no temp directory -> exit 3 and a message on stderr" $?
sed -n 1,12p "$KEEL/assets/core/harness-check.sh" | grep -q '^# Exit .*3 '; check "harness-check: header documents exit 3" $?

# ---------------------------------------------------------------- measure.sh (runs from the plugin)
r="$(new_repo)"; nlines 7 > "$r/a.ts"; nlines 3 > "$r/b.ts"; commit "$r"
ms() { (cd "$r" && env "$@" bash "$KEEL/scripts/measure.sh" file-size 2>"$W/mserr"); }
o0="$(ms)"; rc0=$?
o1="$(ms TMPDIR="$NOTMP")"; rc1=$?
[ "$rc0" -eq 0 ] && [ "$rc1" -eq 0 ] && [ "$o1" = "$o0" ] && printf '%s\n' "$o1" | grep -qx 'files 3'; check "measure.sh: unusable TMPDIR gives the same measurements" $?
! grep -q mktemp "$W/mserr"; check "measure.sh: unusable TMPDIR prints no mktemp error" $?
nolefts "$r"; check "measure.sh: nothing left in .agents/run/tmp" $?
blockrun "$r"
o2="$(ms TMPDIR="$NOTMP")"; rc2=$?
[ "$rc2" -eq 1 ] && [ -z "$o2" ] && grep -qF "$NOMSG" "$W/mserr" && ! grep -q mktemp "$W/mserr"; check "measure.sh: no temp directory -> exit 1 and a message on stderr" $?

# ---------------------------------------------------------------- structure: no "$tmp/..." with an empty tmp
FILES="assets/core/harness-check.sh assets/core/lib/baseline.sh assets/core/sensors/common/guard.sh
assets/core/sensors/jvm/lint.sh assets/core/sensors/jvm/tests.sh assets/core/sensors/python/lint.sh
assets/core/sensors/typescript/lint.sh assets/core/sensors/rules/architecture.sh
assets/core/sensors/rules/architecture-grep.sh assets/core/sensors/rules/code-language.sh
assets/core/sensors/rules/file-size.sh assets/core/sensors/rules/folder-layout.sh
assets/core/sensors/rules/test-presence.sh assets/core/sensors/rules/slow/diff-coverage.sh
assets/core/sensors/rules/slow/mutation.sh scripts/measure.sh"
nfiles=0
for f in $FILES; do
  nfiles=$((nfiles + 1))
  # every mktemp is inside the keel_tmpdir / keel_tmpfile function definition
  ! grep -n mktemp "$KEEL/$f" | grep -vE ':[[:space:]]*keel_tmp(dir|file)\(\)'; check "$f: mktemp only inside keel_tmpdir/keel_tmpfile" $?
  # every tmp/since/empty assignment is followed (within 3 lines) by an emptiness check on the same variable
  awk '
    match($0, /(^|[^a-z_])(tmp|since|empty)="\$\(keel_tmp(dir|file)\)"/) {
      n = substr($0, RSTART, RLENGTH); sub(/^[^a-z]/, "", n); sub(/=.*/, "", n); want = n; left = 3; next }
    left > 0 { if (index($0, "-z \"$" want "\"") > 0) left = 0; else { left--; if (left == 0) bad = 1 } }
    END { exit bad }' "$KEEL/$f"; check "$f: every temp assignment is followed by an emptiness check" $?
  # and a temp assignment exists at all (the file really uses the pattern)
  grep -qE '(tmp|since|empty)="\$\(keel_tmp(dir|file)\)"' "$KEEL/$f"; check "$f: uses keel_tmpdir/keel_tmpfile" $?
done
[ "$nfiles" -eq 16 ]; check "structure covers every call site ($nfiles files)" $?
! grep -rn mktemp "$KEEL/assets" "$KEEL/scripts" | grep -vE ':[[:space:]]*keel_tmp(dir|file)\(\)'; check "grep mktemp over assets/ and scripts/ lists only the new pattern" $?
finish
