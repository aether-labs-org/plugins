#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/keel_helpers.sh"
RS="assets/core/sensors/rules"

# mk -> repo with the baseline lib installed
mk() {
  local r; r="$(new_repo)"
  install_asset "$r" assets/core/lib/baseline.sh scripts/lib/baseline.sh
  install_asset "$r" assets/core/lib/envparse.sh scripts/lib/envparse.sh
  mkdir -p "$r/.agents/rules" "$r/.agents/baselines" "$r/src"
  printf '%s\n' "$r"
}
# put REPO NAME -> installs a rule sensor as scripts/sensors/NAME.sh
put() { install_asset "$1" "$RS/$2.sh" "scripts/sensors/$2.sh"; }
run() { # run REPO SENSOR [env...] -> out, rc
  local r="$1" s="$2"; shift 2
  out="$(cd "$r" && env "$@" bash "scripts/sensors/$s.sh" 2>&1)"; rc=$?
}
nlines() { seq 1 "$1" | sed 's/.*/x/'; }
commit() { (cd "$1" && git add -A && git commit -q -m c); }

structure() { # structure <name>
  local f="$KEEL/$RS/$1.sh"
  [ -f "$f" ]; check "$1 exists" $?
  sed -n 2p "$f" | grep -q '^# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.$'; check "$1 managed header" $?
  grep -q '^# --- keel:repo-specific begin ---$' "$f" && grep -q '^# --- keel:repo-specific end ---$' "$f"; check "$1 markers" $?
  grep -q "^id=$(basename "$1")\$" "$f"; check "$1 id equals file name" $?
}

# ================= file-size
structure file-size
r="$(mk)"; put "$r" file-size
run "$r" file-size; [ $rc -eq 2 ] && printf '%s\n' "$out" | head -1 | grep -q 'skip	.*no .agents/rules/file-size.env - run the rules skill'; check "file-size: no env -> skip" $?
printf "LIMIT=5\nINCLUDE='src'\n" > "$r/.agents/rules/file-size.env"
nlines 7 > "$r/src/a.ts"; nlines 3 > "$r/src/small.ts"; commit "$r"
run "$r" file-size
[ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | grep -q '^file-size	heuristic	fail	' && printf '%s\n' "$out" | grep -qF '  src/a.ts: 7 lines (allowed 5)'; check "file-size: oversize without baseline fails" $?
printf '%s\n' "$out" | grep -qF '  guidance: Split the files above by responsibility so each part stays within 5 lines (docs/conventions.md#file-size). Do not raise .agents/baselines/file-size.tsv or LIMIT in .agents/rules/file-size.env.'; check "file-size: guidance text" $?
printf '# measured_at: 2026-10-20 review_by: 2027-04-20\nsrc/a.ts\t7\n' > "$r/.agents/baselines/file-size.tsv"
run "$r" file-size; [ $rc -eq 0 ] && printf '%s\n' "$out" | head -1 | grep -q '^file-size	heuristic	pass	2 files checked, 0 over 5 lines (1 baselined)\.$'; check "file-size: baselined passes" $?
nlines 8 > "$r/src/a.ts"; run "$r" file-size; [ $rc -eq 1 ] && printf '%s\n' "$out" | grep -qF 'src/a.ts: 8 lines (allowed 7)'; check "file-size: growth past baseline fails" $?
nlines 4 > "$r/src/a.ts"; run "$r" file-size; [ $rc -eq 0 ]; check "file-size: shrink below limit passes" $?
rm "$r/.agents/baselines/file-size.tsv"; nlines 7 > "$r/src/my file ação.ts"; rm "$r/src/a.ts"
run "$r" file-size; printf '%s\n' "$out" | grep -qF '  src/my file ação.ts: 7 lines (allowed 5)'; check "file-size: spaces and non-ASCII path (RF1)" $?
printf 'LIMIT=5\r\nINCLUDE='"'"'src'"'"'\r\n' > "$r/.agents/rules/file-size.env"
run "$r" file-size; printf '%s\n' "$out" | grep -qF 'allowed 5)'; check "file-size: CRLF env parses (RF4)" $?
nlines 7 > "$r/src/a.ts"; nlines 7 > "$r/src/b.ts"
run "$r" file-size SCOPE=src/b.ts
printf '%s\n' "$out" | grep -qF 'src/b.ts: 7' && ! printf '%s\n' "$out" | grep -qF 'src/a.ts'; check "file-size: SCOPE restricts the check" $?
run "$r" file-size KEEL_MEASURE=1 KEEL_TODAY=2026-10-20
[ "$(printf '%s\n' "$out" | head -1)" = "# measured_at: 2026-10-20 review_by: 2027-04-20" ] && printf '%s\n' "$out" | grep -qx "$(printf 'src/a.ts\t7')"; check "file-size: KEEL_MEASURE output" $?
printf "LIMIT=5\nINCLUDE='src'\nEXCLUDE='src/b.ts'\n" > "$r/.agents/rules/file-size.env"
run "$r" file-size KEEL_MEASURE=1; ! printf '%s\n' "$out" | grep -q 'src/b.ts'; check "file-size: EXCLUDE honoured" $?
run "$r" file-size RULE_ENV="$r/nope.env"; [ $rc -eq 2 ]; check "file-size: RULE_ENV override missing -> skip" $?

# ================= folder-layout
structure folder-layout
r="$(mk)"; put "$r" folder-layout
mkdir -p "$r/src/app" "$r/src/domain" "$r/src/misc" "$r/src/other"; echo 1 > "$r/src/app/x.ts"; echo 1 > "$r/src/domain/d.ts"; echo 1 > "$r/src/misc/y.ts"
commit "$r"
cat > "$r/.agents/rules/folder-layout.env" <<'ENV'
INCLUDE='src'
ALLOWED='src/app/*
src/domain/*'
ENV
run "$r" folder-layout
[ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | grep -q '^folder-layout	correctness	fail	' && printf '%s\n' "$out" | grep -qF '  src/misc/y.ts'; check "folder-layout: misplaced file reported" $?
printf '%s\n' "$out" | grep -qF 'docs/architecture.md#folder-layout' && printf '%s\n' "$out" | grep -qF 'ever widen ALLOWED'; check "folder-layout: guidance" $?
printf '# measured_at: 2026-10-20 review_by: 2027-04-20\nsrc/misc/y.ts\t1\n' > "$r/.agents/baselines/folder-layout.tsv"
run "$r" folder-layout; [ $rc -eq 0 ]; check "folder-layout: baselined passes" $?
echo 1 > "$r/src/other/z.ts"; run "$r" folder-layout; [ $rc -eq 1 ] && printf '%s\n' "$out" | grep -qF 'src/other/z.ts'; check "folder-layout: new misplaced file fails" $?
run "$r" folder-layout SCOPE=src/app/x.ts; [ $rc -eq 0 ]; check "folder-layout: SCOPE honoured" $?
run "$r" folder-layout KEEL_MEASURE=1 KEEL_TODAY=2026-10-20; printf '%s\n' "$out" | grep -qx "$(printf 'src/misc/y.ts\t1')"; check "folder-layout: KEEL_MEASURE" $?

# ================= architecture (native engines)
structure architecture
structure architecture-grep
r="$(mk)"; put "$r" architecture
run "$r" architecture; [ $rc -eq 2 ]; check "architecture: no env -> skip" $?
printf "STYLE=hexagonal\nLANG=java\nBASE=com.acme\n" > "$r/.agents/rules/architecture.env"
run "$r" architecture; [ $rc -eq 2 ] && printf '%s\n' "$out" | head -1 | grep -q 'skip'; check "archunit: tool absent -> skip" $?
use_stub "$r" gradlew gradlew
VIOL=$'Architecture Violation [Priority: MEDIUM] - Rule \'x\' was violated (2 times):\nMethod <a.A.m()> calls <b.B.n()> in (A.java:3)\nMethod <a.A.o()> calls <b.B.n()> in (A.java:9)\nArchitecture Violation [Priority: MEDIUM] - Rule \'y\' was violated (1 times):\nField <a.A.f> has type <b.B> in (A.java:2)'
run "$r" architecture STUB_EXIT=1 STUB_OUT="$VIOL"
[ $rc -eq 1 ] && [ "$(printf '%s\n' "$out" | head -1)" = "$(printf 'architecture\tcorrectness\tfail\t3 architecture violation(s) (archunit).')" ]; check "archunit: 2+1 violations summed" $?
[ "$(printf '%s\n' "$out" | grep -c '^  [A-Z]')" -ge 1 ] && printf '%s\n' "$out" | grep -q '^  guidance: Move the dependency behind a port'; check "archunit: details + guidance" $?
run "$r" architecture STUB_EXIT=0; [ $rc -eq 0 ] && printf '%s\n' "$out" | head -1 | grep -q '^architecture	correctness	pass	'; check "archunit: pass" $?
run "$r" architecture KEEL_MEASURE=1; [ $rc -eq 0 ] && [ "$out" = "# native baseline - see docs/architecture.md#architecture" ]; check "architecture: KEEL_MEASURE" $?
grep -q "Move the dependency behind a port owned by the inner layer, or move the code to the layer allowed to depend on it (docs/architecture.md#architecture). Do not edit the generated rule or the native baseline to make this pass." "$r/scripts/sensors/architecture.sh"; check "architecture: guidance text" $?
# archunit through a quiet Gradle run: the violation text comes from the JUnit report
JX="$(cd "$(dirname "$0")" && pwd)/fixtures/keel/junit"
r="$(mk)"; put "$r" architecture; install_asset "$r" assets/core/lib/junit.sh scripts/lib/junit.sh
printf "STYLE=hexagonal\nLANG=java\nBASE=com.acme\n" > "$r/.agents/rules/architecture.env"
cp "$(cd "$(dirname "$0")" && pwd)/fixtures/keel/stubs/gradle-junit" "$r/gradlew"; chmod +x "$r/gradlew"
run "$r" architecture STUB_EXIT=1 STUB_OUT="4 tests completed, 1 failed" STUB_XML="$JX/archunit-failure.xml"
[ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | grep -q '1 architecture violation(s) (archunit)' && printf '%s\n' "$out" | grep -qF '  Field <com.acme.application.ChargeFee.leak> has type <com.acme.adapter.web.FeeController>'; check "archunit: violation read from the JUnit report of a quiet build" $?
! printf '%s\n' "$out" | grep -q "^  domain models"; check "archunit: details are the violations, not the rule description" $?
# depcruise
r="$(mk)"; put "$r" architecture; printf "STYLE=layered\nLANG=ts\nBASE=src\n" > "$r/.agents/rules/architecture.env"
sed -i 's|^ENGINE="archunit"|ENGINE="depcruise"|; s|^CMD=.*|CMD=(node_modules/.bin/depcruise src --output-type err)|' "$r/scripts/sensors/architecture.sh"
run "$r" architecture; [ $rc -eq 2 ]; check "depcruise: tool absent -> skip" $?
use_stub "$r" depcruise node_modules/.bin/depcruise
run "$r" architecture STUB_EXIT=1 STUB_OUT=$'  error no-domain-to-infra: src/domain/a.ts -> src/infra/b.ts\n  error no-domain-to-infra: src/domain/c.ts -> src/infra/b.ts\n\nx 2 dependency violations (2 errors, 0 warnings)'
[ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | grep -q '2 architecture violation(s) (depcruise)'; check "depcruise: 2 error lines" $?
run "$r" architecture STUB_EXIT=0; [ $rc -eq 0 ]; check "depcruise: pass" $?
sed -i 's|^CMD=.*|CMD=(node_modules/.bin/depcruise src --ignore-known .agents/baselines/depcruise-known-violations.json --output-type err)|' "$r/scripts/sensors/architecture.sh"
: > "$r/stub.log"; run "$r" architecture STUB_EXIT=0 STUB_LOG="$r/stub.log"
grep -qx -- 'src --output-type err' "$r/stub.log"; check "depcruise: --ignore-known dropped while the known-violations file is missing" $?
mkdir -p "$r/.agents/baselines"; echo '[]' > "$r/.agents/baselines/depcruise-known-violations.json"
: > "$r/stub.log"; run "$r" architecture STUB_EXIT=0 STUB_LOG="$r/stub.log"
grep -qx -- 'src --ignore-known .agents/baselines/depcruise-known-violations.json --output-type err' "$r/stub.log"; check "depcruise: --ignore-known kept once the file exists" $?
run "$r" architecture STUB_EXIT=1 STUB_OUT="ERROR: Can't open config file"
[ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | grep -q 'depcruise exited 1 without reporting a violation'; check "depcruise: a tool error is not reported as a violation" $?
# importlinter
r="$(mk)"; put "$r" architecture; printf "STYLE=layered\nLANG=python\nBASE=acme\n" > "$r/.agents/rules/architecture.env"
sed -i 's|^ENGINE="archunit"|ENGINE="importlinter"|; s|^CMD=.*|CMD=(.venv/bin/lint-imports)|' "$r/scripts/sensors/architecture.sh"
run "$r" architecture; [ $rc -eq 2 ]; check "importlinter: tool absent -> skip" $?
use_stub "$r" lint-imports .venv/bin/lint-imports
run "$r" architecture STUB_EXIT=1 STUB_OUT=$'Layers contract BROKEN\n\nContracts: 2 kept, 1 broken.'
[ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | grep -q '1 architecture violation(s) (importlinter)'; check "importlinter: 1 broken" $?
# real lint-imports output: the offending import edge is what the agent sees first
LI=$'Architecture layers BROKEN\n\nContracts: 0 kept, 1 broken.\n\nBroken contracts\n----------------\n\nArchitecture layers\n-------------------\n\nacme.domain is not allowed to import acme.infra:\n\n- acme.domain.fee -> acme.infra.db (l.3)'
run "$r" architecture STUB_EXIT=1 STUB_OUT="$LI"
[ "$(printf '%s\n' "$out" | sed -n 2p)" = "  - acme.domain.fee -> acme.infra.db (l.3)" ]; check "importlinter: the import edge is the first detail" $?
run "$r" architecture STUB_EXIT=0 STUB_OUT="Contracts: 3 kept, 0 broken."; [ $rc -eq 0 ]; check "importlinter: pass" $?

# ================= architecture-grep
r="$(mk)"; put "$r" architecture-grep
LAYERS_JAVA="domain|src/main/java/com/acme/domain|com.acme.domain||domainModels
application|src/main/java/com/acme/application|com.acme.application|domain|applicationServices
adapter|src/main/java/com/acme/adapter|com.acme.adapter|application,domain|adapter"
cat > "$r/.agents/rules/architecture.env" <<ENV
STYLE=hexagonal
LANG=java
BASE=com.acme
LAYERS='$LAYERS_JAVA'
FORBIDDEN='domain|org.springframework'
ENV
J="$r/src/main/java/com/acme"; mkdir -p "$J/domain" "$J/application" "$J/adapter/web"
printf 'package com.acme.domain;\nimport com.acme.adapter.web.X;\nimport org.springframework.stereotype.Service;\nimport java.util.List;\n' > "$J/domain/Foo.java"
printf 'package com.acme.application;\nimport com.acme.domain.Foo;\n' > "$J/application/Svc.java"
printf 'package com.acme.adapter.web;\npublic class X {}\n' > "$J/adapter/web/X.java"
commit "$r"
run "$r" architecture-grep KEEL_MEASURE=1 KEEL_TODAY=2026-10-20
[ "$(printf '%s\n' "$out" | sed -n 2,5p)" = "$(printf 'src/main/java/com/acme/domain/Foo.java\t2')" ]; check "grep java: domain->adapter (1) + framework (1) = 2; application->domain = 0" $?
run "$r" architecture-grep; [ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | grep -q '^architecture-grep	correctness	fail	' && printf '%s\n' "$out" | grep -q '^  guidance: '; check "grep java: fails without baseline" $?
printf '# measured_at: 2026-10-20 review_by: 2027-04-20\nsrc/main/java/com/acme/domain/Foo.java\t2\n' > "$r/.agents/baselines/architecture-grep.tsv"
run "$r" architecture-grep; [ $rc -eq 0 ]; check "grep java: baselined passes" $?
run "$r" architecture-grep SCOPE=src/main/java/com/acme/application/Svc.java; [ $rc -eq 0 ]; check "grep java: SCOPE honoured" $?
# python
r="$(mk)"; put "$r" architecture-grep
cat > "$r/.agents/rules/architecture.env" <<'ENV'
STYLE=layered
LANG=python
BASE=acme
LAYERS='domain|acme/domain|acme.domain||domainModels
infra|acme/infra|acme.infra|domain|adapter'
ENV
mkdir -p "$r/acme/domain" "$r/acme/infra"; printf 'from acme.infra import db\nimport os\n' > "$r/acme/domain/m.py"; printf 'from acme.domain import m\n' > "$r/acme/infra/db.py"; commit "$r"
run "$r" architecture-grep KEEL_MEASURE=1; printf '%s\n' "$out" | grep -qx "$(printf 'acme/domain/m.py\t1')" && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 2 ]; check "grep python: domain importing infra counted" $?
sed -i 's/^LANG=python/LANG=ts/' "$r/.agents/rules/architecture.env"; run "$r" architecture-grep; [ $rc -eq 2 ] && printf '%s\n' "$out" | grep -q 'use architecture.sh with ENGINE=depcruise'; check "grep ts -> skip with pointer" $?

# ================= code-language
structure code-language
SL="$KEEL/assets/core/sensors/rules/stoplists/pt.txt"
[ "$(grep -vc '^#' "$SL")" -ge 100 ]; check "stop-list has at least 100 words" $?
! grep -v '^#' "$SL" | grep -qxE 'data|total|item|status|local|real|final|base'; check "stop-list excludes data total item status local real final base" $?
! grep -v '^#' "$SL" | grep -qvE '^[a-z]+$'; check "stop-list is ASCII lowercase" $?
r="$(mk)"; put "$r" code-language; mkdir -p "$r/scripts/sensors/stoplists"; cp "$SL" "$r/scripts/sensors/stoplists/pt.txt"
printf "INCLUDE='src'\n" > "$r/.agents/rules/code-language.env"
cat > "$r/src/a.ts" <<'TS'
const nomeUsuario = 1; // calcula o valor
const name = "Usuário inválido";
TS
printf 'function açãoX() {}\n' > "$r/src/b.ts"; commit "$r"
run "$r" code-language KEEL_MEASURE=1 KEEL_TODAY=2026-10-20
printf '%s\n' "$out" | grep -qx "$(printf 'src/a.ts\t4')"; check "code-language: identifiers + comment words counted, literals ignored (4)" $?
printf '%s\n' "$out" | grep -q "^src/b.ts	[1-9]"; check "code-language: non-ASCII identifier flagged" $?
run "$r" code-language; [ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | grep -q '^code-language	heuristic	fail	' && printf '%s\n' "$out" | grep -q '^  guidance: Rename the identifiers'; check "code-language: fails without baseline" $?
run "$r" code-language KEEL_MEASURE=1 | cat >/dev/null
(cd "$r" && KEEL_MEASURE=1 bash scripts/sensors/code-language.sh > .agents/baselines/code-language.tsv)
run "$r" code-language; [ $rc -eq 0 ]; check "code-language: baselined passes" $?
echo 'const calcula = 1;' >> "$r/src/a.ts"; run "$r" code-language; [ $rc -eq 1 ]; check "code-language: growth fails" $?
run "$r" code-language SCOPE=src/b.ts; [ $rc -eq 0 ]; check "code-language: SCOPE honoured" $?
echo 'plain English only' > "$r/src/c.ts"; run "$r" code-language KEEL_MEASURE=1; ! printf '%s\n' "$out" | grep -q 'src/c.ts'; check "code-language: English file not flagged" $?
# measure.sh language
MS="$KEEL/scripts/measure.sh"
r="$(mk)"; printf 'const nomeUsuario = 1; // calcula o valor\n' > "$r/src/a.ts"; commit "$r"
out="$(cd "$r" && bash "$MS" language pt.txt 2>&1)"
printf '%s\n' "$out" | grep -qx 'flagged 4' && printf '%s\n' "$out" | grep -qx "$(printf 'nome\t1')"; check "measure.sh language: flagged 4 and nome 1" $?
[ -z "$(cd "$r" && git status --porcelain | grep -v '^??' )" ] && [ -z "$(cd "$r" && git status --porcelain)" ]; check "measure.sh language writes nothing in the repo" $?

# ================= test-presence
structure test-presence
r="$(mk)"; put "$r" test-presence
cat > "$r/.agents/rules/testing-strategy.env" <<'ENV'
INCLUDE='src/main'
MAPPINGS='^src/main/java/(.*)\.java$|src/test/java/\1Test.java'
ENV
mkdir -p "$r/src/main/java/a" "$r/src/test/java/a"; echo c > "$r/src/main/java/a/Foo.java"; echo c > "$r/src/test/java/a/FooTest.java"; echo c > "$r/src/main/java/a/Bar.java"; commit "$r"
run "$r" test-presence SCOPE=src/main/java/a/Foo.java; [ $rc -eq 0 ]; check "test-presence: test exists -> pass" $?
run "$r" test-presence SCOPE=src/main/java/a/Bar.java
[ $rc -eq 1 ] && printf '%s\n' "$out" | grep -q 'Bar.java' && printf '%s\n' "$out" | grep -q 'src/test/java/a/BarTest.java'; check "test-presence: missing test names the file" $?
printf '# measured_at: 2026-10-20 review_by: 2027-04-20\nsrc/main/java/a/Bar.java\t1\n' > "$r/.agents/baselines/test-presence.tsv"
run "$r" test-presence SCOPE=src/main/java/a/Bar.java; [ $rc -eq 0 ]; check "test-presence: baselined -> pass" $?
run "$r" test-presence KEEL_MEASURE=1 KEEL_TODAY=2026-10-20; [ "$(printf '%s\n' "$out" | sed -n 2,9p)" = "$(printf 'src/main/java/a/Bar.java\t1')" ]; check "test-presence: KEEL_MEASURE over all INCLUDE files" $?

# ================= slow: mutation
structure slow/mutation
r="$(mk)"; mkdir -p "$r/scripts/sensors/slow"; install_asset "$r" "$RS/slow/mutation.sh" scripts/sensors/slow/mutation.sh
printf "MUTATION_MIN_SCORE=70\n" > "$r/.agents/rules/testing-strategy.env"
mkdir -p "$r/src/main/java/a"; echo c > "$r/src/main/java/a/Foo.java"; commit "$r"
runm() { local rr="$1"; shift; out="$(cd "$rr" && env STUB_LOG="$rr/stub.log" "$@" bash scripts/sensors/slow/mutation.sh 2>&1)"; rc=$?; }
runm "$r" SCOPE=src/main/java/a/Foo.java; [ $rc -eq 2 ]; check "mutation: tool absent -> skip" $?
use_stub "$r" pitest-maven mvnw
runm "$r" SCOPE=src/main/java/a/Foo.java STUB_OUT="Generated 10 mutations Killed 6 (60%)" STUB_EXIT=0
[ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | grep -q '^mutation	correctness	fail	.*60%' && printf '%s\n' "$out" | grep -q '^  guidance: .*never lower\|^  guidance: .*Never lower'; check "mutation: 60% < 70 fails" $?
grep -q -- '-DtargetClasses=a.Foo' "$r/stub.log"; check "mutation: pit gets FQCN targets" $?
runm "$r" SCOPE=src/main/java/a/Foo.java STUB_OUT="Generated 10 mutations Killed 8 (80%)"; [ $rc -eq 0 ]; check "mutation: 80% passes" $?
runm "$r" SCOPE=; [ $rc -eq 2 ] && printf '%s\n' "$out" | grep -q 'no changed source files'; check "mutation: empty SCOPE -> skip" $?
runm "$r" SCOPE=README.md; [ $rc -eq 2 ]; check "mutation: no source changed -> skip" $?
# stryker
r="$(mk)"; mkdir -p "$r/scripts/sensors/slow"; install_asset "$r" "$RS/slow/mutation.sh" scripts/sensors/slow/mutation.sh
printf "MUTATION_MIN_SCORE=70\n" > "$r/.agents/rules/testing-strategy.env"; echo c > "$r/src/a.ts"; commit "$r"
sed -i 's|^ENGINE="pit"|ENGINE="stryker"|; s|^CMD=.*|CMD=(node_modules/.bin/stryker run)|' "$r/scripts/sensors/slow/mutation.sh"
use_stub "$r" stryker node_modules/.bin/stryker
runm "$r" SCOPE=src/a.ts STUB_OUT="Final mutation score of 90.5"; [ $rc -eq 0 ] && grep -q -- '--mutate src/a.ts' "$r/stub.log"; check "mutation: stryker --mutate" $?
# mutmut
sed -i 's|^ENGINE="stryker"|ENGINE="mutmut"|; s|^CMD=.*|CMD=(.venv/bin/mutmut)|' "$r/scripts/sensors/slow/mutation.sh"; echo c > "$r/pkg.py"; commit "$r"
use_stub "$r" mutmut .venv/bin/mutmut
runm "$r" SCOPE=pkg.py STUB_OUT=$'Killed (6)\nSurvived (4)'; [ $rc -eq 1 ] && grep -q -- '--paths-to-mutate pkg.py' "$r/stub.log"; check "mutation: mutmut score from killed/survived" $?

# ================= slow: diff-coverage
structure slow/diff-coverage
r="$(mk)"; mkdir -p "$r/scripts/sensors/slow"; install_asset "$r" "$RS/slow/diff-coverage.sh" scripts/sensors/slow/diff-coverage.sh
printf "DIFF_COVERAGE_MIN=80\n" > "$r/.agents/rules/testing-strategy.env"
# src/a.ts has 4 lines; the report covers 1-3, not 4 (whole-file coverage 75%)
mkdir -p "$r/coverage"; cp "$FIXTURES/coverage/lcov.info" "$r/coverage/lcov.info"; printf 'l1\nl2\nl3\nl4\n' > "$r/src/a.ts"; commit "$r"
sed -i 's|^CMD=.*|CMD=(true)|' "$r/scripts/sensors/slow/diff-coverage.sh"
rund() { local rr="$1"; shift; out="$(cd "$rr" && env "$@" bash scripts/sensors/slow/diff-coverage.sh 2>&1)"; rc=$?; }
sed -i '4s/.*/l4 changed/' "$r/src/a.ts"; rund "$r" SCOPE=src/a.ts
[ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | grep -q '^diff-coverage	correctness	fail	diff coverage 0% .*(0 of 1 changed lines)' && printf '%s\n' "$out" | grep -qF '  src/a.ts: lines 4 not covered'; check "diff-coverage: the changed line 4 is uncovered -> fails and lists it" $?
(cd "$r" && git checkout -q src/a.ts); sed -i '2s/.*/l2 changed/' "$r/src/a.ts"; rund "$r" SCOPE=src/a.ts
[ $rc -eq 0 ] && printf '%s\n' "$out" | head -1 | grep -q 'diff coverage 100% .*1 of 1 changed lines'; check "diff-coverage: only changed lines count - a covered edit in a 75%-covered file passes" $?
rund "$r" SCOPE=; [ $rc -eq 2 ]; check "diff-coverage: empty SCOPE -> skip" $?
echo new > "$r/src/b.ts"; rund "$r" SCOPE=src/b.ts; [ $rc -eq 2 ] && printf '%s\n' "$out" | grep -q 'no changed file appears in the coverage report'; check "diff-coverage: changed file missing from the report -> skip" $?
r="$(mk)"; mkdir -p "$r/scripts/sensors/slow" "$r/build/reports"; install_asset "$r" "$RS/slow/diff-coverage.sh" scripts/sensors/slow/diff-coverage.sh
printf "DIFF_COVERAGE_MIN=80\n" > "$r/.agents/rules/testing-strategy.env"
cp "$FIXTURES/coverage/jacoco.xml" "$r/build/reports/jacoco.xml"; mkdir -p "$r/src/main/java/a"; printf 'p\n\nc1\nc2\n' > "$r/src/main/java/a/Foo.java"; commit "$r"
sed -i 's|^CMD=.*|CMD=(true)|; s|^FORMAT=.*|FORMAT="jacoco"|; s|^REPORT=.*|REPORT="build/reports/jacoco.xml"|' "$r/scripts/sensors/slow/diff-coverage.sh"
sed -i '3s/.*/c1 changed/' "$r/src/main/java/a/Foo.java"
rund "$r" SCOPE=src/main/java/a/Foo.java; [ $rc -eq 0 ] && printf '%s\n' "$out" | head -1 | grep -q '100%'; check "diff-coverage: jacoco, changed line covered -> passes" $?

# ================= pattern (F3d-1): generic, baselined
structure pattern
PT="$KEEL/$RS/pattern.sh"
r="$(mk)"; put "$r" pattern
run "$r" pattern; [ $rc -eq 2 ] && printf '%s\n' "$out" | head -1 | grep -q 'skip	.*no .agents/rules/pattern.env - run the rules skill'; check "pattern: no env -> skip" $?
cat > "$r/.agents/rules/pattern.env" <<'ENV'
RULE_ID=pattern
PATTERN='console\.(log|debug)\('
INCLUDE='src'
MESSAGE='Direct console output was found.'
FIX='Use the logger in src/log.ts.'
ENV
printf 'console.log(1);\nok();\nconsole.debug(2);\n' > "$r/src/a.ts"; printf 'ok();\n' > "$r/src/clean.ts"; commit "$r"
run "$r" pattern
[ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | grep -q '^pattern	heuristic	fail	1 of 2 files with new matches\.$' && printf '%s\n' "$out" | grep -qF '  src/a.ts: 2 match(es) (allowed 0)'; check "pattern: matches without a baseline fail, per file" $?
printf '%s\n' "$out" | grep -qF '  guidance: Direct console output was found. Use the logger in src/log.ts. Never add a suppression to make this pass'; check "pattern: guidance is MESSAGE, FIX and the suppression warning" $?
[ "$(printf '%s\n' "$out" | grep -c '^  ')" -le 6 ]; check "pattern: at most 5 detail lines plus guidance" $?
printf '# measured_at: 2026-10-20 review_by: 2027-04-20\nsrc/a.ts\t2\n' > "$r/.agents/baselines/pattern.tsv"
run "$r" pattern; [ $rc -eq 0 ] && printf '%s\n' "$out" | head -1 | grep -q '^pattern	heuristic	pass	2 files checked, no new matches (1 files baselined)\.$'; check "pattern: baselined passes" $?
printf 'console.log(1);\nconsole.log(2);\nconsole.debug(3);\n' > "$r/src/a.ts"; run "$r" pattern
[ $rc -eq 1 ] && printf '%s\n' "$out" | grep -qF '  src/a.ts: 3 match(es) (allowed 2)'; check "pattern: growth past the baseline fails" $?
printf 'console.log(1);\n' > "$r/src/a.ts"; run "$r" pattern; [ $rc -eq 0 ]; check "pattern: shrinking is always allowed" $?
printf 'console.log(1);\n' > "$r/src/b.ts"; run "$r" pattern
[ $rc -eq 1 ] && printf '%s\n' "$out" | grep -qF '  src/b.ts: 1 match(es) (allowed 0)'; check "pattern: a new file with a match fails (absent from the baseline means zero)" $?
run "$r" pattern SCOPE=src/a.ts; [ $rc -eq 0 ]; check "pattern: SCOPE restricts the check" $?
rm "$r/src/b.ts"
run "$r" pattern KEEL_MEASURE=1 KEEL_TODAY=2026-10-20
[ "$(printf '%s\n' "$out" | head -1)" = "# measured_at: 2026-10-20 review_by: 2027-04-20" ] && printf '%s\n' "$out" | grep -qx "$(printf 'src/a.ts\t1')" && ! printf '%s\n' "$out" | grep -q 'clean.ts'; check "pattern: KEEL_MEASURE prints the header and the non-zero rows" $?
printf "PATTERN='console\\\\.log'\nINCLUDE='src'\nEXCLUDE='src/a.ts'\n" > "$r/.agents/rules/pattern.env"
run "$r" pattern KEEL_MEASURE=1; ! printf '%s\n' "$out" | grep -q 'src/a.ts'; check "pattern: EXCLUDE honoured" $?
printf "PATTERN='console\\\\.log'\nINCLUDE='lib'\n" > "$r/.agents/rules/pattern.env"
run "$r" pattern KEEL_MEASURE=1; ! printf '%s\n' "$out" | grep -q 'src/a.ts'; check "pattern: INCLUDE limits the files" $?
printf "PATTERN='console\\\\.log'\r\nCLASS=correctness\r\n" > "$r/.agents/rules/pattern.env"
run "$r" pattern; printf '%s\n' "$out" | head -1 | grep -q '^pattern	correctness	pass	'; check "pattern: CLASS=correctness (CRLF env) reaches line 1" $?
printf "PATTERN='console\\\\.log'\nCLASS=security\n" > "$r/.agents/rules/pattern.env"
run "$r" pattern; [ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | grep -q 'CLASS=security'; check "pattern: CLASS=security is a configuration failure" $?
printf "ENGINE=grep\n" > "$r/.agents/rules/pattern.env"
run "$r" pattern; [ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | grep -q 'PATTERN is empty'; check "pattern: an empty PATTERN fails, never passes silently" $?
printf "PATTERN='foo('\n" > "$r/.agents/rules/pattern.env"
run "$r" pattern; [ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | grep -q 'not a valid ERE'; check "pattern: an invalid ERE fails" $?
printf "PATTERN='x'\nENGINE=perl\n" > "$r/.agents/rules/pattern.env"
run "$r" pattern; [ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | grep -q 'ENGINE=perl'; check "pattern: an unknown ENGINE fails" $?
# paths with spaces, a colon and non-ASCII; binary files are not counted
r="$(mk)"; put "$r" pattern
printf "PATTERN='TODO'\nINCLUDE='src'\n" > "$r/.agents/rules/pattern.env"
printf 'TODO a\nTODO b\n' > "$r/src/my file: ação.ts"; printf 'TODO\0\1\2\n' > "$r/src/blob.bin"; commit "$r"
run "$r" pattern; printf '%s\n' "$out" | grep -qF '  src/my file: ação.ts: 2 match(es) (allowed 0)' && ! printf '%s\n' "$out" | grep -q 'blob.bin'; check "pattern: spaces, a colon and non-ASCII in a path; binary skipped" $?
# installed under the rule's own id
r="$(mk)"; install_asset "$r" "$RS/pattern.sh" scripts/sensors/no-todo.sh; sed -i.bak 's/^id=pattern$/id=no-todo/' "$r/scripts/sensors/no-todo.sh"; rm -f "$r/scripts/sensors/no-todo.sh.bak"
printf "RULE_ID=no-todo\nPATTERN='TODO'\nINCLUDE='src'\n" > "$r/.agents/rules/no-todo.env"; echo 'TODO x' > "$r/src/a.ts"; commit "$r"
run "$r" no-todo; [ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | grep -q '^no-todo	heuristic	fail	' && printf '%s\n' "$out" | grep -qF 'rules/no-todo.env'; check "pattern: installed as <rule-id>.sh it reads its own env and baseline" $?
# engines that are not installed skip with the reason (the tools are never installed by keel)
r="$(mk)"; put "$r" pattern; echo 'rule: {}' > "$r/rule.yml"; echo 'x' > "$r/src/a.ts"
for eng in ast-grep semgrep; do
  printf "ENGINE=%s\nRULE_FILE=rule.yml\nINCLUDE='src'\n" "$eng" > "$r/.agents/rules/pattern.env"; commit "$r"
  if command -v "$eng" >/dev/null 2>&1; then
    echo "  skip pattern: $eng is installed here, so the missing-tool path cannot be tested"
  else
    run "$r" pattern; [ $rc -eq 2 ] && printf '%s\n' "$out" | head -1 | grep -q "^pattern	heuristic	skip	$eng is not installed"; check "pattern: ENGINE=$eng not installed -> skip with the reason" $?
    run "$r" pattern KEEL_MEASURE=1; [ $rc -eq 2 ]; check "pattern: ENGINE=$eng not installed -> measure skips too" $?
  fi
done
# engines with a stub on PATH: the output is reduced to path<TAB>count
mkdir -p "$r/bin"
cat > "$r/bin/ast-grep" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" > "${STUB_ARGS:-/dev/null}"
[ -n "${STUB_ERR:-}" ] && printf '%s\n' "$STUB_ERR" >&2
[ -n "${STUB_FILE:-}" ] && cat "$STUB_FILE"
exit "${STUB_EXIT:-0}"
STUB
sed 's|ast-grep|semgrep|' "$r/bin/ast-grep" > "$r/bin/semgrep"; chmod +x "$r/bin/ast-grep" "$r/bin/semgrep"
printf 'x\n' > "$r/src/b.ts"; commit "$r"
W_STUB="$r/stub-ast.json"
printf '{"text":"a","file":"src/a.ts","range":{}}\n{"text":"b","file":"src/a.ts","range":{}}\n{"text":"c","file":"./src/b.ts","range":{}}\n' > "$W_STUB"
printf "ENGINE=ast-grep\nRULE_FILE=rule.yml\nINCLUDE='src'\nMESSAGE='Bad node.'\n" > "$r/.agents/rules/pattern.env"
run "$r" pattern PATH="$r/bin:$PATH" STUB_FILE="$W_STUB" STUB_EXIT=1 STUB_ARGS="$r/args.txt"
[ $rc -eq 1 ] && printf '%s\n' "$out" | grep -qF '  src/a.ts: 2 match(es) (allowed 0)' && printf '%s\n' "$out" | grep -qF '  src/b.ts: 1 match(es) (allowed 0)'; check "pattern: ast-grep --json output is reduced to per-file counts" $?
grep -q -- '--rule rule.yml' "$r/args.txt" && grep -q 'src/a.ts' "$r/args.txt"; check "pattern: ast-grep is given the rule file and the candidate files" $?
printf '# measured_at: 2026-10-20 review_by: 2027-04-20\nsrc/a.ts\t2\nsrc/b.ts\t1\n' > "$r/.agents/baselines/pattern.tsv"
run "$r" pattern PATH="$r/bin:$PATH" STUB_FILE="$W_STUB" STUB_EXIT=1; [ $rc -eq 0 ]; check "pattern: ast-grep findings within the baseline pass" $?
rm "$r/.agents/baselines/pattern.tsv"
run "$r" pattern PATH="$r/bin:$PATH" STUB_ERR="error: bad rule" STUB_EXIT=2
[ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | grep -q 'ast-grep failed: error: bad rule'; check "pattern: an engine that prints only an error fails, never passes" $?
run "$r" pattern PATH="$r/bin:$PATH"; [ $rc -eq 0 ]; check "pattern: an engine with no findings and no error passes" $?
printf '{"results":[{"check_id":"r","path":"src/a.ts","start":{"line":1}},{"check_id":"r","path": "src/a.ts"}],"errors":[],"paths":{"scanned":["src/a.ts"]}}\n' > "$r/stub-sg.json"
printf "ENGINE=semgrep\nRULE_FILE=rule.yml\nINCLUDE='src'\n" > "$r/.agents/rules/pattern.env"
run "$r" pattern PATH="$r/bin:$PATH" STUB_FILE="$r/stub-sg.json" STUB_ARGS="$r/args2.txt"
[ $rc -eq 1 ] && printf '%s\n' "$out" | grep -qF '  src/a.ts: 2 match(es) (allowed 0)'; check "pattern: semgrep --json output is reduced to per-file counts" $?
grep -q -- '--config rule.yml' "$r/args2.txt"; check "pattern: semgrep is given the rule file" $?
printf "ENGINE=semgrep\nRULE_FILE=missing.yml\n" > "$r/.agents/rules/pattern.env"
run "$r" pattern PATH="$r/bin:$PATH"; [ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | grep -q "RULE_FILE 'missing.yml'"; check "pattern: a missing RULE_FILE fails" $?

# ================= gate slow runs the slow sensors
r="$(mk)"; install_asset "$r" assets/core/gate.sh scripts/gate.sh; cp "$KEEL/assets/core/gate.env" "$r/.agents/gate.env"
mkdir -p "$r/scripts/sensors/slow" "$r/coverage"; install_asset "$r" "$RS/slow/diff-coverage.sh" scripts/sensors/slow/diff-coverage.sh
printf "DIFF_COVERAGE_MIN=80\n" > "$r/.agents/rules/testing-strategy.env"; cp "$FIXTURES/coverage/lcov.info" "$r/coverage/lcov.info"; printf 'l1\nl2\nl3\nl4\n' > "$r/src/a.ts"; commit "$r"
sed -i 's|^CMD=.*|CMD=(true)|' "$r/scripts/sensors/slow/diff-coverage.sh"; sed -i '4s/.*/l4 changed/' "$r/src/a.ts"
out="$(cd "$r" && bash scripts/gate.sh slow 2>&1)"; rc=$?
[ $rc -eq 1 ] && printf '%s\n' "$out" | grep -q 'gate: slow - FAILED (1 of 1)'; check "gate.sh slow runs diff-coverage" $?
finish
