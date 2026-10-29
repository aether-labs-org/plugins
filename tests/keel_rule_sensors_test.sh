#!/usr/bin/env bash
set -uo pipefail
qgrep() { grep "$@" >/dev/null; } # reads all its input: `| grep -q` can SIGPIPE the writer under pipefail
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
  sed -n 2p "$f" | qgrep '^# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.$'; check "$1 managed header" $?
  grep -q '^# --- keel:repo-specific begin ---$' "$f" && grep -q '^# --- keel:repo-specific end ---$' "$f"; check "$1 markers" $?
  grep -q "^id=$(basename "$1")\$" "$f"; check "$1 id equals file name" $?
}

# ================= file-size
structure file-size
r="$(mk)"; put "$r" file-size
run "$r" file-size; [ $rc -eq 2 ] && printf '%s\n' "$out" | head -1 | qgrep 'skip	.*no .agents/rules/file-size.env - run the rules skill'; check "file-size: no env -> skip" $?
printf "LIMIT=5\nINCLUDE='src'\n" > "$r/.agents/rules/file-size.env"
nlines 7 > "$r/src/a.ts"; nlines 3 > "$r/src/small.ts"; commit "$r"
run "$r" file-size
[ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | qgrep '^file-size	heuristic	fail	' && printf '%s\n' "$out" | qgrep -F '  src/a.ts: 7 lines (allowed 5)'; check "file-size: oversize without baseline fails" $?
printf '%s\n' "$out" | qgrep -F '  guidance: Split the files above by responsibility so each part stays within 5 lines (docs/conventions.md#file-size). Do not raise .agents/baselines/file-size.tsv or LIMIT in .agents/rules/file-size.env.'; check "file-size: guidance text" $?
printf '# measured_at: 2026-10-20 review_by: 2027-04-20\nsrc/a.ts\t7\n' > "$r/.agents/baselines/file-size.tsv"
run "$r" file-size; [ $rc -eq 0 ] && printf '%s\n' "$out" | head -1 | qgrep '^file-size	heuristic	pass	2 files checked, 0 over 5 lines (1 baselined)\.$'; check "file-size: baselined passes" $?
nlines 8 > "$r/src/a.ts"; run "$r" file-size; [ $rc -eq 1 ] && printf '%s\n' "$out" | qgrep -F 'src/a.ts: 8 lines (allowed 7)'; check "file-size: growth past baseline fails" $?
nlines 4 > "$r/src/a.ts"; run "$r" file-size; [ $rc -eq 0 ]; check "file-size: shrink below limit passes" $?
rm "$r/.agents/baselines/file-size.tsv"; nlines 7 > "$r/src/my file ação.ts"; rm "$r/src/a.ts"
run "$r" file-size; printf '%s\n' "$out" | qgrep -F '  src/my file ação.ts: 7 lines (allowed 5)'; check "file-size: spaces and non-ASCII path (RF1)" $?
printf 'LIMIT=5\r\nINCLUDE='"'"'src'"'"'\r\n' > "$r/.agents/rules/file-size.env"
run "$r" file-size; printf '%s\n' "$out" | qgrep -F 'allowed 5)'; check "file-size: CRLF env parses (RF4)" $?
nlines 7 > "$r/src/a.ts"; nlines 7 > "$r/src/b.ts"
run "$r" file-size SCOPE=src/b.ts
printf '%s\n' "$out" | qgrep -F 'src/b.ts: 7' && ! printf '%s\n' "$out" | qgrep -F 'src/a.ts'; check "file-size: SCOPE restricts the check" $?
run "$r" file-size KEEL_MEASURE=1 KEEL_TODAY=2026-10-20
[ "$(printf '%s\n' "$out" | head -1)" = "# measured_at: 2026-10-20 review_by: 2027-04-20" ] && printf '%s\n' "$out" | qgrep -x "$(printf 'src/a.ts\t7')"; check "file-size: KEEL_MEASURE output" $?
printf "LIMIT=5\nINCLUDE='src'\nEXCLUDE='src/b.ts'\n" > "$r/.agents/rules/file-size.env"
run "$r" file-size KEEL_MEASURE=1; ! printf '%s\n' "$out" | qgrep 'src/b.ts'; check "file-size: EXCLUDE honoured" $?
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
[ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | qgrep '^folder-layout	correctness	fail	' && printf '%s\n' "$out" | qgrep -F '  src/misc/y.ts'; check "folder-layout: misplaced file reported" $?
printf '%s\n' "$out" | qgrep -F 'docs/architecture.md#folder-layout' && printf '%s\n' "$out" | qgrep -F 'ever widen ALLOWED'; check "folder-layout: guidance" $?
printf '# measured_at: 2026-10-20 review_by: 2027-04-20\nsrc/misc/y.ts\t1\n' > "$r/.agents/baselines/folder-layout.tsv"
run "$r" folder-layout; [ $rc -eq 0 ]; check "folder-layout: baselined passes" $?
echo 1 > "$r/src/other/z.ts"; run "$r" folder-layout; [ $rc -eq 1 ] && printf '%s\n' "$out" | qgrep -F 'src/other/z.ts'; check "folder-layout: new misplaced file fails" $?
run "$r" folder-layout SCOPE=src/app/x.ts; [ $rc -eq 0 ]; check "folder-layout: SCOPE honoured" $?
run "$r" folder-layout KEEL_MEASURE=1 KEEL_TODAY=2026-10-20; printf '%s\n' "$out" | qgrep -x "$(printf 'src/misc/y.ts\t1')"; check "folder-layout: KEEL_MEASURE" $?

# ================= architecture (native engines)
structure architecture
structure architecture-grep
r="$(mk)"; put "$r" architecture
run "$r" architecture; [ $rc -eq 2 ]; check "architecture: no env -> skip" $?
printf "STYLE=hexagonal\nLANG=java\nBASE=com.acme\n" > "$r/.agents/rules/architecture.env"
run "$r" architecture; [ $rc -eq 2 ] && printf '%s\n' "$out" | head -1 | qgrep 'skip'; check "archunit: tool absent -> skip" $?
use_stub "$r" gradlew gradlew
VIOL=$'Architecture Violation [Priority: MEDIUM] - Rule \'x\' was violated (2 times):\nMethod <a.A.m()> calls <b.B.n()> in (A.java:3)\nMethod <a.A.o()> calls <b.B.n()> in (A.java:9)\nArchitecture Violation [Priority: MEDIUM] - Rule \'y\' was violated (1 times):\nField <a.A.f> has type <b.B> in (A.java:2)'
run "$r" architecture STUB_EXIT=1 STUB_OUT="$VIOL"
[ $rc -eq 1 ] && [ "$(printf '%s\n' "$out" | head -1)" = "$(printf 'architecture\tcorrectness\tfail\t3 architecture violation(s) (archunit).')" ]; check "archunit: 2+1 violations summed" $?
[ "$(printf '%s\n' "$out" | grep -c '^  [A-Z]')" -ge 1 ] && printf '%s\n' "$out" | qgrep '^  guidance: Move the dependency behind a port'; check "archunit: details + guidance" $?
run "$r" architecture STUB_EXIT=0; [ $rc -eq 0 ] && printf '%s\n' "$out" | head -1 | qgrep '^architecture	correctness	pass	'; check "archunit: pass" $?
run "$r" architecture KEEL_MEASURE=1; [ $rc -eq 0 ] && [ "$out" = "# native baseline - see docs/architecture.md#architecture" ]; check "architecture: KEEL_MEASURE" $?
grep -q "Move the dependency behind a port owned by the inner layer, or move the code to the layer allowed to depend on it (docs/architecture.md#architecture). Do not edit the generated rule or the native baseline to make this pass." "$r/scripts/sensors/architecture.sh"; check "architecture: guidance text" $?
# archunit through a quiet Gradle run: the violation text comes from the JUnit report
JX="$(cd "$(dirname "$0")" && pwd)/fixtures/keel/junit"
r="$(mk)"; put "$r" architecture; install_asset "$r" assets/core/lib/junit.sh scripts/lib/junit.sh
printf "STYLE=hexagonal\nLANG=java\nBASE=com.acme\n" > "$r/.agents/rules/architecture.env"
cp "$(cd "$(dirname "$0")" && pwd)/fixtures/keel/stubs/gradle-junit" "$r/gradlew"; chmod +x "$r/gradlew"
run "$r" architecture STUB_EXIT=1 STUB_OUT="4 tests completed, 1 failed" STUB_XML="$JX/archunit-failure.xml"
[ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | qgrep '1 architecture violation(s) (archunit)' && printf '%s\n' "$out" | qgrep -F '  Field <com.acme.application.ChargeFee.leak> has type <com.acme.adapter.web.FeeController>'; check "archunit: violation read from the JUnit report of a quiet build" $?
! printf '%s\n' "$out" | qgrep "^  domain models"; check "archunit: details are the violations, not the rule description" $?
# depcruise
r="$(mk)"; put "$r" architecture; printf "STYLE=layered\nLANG=ts\nBASE=src\n" > "$r/.agents/rules/architecture.env"
sed -i 's|^ENGINE="archunit"|ENGINE="depcruise"|; s|^CMD=.*|CMD=(node_modules/.bin/depcruise src --output-type err)|' "$r/scripts/sensors/architecture.sh"
run "$r" architecture; [ $rc -eq 2 ]; check "depcruise: tool absent -> skip" $?
use_stub "$r" depcruise node_modules/.bin/depcruise
run "$r" architecture STUB_EXIT=1 STUB_OUT=$'  error no-domain-to-infra: src/domain/a.ts -> src/infra/b.ts\n  error no-domain-to-infra: src/domain/c.ts -> src/infra/b.ts\n\nx 2 dependency violations (2 errors, 0 warnings)'
[ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | qgrep '2 architecture violation(s) (depcruise)'; check "depcruise: 2 error lines" $?
run "$r" architecture STUB_EXIT=0; [ $rc -eq 0 ]; check "depcruise: pass" $?
sed -i 's|^CMD=.*|CMD=(node_modules/.bin/depcruise src --ignore-known .agents/baselines/depcruise-known-violations.json --output-type err)|' "$r/scripts/sensors/architecture.sh"
: > "$r/stub.log"; run "$r" architecture STUB_EXIT=0 STUB_LOG="$r/stub.log"
grep -qx -- 'src --output-type err' "$r/stub.log"; check "depcruise: --ignore-known dropped while the known-violations file is missing" $?
mkdir -p "$r/.agents/baselines"; echo '[]' > "$r/.agents/baselines/depcruise-known-violations.json"
: > "$r/stub.log"; run "$r" architecture STUB_EXIT=0 STUB_LOG="$r/stub.log"
grep -qx -- 'src --ignore-known .agents/baselines/depcruise-known-violations.json --output-type err' "$r/stub.log"; check "depcruise: --ignore-known kept once the file exists" $?
run "$r" architecture STUB_EXIT=1 STUB_OUT="ERROR: Can't open config file"
[ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | qgrep 'depcruise exited 1 without reporting a violation'; check "depcruise: a tool error is not reported as a violation" $?
# importlinter
r="$(mk)"; put "$r" architecture; printf "STYLE=layered\nLANG=python\nBASE=acme\n" > "$r/.agents/rules/architecture.env"
sed -i 's|^ENGINE="archunit"|ENGINE="importlinter"|; s|^CMD=.*|CMD=(.venv/bin/lint-imports)|' "$r/scripts/sensors/architecture.sh"
run "$r" architecture; [ $rc -eq 2 ]; check "importlinter: tool absent -> skip" $?
use_stub "$r" lint-imports .venv/bin/lint-imports
run "$r" architecture STUB_EXIT=1 STUB_OUT=$'Layers contract BROKEN\n\nContracts: 2 kept, 1 broken.'
[ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | qgrep '1 architecture violation(s) (importlinter)'; check "importlinter: 1 broken" $?
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
run "$r" architecture-grep; [ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | qgrep '^architecture-grep	correctness	fail	' && printf '%s\n' "$out" | qgrep '^  guidance: '; check "grep java: fails without baseline" $?
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
run "$r" architecture-grep KEEL_MEASURE=1; printf '%s\n' "$out" | qgrep -x "$(printf 'acme/domain/m.py\t1')" && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 2 ]; check "grep python: domain importing infra counted" $?
sed -i 's/^LANG=python/LANG=ts/' "$r/.agents/rules/architecture.env"; run "$r" architecture-grep; [ $rc -eq 2 ] && printf '%s\n' "$out" | qgrep 'use architecture.sh with ENGINE=depcruise'; check "grep ts -> skip with pointer" $?

# ================= code-language
structure code-language
SL="$KEEL/assets/core/sensors/rules/stoplists/pt.txt"
[ "$(grep -vc '^#' "$SL")" -ge 100 ]; check "stop-list has at least 100 words" $?
! grep -v '^#' "$SL" | qgrep -xE 'data|total|item|status|local|real|final|base'; check "stop-list excludes data total item status local real final base" $?
! grep -v '^#' "$SL" | qgrep -vE '^[a-z]+$'; check "stop-list is ASCII lowercase" $?
r="$(mk)"; put "$r" code-language; mkdir -p "$r/scripts/sensors/stoplists"; cp "$SL" "$r/scripts/sensors/stoplists/pt.txt"
printf "INCLUDE='src'\n" > "$r/.agents/rules/code-language.env"
cat > "$r/src/a.ts" <<'TS'
const nomeUsuario = 1; // calcula o valor
const name = "Usuário inválido";
TS
printf 'function açãoX() {}\n' > "$r/src/b.ts"; commit "$r"
run "$r" code-language KEEL_MEASURE=1 KEEL_TODAY=2026-10-20
printf '%s\n' "$out" | qgrep -x "$(printf 'src/a.ts\t4')"; check "code-language: identifiers + comment words counted, literals ignored (4)" $?
printf '%s\n' "$out" | qgrep "^src/b.ts	[1-9]"; check "code-language: non-ASCII identifier flagged" $?
run "$r" code-language; [ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | qgrep '^code-language	heuristic	fail	' && printf '%s\n' "$out" | qgrep '^  guidance: Rename the identifiers'; check "code-language: fails without baseline" $?
run "$r" code-language KEEL_MEASURE=1 | cat >/dev/null
(cd "$r" && KEEL_MEASURE=1 bash scripts/sensors/code-language.sh > .agents/baselines/code-language.tsv)
run "$r" code-language; [ $rc -eq 0 ]; check "code-language: baselined passes" $?
echo 'const calcula = 1;' >> "$r/src/a.ts"; run "$r" code-language; [ $rc -eq 1 ]; check "code-language: growth fails" $?
run "$r" code-language SCOPE=src/b.ts; [ $rc -eq 0 ]; check "code-language: SCOPE honoured" $?
echo 'plain English only' > "$r/src/c.ts"; run "$r" code-language KEEL_MEASURE=1; ! printf '%s\n' "$out" | qgrep 'src/c.ts'; check "code-language: English file not flagged" $?
# measure.sh language
MS="$KEEL/scripts/measure.sh"
r="$(mk)"; printf 'const nomeUsuario = 1; // calcula o valor\n' > "$r/src/a.ts"; commit "$r"
out="$(cd "$r" && bash "$MS" language pt.txt 2>&1)"
printf '%s\n' "$out" | qgrep -x 'flagged 4' && printf '%s\n' "$out" | qgrep -x "$(printf 'nome\t1')"; check "measure.sh language: flagged 4 and nome 1" $?
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
[ $rc -eq 1 ] && printf '%s\n' "$out" | qgrep 'Bar.java' && printf '%s\n' "$out" | qgrep 'src/test/java/a/BarTest.java'; check "test-presence: missing test names the file" $?
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
[ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | qgrep '^mutation	correctness	fail	.*60%' && printf '%s\n' "$out" | qgrep '^  guidance: .*never lower\|^  guidance: .*Never lower'; check "mutation: 60% < 70 fails" $?
grep -q -- '-DtargetClasses=a.Foo' "$r/stub.log"; check "mutation: pit gets FQCN targets" $?
runm "$r" SCOPE=src/main/java/a/Foo.java STUB_OUT="Generated 10 mutations Killed 8 (80%)"; [ $rc -eq 0 ]; check "mutation: 80% passes" $?
runm "$r" SCOPE=; [ $rc -eq 2 ] && printf '%s\n' "$out" | qgrep 'no changed source files'; check "mutation: empty SCOPE -> skip" $?
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
[ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | qgrep '^diff-coverage	correctness	fail	diff coverage 0% .*(0 of 1 changed lines)' && printf '%s\n' "$out" | qgrep -F '  src/a.ts: lines 4 not covered'; check "diff-coverage: the changed line 4 is uncovered -> fails and lists it" $?
(cd "$r" && git checkout -q src/a.ts); sed -i '2s/.*/l2 changed/' "$r/src/a.ts"; rund "$r" SCOPE=src/a.ts
[ $rc -eq 0 ] && printf '%s\n' "$out" | head -1 | qgrep 'diff coverage 100% .*1 of 1 changed lines'; check "diff-coverage: only changed lines count - a covered edit in a 75%-covered file passes" $?
rund "$r" SCOPE=; [ $rc -eq 2 ]; check "diff-coverage: empty SCOPE -> skip" $?
echo new > "$r/src/b.ts"; rund "$r" SCOPE=src/b.ts; [ $rc -eq 2 ] && printf '%s\n' "$out" | qgrep 'no changed file appears in the coverage report'; check "diff-coverage: changed file missing from the report -> skip" $?
r="$(mk)"; mkdir -p "$r/scripts/sensors/slow" "$r/build/reports"; install_asset "$r" "$RS/slow/diff-coverage.sh" scripts/sensors/slow/diff-coverage.sh
printf "DIFF_COVERAGE_MIN=80\n" > "$r/.agents/rules/testing-strategy.env"
cp "$FIXTURES/coverage/jacoco.xml" "$r/build/reports/jacoco.xml"; mkdir -p "$r/src/main/java/a"; printf 'p\n\nc1\nc2\n' > "$r/src/main/java/a/Foo.java"; commit "$r"
sed -i 's|^CMD=.*|CMD=(true)|; s|^FORMAT=.*|FORMAT="jacoco"|; s|^REPORT=.*|REPORT="build/reports/jacoco.xml"|' "$r/scripts/sensors/slow/diff-coverage.sh"
sed -i '3s/.*/c1 changed/' "$r/src/main/java/a/Foo.java"
rund "$r" SCOPE=src/main/java/a/Foo.java; [ $rc -eq 0 ] && printf '%s\n' "$out" | head -1 | qgrep '100%'; check "diff-coverage: jacoco, changed line covered -> passes" $?

# ================= pattern (F3d-1): generic, baselined
structure pattern
PT="$KEEL/$RS/pattern.sh"
r="$(mk)"; put "$r" pattern
run "$r" pattern; [ $rc -eq 2 ] && printf '%s\n' "$out" | head -1 | qgrep 'skip	.*no .agents/rules/pattern.env - run the rules skill'; check "pattern: no env -> skip" $?
cat > "$r/.agents/rules/pattern.env" <<'ENV'
RULE_ID=pattern
PATTERN='console\.(log|debug)\('
INCLUDE='src'
MESSAGE='Direct console output was found.'
FIX='Use the logger in src/log.ts.'
ENV
printf 'console.log(1);\nok();\nconsole.debug(2);\n' > "$r/src/a.ts"; printf 'ok();\n' > "$r/src/clean.ts"; commit "$r"
run "$r" pattern
[ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | qgrep '^pattern	heuristic	fail	1 of 2 files with new matches\.$' && printf '%s\n' "$out" | qgrep -F '  src/a.ts: 2 match(es) (allowed 0)'; check "pattern: matches without a baseline fail, per file" $?
printf '%s\n' "$out" | qgrep -F '  guidance: Direct console output was found. Use the logger in src/log.ts. Never add a suppression to make this pass'; check "pattern: guidance is MESSAGE, FIX and the suppression warning" $?
[ "$(printf '%s\n' "$out" | grep -c '^  ')" -le 6 ]; check "pattern: at most 5 detail lines plus guidance" $?
printf '# measured_at: 2026-10-20 review_by: 2027-04-20\nsrc/a.ts\t2\n' > "$r/.agents/baselines/pattern.tsv"
run "$r" pattern; [ $rc -eq 0 ] && printf '%s\n' "$out" | head -1 | qgrep '^pattern	heuristic	pass	2 files checked, no new matches (1 files baselined)\.$'; check "pattern: baselined passes" $?
printf 'console.log(1);\nconsole.log(2);\nconsole.debug(3);\n' > "$r/src/a.ts"; run "$r" pattern
[ $rc -eq 1 ] && printf '%s\n' "$out" | qgrep -F '  src/a.ts: 3 match(es) (allowed 2)'; check "pattern: growth past the baseline fails" $?
printf 'console.log(1);\n' > "$r/src/a.ts"; run "$r" pattern; [ $rc -eq 0 ]; check "pattern: shrinking is always allowed" $?
printf 'console.log(1);\n' > "$r/src/b.ts"; run "$r" pattern
[ $rc -eq 1 ] && printf '%s\n' "$out" | qgrep -F '  src/b.ts: 1 match(es) (allowed 0)'; check "pattern: a new file with a match fails (absent from the baseline means zero)" $?
run "$r" pattern SCOPE=src/a.ts; [ $rc -eq 0 ]; check "pattern: SCOPE restricts the check" $?
rm "$r/src/b.ts"
run "$r" pattern KEEL_MEASURE=1 KEEL_TODAY=2026-10-20
[ "$(printf '%s\n' "$out" | head -1)" = "# measured_at: 2026-10-20 review_by: 2027-04-20" ] && printf '%s\n' "$out" | qgrep -x "$(printf 'src/a.ts\t1')" && ! printf '%s\n' "$out" | qgrep 'clean.ts'; check "pattern: KEEL_MEASURE prints the header and the non-zero rows" $?
printf "PATTERN='console\\\\.log'\nINCLUDE='src'\nEXCLUDE='src/a.ts'\n" > "$r/.agents/rules/pattern.env"
run "$r" pattern KEEL_MEASURE=1; ! printf '%s\n' "$out" | qgrep 'src/a.ts'; check "pattern: EXCLUDE honoured" $?
printf "PATTERN='console\\\\.log'\nINCLUDE='lib'\n" > "$r/.agents/rules/pattern.env"
run "$r" pattern KEEL_MEASURE=1; ! printf '%s\n' "$out" | qgrep 'src/a.ts'; check "pattern: INCLUDE limits the files" $?
printf "PATTERN='console\\\\.log'\r\nCLASS=correctness\r\n" > "$r/.agents/rules/pattern.env"
run "$r" pattern; printf '%s\n' "$out" | head -1 | qgrep '^pattern	correctness	pass	'; check "pattern: CLASS=correctness (CRLF env) reaches line 1" $?
printf "PATTERN='console\\\\.log'\nCLASS=security\n" > "$r/.agents/rules/pattern.env"
run "$r" pattern; [ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | qgrep 'CLASS=security'; check "pattern: CLASS=security is a configuration failure" $?
printf "ENGINE=grep\n" > "$r/.agents/rules/pattern.env"
run "$r" pattern; [ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | qgrep 'PATTERN is empty'; check "pattern: an empty PATTERN fails, never passes silently" $?
printf "PATTERN='foo('\n" > "$r/.agents/rules/pattern.env"
run "$r" pattern; [ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | qgrep 'not a valid ERE'; check "pattern: an invalid ERE fails" $?
printf "PATTERN='x'\nENGINE=perl\n" > "$r/.agents/rules/pattern.env"
run "$r" pattern; [ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | qgrep 'ENGINE=perl'; check "pattern: an unknown ENGINE fails" $?
# paths with spaces, a colon and non-ASCII; binary files are not counted
r="$(mk)"; put "$r" pattern
printf "PATTERN='TODO'\nINCLUDE='src'\n" > "$r/.agents/rules/pattern.env"
printf 'TODO a\nTODO b\n' > "$r/src/my file: ação.ts"; printf 'TODO\0\1\2\n' > "$r/src/blob.bin"; commit "$r"
run "$r" pattern; printf '%s\n' "$out" | qgrep -F '  src/my file: ação.ts: 2 match(es) (allowed 0)' && ! printf '%s\n' "$out" | qgrep 'blob.bin'; check "pattern: spaces, a colon and non-ASCII in a path; binary skipped" $?
# installed under the rule's own id
r="$(mk)"; install_asset "$r" "$RS/pattern.sh" scripts/sensors/no-todo.sh; sed -i.bak 's/^id=pattern$/id=no-todo/' "$r/scripts/sensors/no-todo.sh"; rm -f "$r/scripts/sensors/no-todo.sh.bak"
printf "RULE_ID=no-todo\nPATTERN='TODO'\nINCLUDE='src'\n" > "$r/.agents/rules/no-todo.env"; echo 'TODO x' > "$r/src/a.ts"; commit "$r"
run "$r" no-todo; [ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | qgrep '^no-todo	heuristic	fail	' && printf '%s\n' "$out" | qgrep -F 'rules/no-todo.env'; check "pattern: installed as <rule-id>.sh it reads its own env and baseline" $?
# engines that are not installed skip with the reason (the tools are never installed by keel)
r="$(mk)"; put "$r" pattern; echo 'rule: {}' > "$r/rule.yml"; echo 'x' > "$r/src/a.ts"
for eng in ast-grep semgrep; do
  printf "ENGINE=%s\nRULE_FILE=rule.yml\nINCLUDE='src'\n" "$eng" > "$r/.agents/rules/pattern.env"; commit "$r"
  if command -v "$eng" >/dev/null 2>&1; then
    echo "  skip pattern: $eng is installed here, so the missing-tool path cannot be tested"
  else
    run "$r" pattern; [ $rc -eq 2 ] && printf '%s\n' "$out" | head -1 | qgrep "^pattern	heuristic	skip	$eng is not installed"; check "pattern: ENGINE=$eng not installed -> skip with the reason" $?
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
[ $rc -eq 1 ] && printf '%s\n' "$out" | qgrep -F '  src/a.ts: 2 match(es) (allowed 0)' && printf '%s\n' "$out" | qgrep -F '  src/b.ts: 1 match(es) (allowed 0)'; check "pattern: ast-grep --json output is reduced to per-file counts" $?
grep -q -- '--rule rule.yml' "$r/args.txt" && grep -q 'src/a.ts' "$r/args.txt"; check "pattern: ast-grep is given the rule file and the candidate files" $?
printf '# measured_at: 2026-10-20 review_by: 2027-04-20\nsrc/a.ts\t2\nsrc/b.ts\t1\n' > "$r/.agents/baselines/pattern.tsv"
run "$r" pattern PATH="$r/bin:$PATH" STUB_FILE="$W_STUB" STUB_EXIT=1; [ $rc -eq 0 ]; check "pattern: ast-grep findings within the baseline pass" $?
rm "$r/.agents/baselines/pattern.tsv"
run "$r" pattern PATH="$r/bin:$PATH" STUB_ERR="error: bad rule" STUB_EXIT=2
[ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | qgrep 'ast-grep failed: error: bad rule'; check "pattern: an engine that prints only an error fails, never passes" $?
run "$r" pattern PATH="$r/bin:$PATH"; [ $rc -eq 0 ]; check "pattern: an engine with no findings and no error passes" $?
printf '{"results":[{"check_id":"r","path":"src/a.ts","start":{"line":1}},{"check_id":"r","path": "src/a.ts"}],"errors":[],"paths":{"scanned":["src/a.ts"]}}\n' > "$r/stub-sg.json"
printf "ENGINE=semgrep\nRULE_FILE=rule.yml\nINCLUDE='src'\n" > "$r/.agents/rules/pattern.env"
run "$r" pattern PATH="$r/bin:$PATH" STUB_FILE="$r/stub-sg.json" STUB_ARGS="$r/args2.txt"
[ $rc -eq 1 ] && printf '%s\n' "$out" | qgrep -F '  src/a.ts: 2 match(es) (allowed 0)'; check "pattern: semgrep --json output is reduced to per-file counts" $?
grep -q -- '--config rule.yml' "$r/args2.txt"; check "pattern: semgrep is given the rule file" $?
printf "ENGINE=semgrep\nRULE_FILE=missing.yml\n" > "$r/.agents/rules/pattern.env"
run "$r" pattern PATH="$r/bin:$PATH"; [ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | qgrep "RULE_FILE 'missing.yml'"; check "pattern: a missing RULE_FILE fails" $?

# ================= gate slow runs the slow sensors
r="$(mk)"; install_asset "$r" assets/core/gate.sh scripts/gate.sh; cp "$KEEL/assets/core/gate.env" "$r/.agents/gate.env"
mkdir -p "$r/scripts/sensors/slow" "$r/coverage"; install_asset "$r" "$RS/slow/diff-coverage.sh" scripts/sensors/slow/diff-coverage.sh
printf "DIFF_COVERAGE_MIN=80\n" > "$r/.agents/rules/testing-strategy.env"; cp "$FIXTURES/coverage/lcov.info" "$r/coverage/lcov.info"; printf 'l1\nl2\nl3\nl4\n' > "$r/src/a.ts"; commit "$r"
sed -i 's|^CMD=.*|CMD=(true)|' "$r/scripts/sensors/slow/diff-coverage.sh"; sed -i '4s/.*/l4 changed/' "$r/src/a.ts"
out="$(cd "$r" && bash scripts/gate.sh slow 2>&1)"; rc=$?
[ $rc -eq 1 ] && printf '%s\n' "$out" | qgrep 'gate: slow - FAILED (1 of 1)'; check "gate.sh slow runs diff-coverage" $?

# ================= mandatory rules (D43): EXCEPTIONS with a deadline, no baseline
# mand_case SENSOR REPO ENVNAME BADPATH BASELINE_FILE EXTRA_RUN_ARGS...
# The repo must fail SENSOR for BADPATH (and only that path) under ENVNAME as a ratchet rule with no baseline.
mand_case() {
  local s="$1" r="$2" bad="$4" bl="$5" base e
  e="$r/.agents/rules/$3"
  base="$(cat "$e")"
  printf '%s\nENFORCEMENT_LEVEL=mandatory\n' "$base" > "$e"
  run "$r" "$s" KEEL_TODAY=2026-10-29; [ $rc -eq 1 ] && printf '%s\n' "$out" | qgrep -F "$bad"; check "$s: mandatory without an exception fails" $?
  printf '%s\nENFORCEMENT_LEVEL=mandatory\nEXCEPTIONS='"'"'%s 2027-01-01'"'"'\n' "$base" "$bad" > "$e"
  run "$r" "$s" KEEL_TODAY=2026-10-29
  [ $rc -eq 0 ] && printf '%s\n' "$out" | head -1 | qgrep "^$s	[a-z]*	pass	" && printf '%s\n' "$out" | head -1 | qgrep '1 excepted'; check "$s: an exception before its deadline is skipped" $?
  run "$r" "$s" KEEL_TODAY=2027-01-01; [ $rc -eq 0 ]; check "$s: the deadline day itself is still skipped" $?
  run "$r" "$s" KEEL_TODAY=2027-01-02
  [ $rc -eq 1 ] && printf '%s\n' "$out" | qgrep -F "$bad" && printf '%s\n' "$out" | qgrep -F "exception expired on 2027-01-01"; check "$s: after its deadline the exception fails and says so" $?
  printf '%s\nENFORCEMENT_LEVEL=mandatory\nEXCEPTIONS='"'"'other/path.ts 2027-01-01'"'"'\n' "$base" > "$e"
  run "$r" "$s" KEEL_TODAY=2026-10-29; [ $rc -eq 1 ]; check "$s: an exception for another path does not hide this one" $?
  printf '%s\nENFORCEMENT_LEVEL=mandatory\nEXCEPTIONS='"'"'junk-without-a-date'"'"'\n' "$base" > "$e"
  run "$r" "$s" KEEL_TODAY=2026-10-29; [ $rc -eq 1 ]; check "$s: a line without a valid date is no exception" $?
  printf '%s\nEXCEPTIONS='"'"'%s 2027-01-01'"'"'\n' "$base" "$bad" > "$e"
  run "$r" "$s" KEEL_TODAY=2026-10-29; [ $rc -eq 1 ]; check "$s: a ratchet rule (no ENFORCEMENT_LEVEL) ignores EXCEPTIONS" $?
  printf '%s\nENFORCEMENT_LEVEL=ratchet\nEXCEPTIONS='"'"'%s 2027-01-01'"'"'\n' "$base" "$bad" > "$e"
  run "$r" "$s" KEEL_TODAY=2026-10-29; [ $rc -eq 1 ]; check "$s: ENFORCEMENT_LEVEL=ratchet ignores EXCEPTIONS" $?
  printf '%s\nENFORCEMENT_LEVEL=mandatory\n' "$base" > "$e"
  printf '# measured_at: 2026-10-20 review_by: 2027-04-20\n%s\t%s\n' "$bad" "${6:-1}" > "$r/.agents/baselines/$bl"
  run "$r" "$s" KEEL_TODAY=2026-10-29; [ $rc -eq 1 ]; check "$s: a mandatory rule does not honour a TSV baseline" $?
  printf '%s\n' "$base" > "$e"
  run "$r" "$s" KEEL_TODAY=2026-10-29; [ $rc -eq 0 ]; check "$s: the same baseline passes a ratchet rule" $?
}
# file-size
r="$(mk)"; put "$r" file-size
printf "LIMIT=5\nINCLUDE='src'\n" > "$r/.agents/rules/file-size.env"; nlines 7 > "$r/src/a.ts"; commit "$r"
mand_case file-size "$r" file-size.env src/a.ts file-size.tsv 7
# folder-layout
r="$(mk)"; put "$r" folder-layout
mkdir -p "$r/src/app" "$r/src/misc"; echo 1 > "$r/src/app/x.ts"; echo 1 > "$r/src/misc/y.ts"
printf "INCLUDE='src'\nALLOWED='src/app/*'\n" > "$r/.agents/rules/folder-layout.env"; commit "$r"
mand_case folder-layout "$r" folder-layout.env src/misc/y.ts folder-layout.tsv
# test-presence
r="$(mk)"; put "$r" test-presence
printf "INCLUDE='src/main'\nMAPPINGS='^src/main/java/(.*)\\\\.java\$|src/test/java/\\\\1Test.java'\n" > "$r/.agents/rules/testing-strategy.env"
mkdir -p "$r/src/main/java/a"; echo c > "$r/src/main/java/a/Bar.java"; commit "$r"
mand_case test-presence "$r" testing-strategy.env src/main/java/a/Bar.java test-presence.tsv
# code-language
r="$(mk)"; put "$r" code-language; mkdir -p "$r/scripts/sensors/stoplists"; cp "$SL" "$r/scripts/sensors/stoplists/pt.txt"
printf "INCLUDE='src'\n" > "$r/.agents/rules/code-language.env"; printf 'function açãoX() {}\n' > "$r/src/b.ts"; commit "$r"
mand_case code-language "$r" code-language.env src/b.ts code-language.tsv 3
# architecture-grep
r="$(mk)"; put "$r" architecture-grep
cat > "$r/.agents/rules/architecture.env" <<ENV
STYLE=hexagonal
LANG=java
BASE=com.acme
LAYERS='$LAYERS_JAVA'
FORBIDDEN='domain|org.springframework'
ENV
J="$r/src/main/java/com/acme"; mkdir -p "$J/domain" "$J/adapter/web"
printf 'package com.acme.domain;\nimport com.acme.adapter.web.X;\n' > "$J/domain/Foo.java"; printf 'package com.acme.adapter.web;\npublic class X {}\n' > "$J/adapter/web/X.java"; commit "$r"
mand_case architecture-grep "$r" architecture.env src/main/java/com/acme/domain/Foo.java architecture-grep.tsv

# ================= catalog presets (F3d-2): documented env files for pattern.sh (contracts/rule-env.md)
CTR="$KEEL/contracts/rule-env.md"
# preset_env NAME -> the fenced block under "### NAME" of the "Catalog presets" section, as written in the contract
preset_env() { awk -v n="### $1" '$0 == n { p = 1; next } /^#{1,3} / { p = 0 } p && /^```/ { f = !f; next } p && f' "$CTR"; }
# preset_case NAME MUST NOT: MUST and NOT are newline-separated lines; every MUST line goes into its own file and must
# be counted by the preset, every NOT line into its own file and must not.
preset_case() {
  local name="$1" must="$2" not="$3" r i l nm=0 nn=0 rows
  r="$(mk)"; install_asset "$r" "$RS/pattern.sh" "scripts/sensors/$name.sh"
  sed -i.bak "s/^id=pattern\$/id=$name/" "$r/scripts/sensors/$name.sh"; rm -f "$r/scripts/sensors/$name.sh.bak"
  preset_env "$name" > "$r/.agents/rules/$name.env"
  [ -s "$r/.agents/rules/$name.env" ]; check "preset $name: documented in rule-env.md" $?
  i=0; while IFS= read -r l; do [ -n "$l" ] || continue; i=$((i + 1)); nm=$((nm + 1)); printf '%s\n' "$l" > "$r/src/must$i.txt"; done <<EOM
$must
EOM
  i=0; while IFS= read -r l; do [ -n "$l" ] || continue; i=$((i + 1)); nn=$((nn + 1)); printf '%s\n' "$l" > "$r/src/not$i.txt"; done <<EON
$not
EON
  commit "$r"
  run "$r" "$name" KEEL_MEASURE=1
  rows="$(printf '%s\n' "$out" | grep -c '^src/must[0-9]*\.txt	1$')"
  [ "$rows" -eq "$nm" ]; check "preset $name: all $nm must-match lines are counted (got $rows)" $?
  if printf '%s\n' "$out" | qgrep '^src/not'; then
    printf '%s\n' "$out" | grep '^src/not' | sed 's/^/    unexpected: /'
    fail "preset $name: none of the $nn must-not-match lines is counted"
  else check "preset $name: none of the $nn must-not-match lines is counted" 0; fi
  run "$r" "$name"; [ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | qgrep "^$name	heuristic	fail	"; check "preset $name: the sensor fails on the must-match files (no baseline)" $?
  PRESET_REPO="$r"
}

preset_case comments \
'// TODO fix this
# FIXME later
/* XXX */
// TODO(alice): later
// TODO: #
// TODO
x = 1 // FIXME: soon
// TODO - rewrite' \
'// TODO(#123): rewrite
// TODO #45 split
# FIXME: #7
// TODO https://tracker.example/issues/1
// TODO(https://tracker.example/issues/2)
// XXX#9 keep
const todo = 1
const XXXL = 2
AUTODO = 3
// TODOS are tracked elsewhere'

preset_case suppressions \
'// eslint-disable-next-line no-console
/* eslint-disable */
// @ts-ignore
x = 1  # noqa: E501
y = 2  #noqa
z = f()  # type: ignore
z = f()  #type:ignore[attr]
@SuppressWarnings("unchecked")' \
'// eslint-enable
const noqa = 1
# type: int
// type annotations are checked
// @ts-expect-error
'

preset_case error-handling \
'try { f(); } catch (e) {}
try { f(); } catch {}
} catch (e) { }
    except ValueError: pass
except: pass  # ignore
except (A, B) as e: pass' \
'try { f(); } catch (e) { log(e); }
} catch (e) {
except KeyError: pass_through()
except ValueError:
    pass
const catcher = {}'

preset_case logging \
'console.log("x")
    print("x")
System.out.println(x)
System.out.print(x)
println("kotlin")
x = 1; print (y)' \
'logger.info("x")
window.print()
blueprint(x)
pprint(x)
console.error("x")
def sprint(x): pass'
# logging excludes tests and scripts: a match under them is not counted, one under a source root is
r="$PRESET_REPO"; mkdir -p "$r/src/test/java" "$r/src/scripts" "$r/src/main"
printf 'console.log(1)\n' > "$r/src/app.test.ts"; printf 'console.log(1)\n' > "$r/src/app.spec.ts"
printf 'System.out.println(1);\n' > "$r/src/test/java/AppTest.java"; printf 'print(1)\n' > "$r/src/scripts/seed.py"
printf 'System.out.println(1);\n' > "$r/src/main/App.java"; commit "$r"
run "$r" logging KEEL_MEASURE=1
printf '%s\n' "$out" | qgrep -x "$(printf 'src/main/App.java\t1')" && ! printf '%s\n' "$out" | qgrep -e 'src/app\.test' -e 'src/app\.spec' -e 'src/test/' -e 'src/scripts/'; check "preset logging: tests and scripts are excluded, a source root is not" $?

# a preset env is a pattern rule, so a changed PATTERN is a loosening for guard (already covered in keel_guard_test.sh)
for p in comments suppressions error-handling logging; do
  preset_env "$p" | qgrep -x 'KIND=pattern' && preset_env "$p" | qgrep "^PATTERN='" && preset_env "$p" | qgrep '^MESSAGE=' && preset_env "$p" | qgrep '^FIX='; check "preset $p: KIND=pattern, PATTERN, MESSAGE and FIX are set" $?
done

# ================= dependencies (F3d-2): a new direct dependency needs an ADR naming the manifest
structure dependencies
DP="$KEEL/$RS/dependencies.sh"
# mkd -> a committed harness (state.yml) with the dependencies rule and one manifest of each kind
mkd() {
  local r; r="$(mk)"; put "$r" dependencies
  mkdir -p "$r/docs/adr"
  printf 'schema_version: 2\n' > "$r/.agents/state.yml"
  printf 'RULE_ID=dependencies\nKIND=pattern\nENFORCEMENT=sensor:dependencies\n' > "$r/.agents/rules/dependencies.env"
  cat > "$r/package.json" <<'EOF'
{
  "name": "app",
  "version": "1.0.0",
  "scripts": { "dependencies": "echo not a dependency" },
  "dependencies": {
    "express": "^4.18.0",
    "left-pad": "1.3.0"
  },
  "devDependencies": { "jest": "^29.0.0" }
}
EOF
  cat > "$r/pyproject.toml" <<'EOF'
[project]
name = "app"
dependencies = [
  "requests>=2.31",  # http client
  "pydantic[email]>=2",
]

[project.optional-dependencies]
web = ["flask>=3"]

[dependency-groups]
dev = [
  "pytest>=8",
]

[tool.poetry.dependencies]
python = "^3.11"
httpx = "^0.27"

[tool.poetry.group.test.dependencies]
coverage = { version = "^7", extras = ["toml"] }
EOF
  cat > "$r/pom.xml" <<'EOF'
<project>
  <parent><groupId>org.parent</groupId><artifactId>parent</artifactId></parent>
  <dependencyManagement>
    <dependencies>
      <dependency><groupId>org.managed</groupId><artifactId>bom</artifactId><version>1</version></dependency>
    </dependencies>
  </dependencyManagement>
  <dependencies>
    <dependency>
      <groupId>org.springframework</groupId>
      <artifactId>spring-core</artifactId>
      <version>6.1.0</version>
      <exclusions><exclusion><groupId>commons-logging</groupId><artifactId>commons-logging</artifactId></exclusion></exclusions>
    </dependency>
    <!-- <dependency><groupId>old</groupId><artifactId>commented</artifactId></dependency> -->
  </dependencies>
  <build><plugins><plugin>
    <artifactId>maven-x</artifactId>
    <dependencies><dependency><groupId>org.plugin</groupId><artifactId>dep</artifactId><version>1</version></dependency></dependencies>
  </plugin></plugins></build>
</project>
EOF
  mkdir -p "$r/svc"
  cat > "$r/svc/build.gradle.kts" <<'EOF'
plugins { id("java") }
dependencies {
    implementation("org.slf4j:slf4j-api:2.0.9")
    testImplementation("org.junit.jupiter:junit-jupiter:5.10.0")
    implementation(project(":core"))
    implementation(libs.jackson.databind)
}
EOF
  cat > "$r/svc/build.gradle" <<'EOF'
dependencies {
    api 'com.google.guava:guava:33.0.0-jre'
    implementation group: 'org.apache.commons', name: 'commons-lang3', version: '3.14.0'
}
EOF
  commit "$r"
  printf '%s\n' "$r"
}
verdict() { printf '%s\n' "$out" | head -1 | cut -f1-3 | tr '\t' ' '; }

r="$(mk)"; put "$r" dependencies
run "$r" dependencies; [ $rc -eq 2 ] && printf '%s\n' "$out" | head -1 | qgrep 'skip	.*no .agents/rules/dependencies.env - run the rules skill'; check "dependencies: no env -> skip" $?
r="$(mkd)"; run "$r" dependencies
[ $rc -eq 0 ] && [ "$(verdict)" = "dependencies security pass" ]; check "dependencies: nothing changed -> pass (class security)" $?
r="$(mkd)"; run "$r" dependencies KEEL_MEASURE=1
printf '%s\n' "$out" | qgrep -x "$(printf 'package.json\t3')" && printf '%s\n' "$out" | qgrep -x "$(printf 'pyproject.toml\t6')" && printf '%s\n' "$out" | qgrep -x "$(printf 'pom.xml\t1')" \
  && printf '%s\n' "$out" | qgrep -x "$(printf 'svc/build.gradle.kts\t3')" && printf '%s\n' "$out" | qgrep -x "$(printf 'svc/build.gradle\t2')"; check "dependencies: direct dependencies per manifest (scripts, dependencyManagement, plugin dependencies, exclusions, comments and project() are not direct)" $?
sed -i.bak 's/"express": "^4.18.0"/"express": "^5.0.0"/; s/"left-pad": "1.3.0"/"left-pad": "1.3.1"/' "$r/package.json"; rm -f "$r/package.json.bak"
run "$r" dependencies; [ $rc -eq 0 ]; check "dependencies: a version bump is not a new dependency" $?
sed -i.bak '/left-pad/d; s/"express": "^5.0.0",/"express": "^5.0.0"/' "$r/package.json"; rm -f "$r/package.json.bak"
run "$r" dependencies; [ $rc -eq 0 ]; check "dependencies: removing a dependency passes" $?

# package.json
r="$(mkd)"; sed -i.bak 's/"jest": "^29.0.0"/"jest": "^29.0.0", "lodash": "4.17.21"/' "$r/package.json"; rm -f "$r/package.json.bak"
run "$r" dependencies
[ $rc -eq 1 ] && [ "$(verdict)" = "dependencies security fail" ] && printf '%s\n' "$out" | qgrep -F '  package.json: lodash' && printf '%s\n' "$out" | qgrep -F '  guidance:'; check "dependencies: a new devDependency without an ADR fails and names manifest and package" $?
printf '%s\n' "$out" | qgrep -F 'Never add the dependency to an allow-list'; check "dependencies: guidance names the wrong fix" $?
printf '# ADR 0001\nWe add lodash to the dependencies of other-package.json.\n' > "$r/docs/adr/0001-lodash.md"
run "$r" dependencies; [ $rc -eq 1 ]; check "dependencies: an ADR that does not name the manifest does not unlock it" $?
printf '# ADR 0002\nWe add lodash in `package.json` for deep clone.\n' > "$r/docs/adr/0002-lodash.md"
run "$r" dependencies; [ $rc -eq 0 ] && printf '%s\n' "$out" | head -1 | qgrep '1 new direct dependency'; check "dependencies: an ADR added in the change that names package.json passes" $?
(cd "$r" && git add -A && git commit -q -m adr); run "$r" dependencies KEEL_GUARD_BASE=HEAD; [ $rc -eq 0 ]; check "dependencies: once committed the base moves and nothing is new" $?
r="$(mkd)"; sed -i.bak 's/"jest": "^29.0.0"/"jest": "^29.0.0", "lodash": "4.17.21"/' "$r/package.json"; rm -f "$r/package.json.bak"
printf 'ADR naming package.json.\n' > "$r/docs/adr/0003.md"; (cd "$r" && git add -A && git commit -q -m c2)
run "$r" dependencies KEEL_GUARD_BASE=HEAD~1; [ $rc -eq 0 ]; check "dependencies: KEEL_GUARD_BASE is honoured (ADR committed since the base)" $?
r="$(mkd)"; printf 'ADR naming package.json.\n' > "$r/docs/adr/0003.md"; (cd "$r" && git add -A && git commit -q -m adr-first)
sed -i.bak 's/"jest": "^29.0.0"/"jest": "^29.0.0", "lodash": "4.17.21"/' "$r/package.json"; rm -f "$r/package.json.bak"
run "$r" dependencies; [ $rc -eq 1 ]; check "dependencies: an ADR that already existed at the base does not unlock a new dependency" $?
r="$(mkd)"; sed -i.bak 's/"jest": "^29.0.0"/"jest": "^29.0.0", "left-pad": "1.3.0"/' "$r/package.json"; rm -f "$r/package.json.bak"
run "$r" dependencies; [ $rc -eq 0 ]; check "dependencies: a dependency already present is not new" $?
r="$(mkd)"; sed -i.bak 's/"devDependencies": { "jest": "^29.0.0" }/"devDependencies": { "jest": "^29.0.0" }, "peerDependencies": { "react": "18" }/' "$r/package.json"; rm -f "$r/package.json.bak"
run "$r" dependencies; [ $rc -eq 1 ] && printf '%s\n' "$out" | qgrep -F '  package.json: react'; check "dependencies: a peerDependency counts, on one line" $?
r="$(mkd)"; sed -i.bak 's/"scripts": {.*/"scripts": { "dependencies": "echo", "x": "y" },/' "$r/package.json"; rm -f "$r/package.json.bak"
run "$r" dependencies; [ $rc -eq 0 ]; check "dependencies: a script called dependencies is not a dependency block" $?

# pyproject.toml
r="$(mkd)"; sed -i.bak 's/^  "requests>=2.31",.*/  "requests>=2.32",  # bumped\n  "rich>=13",/' "$r/pyproject.toml"; rm -f "$r/pyproject.toml.bak"
run "$r" dependencies; [ $rc -eq 1 ] && printf '%s\n' "$out" | qgrep -F '  pyproject.toml: rich' && ! printf '%s\n' "$out" | qgrep -F 'requests'; check "dependencies: pyproject [project] dependencies: new name fails, version bump does not" $?
r="$(mkd)"; sed -i.bak 's/^web = \["flask>=3"\]/web = ["flask>=3", "jinja2"]/' "$r/pyproject.toml"; rm -f "$r/pyproject.toml.bak"
run "$r" dependencies; [ $rc -eq 1 ] && printf '%s\n' "$out" | qgrep -F '  pyproject.toml: jinja2'; check "dependencies: pyproject optional-dependencies" $?
r="$(mkd)"; sed -i.bak 's/^  "pytest>=8",/  "pytest>=8",\n  "ruff",/' "$r/pyproject.toml"; rm -f "$r/pyproject.toml.bak"
run "$r" dependencies; [ $rc -eq 1 ] && printf '%s\n' "$out" | qgrep -F '  pyproject.toml: ruff'; check "dependencies: pyproject dependency-groups" $?
r="$(mkd)"; sed -i.bak 's/^httpx = "^0.27"/httpx = "^0.28"\nanyio = "^4"/' "$r/pyproject.toml"; rm -f "$r/pyproject.toml.bak"
run "$r" dependencies; [ $rc -eq 1 ] && printf '%s\n' "$out" | qgrep -F '  pyproject.toml: anyio' && ! printf '%s\n' "$out" | qgrep -F 'httpx'; check "dependencies: pyproject [tool.poetry.dependencies]" $?
r="$(mkd)"; sed -i.bak 's/^coverage = .*/coverage = { version = "^7" }\nfreezegun = "*"/' "$r/pyproject.toml"; rm -f "$r/pyproject.toml.bak"
run "$r" dependencies; [ $rc -eq 1 ] && printf '%s\n' "$out" | qgrep -F '  pyproject.toml: freezegun'; check "dependencies: pyproject poetry group dependencies" $?
r="$(mkd)"; sed -i.bak 's/^  "pydantic\[email\]>=2",/  "pydantic>=2.5",/' "$r/pyproject.toml"; rm -f "$r/pyproject.toml.bak"
run "$r" dependencies; [ $rc -eq 0 ]; check "dependencies: extras and version specifiers do not change a dependency's name" $?

# pom.xml
r="$(mkd)"; sed -i.bak 's|<version>6.1.0</version>|<version>6.2.0</version>|' "$r/pom.xml"; rm -f "$r/pom.xml.bak"
run "$r" dependencies; [ $rc -eq 0 ]; check "dependencies: pom version bump passes" $?
r="$(mkd)"; sed -i.bak 's|<!-- <dependency>.*|<dependency><groupId>org.jsoup</groupId><artifactId>jsoup</artifactId></dependency>|' "$r/pom.xml"; rm -f "$r/pom.xml.bak"
run "$r" dependencies; [ $rc -eq 1 ] && printf '%s\n' "$out" | qgrep -F '  pom.xml: org.jsoup:jsoup'; check "dependencies: pom new dependency as groupId:artifactId" $?
r="$(mkd)"; sed -i.bak 's|<dependency><groupId>org.managed</groupId><artifactId>bom</artifactId><version>1</version></dependency>|<dependency><groupId>org.managed</groupId><artifactId>bom</artifactId><version>1</version></dependency><dependency><groupId>org.m2</groupId><artifactId>b2</artifactId></dependency>|; s|<exclusions><exclusion><groupId>commons-logging</groupId><artifactId>commons-logging</artifactId></exclusion></exclusions>|<exclusions><exclusion><groupId>x</groupId><artifactId>y</artifactId></exclusion></exclusions>|; s|<groupId>org.plugin</groupId>|<groupId>org.plugin2</groupId>|' "$r/pom.xml"; rm -f "$r/pom.xml.bak"
run "$r" dependencies; [ $rc -eq 0 ]; check "dependencies: dependencyManagement, exclusions and plugin dependencies are not direct dependencies" $?

# gradle
r="$(mkd)"; sed -i.bak 's|    implementation("org.slf4j:slf4j-api:2.0.9")|    implementation("org.slf4j:slf4j-api:2.0.10")\n    runtimeOnly("com.h2database:h2:2.2.224")|' "$r/svc/build.gradle.kts"; rm -f "$r/svc/build.gradle.kts.bak"
run "$r" dependencies; [ $rc -eq 1 ] && printf '%s\n' "$out" | qgrep -F '  svc/build.gradle.kts: com.h2database:h2' && ! printf '%s\n' "$out" | qgrep -F 'slf4j'; check "dependencies: gradle kts: new coordinate fails, version bump does not" $?
r="$(mkd)"; sed -i.bak 's|    implementation(project(":core"))|    implementation(project(":core"))\n    implementation(project(":other"))\n    implementation(libs.kotlin.stdlib)|' "$r/svc/build.gradle.kts"; rm -f "$r/svc/build.gradle.kts.bak"
run "$r" dependencies; [ $rc -eq 1 ] && printf '%s\n' "$out" | qgrep -F '  svc/build.gradle.kts: libs.kotlin.stdlib' && ! printf '%s\n' "$out" | qgrep -F ':other'; check "dependencies: gradle version-catalog alias counts, project() does not" $?
r="$(mkd)"; sed -i.bak "s|    api 'com.google.guava:guava:33.0.0-jre'|    api 'com.google.guava:guava:33.0.0-jre'\n    implementation group: 'org.yaml', name: 'snakeyaml', version: '2.2'|" "$r/svc/build.gradle"; rm -f "$r/svc/build.gradle.bak"
run "$r" dependencies; [ $rc -eq 1 ] && printf '%s\n' "$out" | qgrep -F '  svc/build.gradle: org.yaml:snakeyaml'; check "dependencies: gradle groovy map notation" $?
printf 'ADR for svc/build.gradle only.\n' > "$r/docs/adr/0001.md"; run "$r" dependencies; [ $rc -eq 0 ]; check "dependencies: the ADR names the nested manifest path" $?
printf 'ADR for svc/build.gradle.kts only (see also build.gradle).\n' > "$r/docs/adr/0001.md"; run "$r" dependencies; [ $rc -eq 1 ] && printf '%s\n' "$out" | qgrep -F '  svc/build.gradle: org.yaml:snakeyaml'; check "dependencies: naming a different manifest (svc/build.gradle.kts, or a shorter path) does not unlock it" $?

# new manifests, untracked, and a harness installed in this change
r="$(mkd)"; mkdir -p "$r/web"; printf '{ "dependencies": { "react": "18" } }\n' > "$r/web/package.json"
run "$r" dependencies; [ $rc -eq 1 ] && printf '%s\n' "$out" | qgrep -F '  web/package.json: react'; check "dependencies: a new, untracked manifest counts all its dependencies as new" $?
r="$(mkd)"; mkdir -p "$r/web"; printf '{ "dependencies": {} }\n' > "$r/web/package.json"; run "$r" dependencies; [ $rc -eq 0 ]; check "dependencies: a new manifest without dependencies passes" $?
r="$(mkd)"; git -C "$r" rm -q --cached .agents/state.yml; git -C "$r" commit -q -m nostate; rm -f "$r/.agents/state.yml"; printf '{ "dependencies": { "react": "18" } }\n' > "$r/package.json"
run "$r" dependencies; [ $rc -eq 0 ] && printf '%s\n' "$out" | head -1 | qgrep 'installed in this change'; check "dependencies: harness not installed at the base -> pass, nothing to compare" $?
r="$(new_repo --no-commit)"; put "$r" dependencies; install_asset "$r" assets/core/lib/envparse.sh scripts/lib/envparse.sh; mkdir -p "$r/.agents/rules"; printf 'RULE_ID=dependencies\n' > "$r/.agents/rules/dependencies.env"
run "$r" dependencies; [ $rc -eq 0 ] && printf '%s\n' "$out" | head -1 | qgrep 'No commits yet'; check "dependencies: no commits yet -> pass" $?
r="$(mkd)"; sed -i.bak 's/"jest": "^29.0.0"/"jest": "^29.0.0", "lodash": "4.17.21"/' "$r/package.json"; rm -f "$r/package.json.bak"
run "$r" dependencies KEEL_GUARD_BASE=nonexistent-ref; [ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | qgrep 'is not a commit'; check "dependencies: a bad KEEL_GUARD_BASE fails" $?
printf "INCLUDE='svc'\n" >> "$r/.agents/rules/dependencies.env"; run "$r" dependencies; [ $rc -eq 0 ]; check "dependencies: INCLUDE limits the manifests checked" $?
printf "INCLUDE='.'\nEXCLUDE='package.json'\n" > "$r/.agents/rules/dependencies.env"; run "$r" dependencies; [ $rc -eq 0 ]; check "dependencies: EXCLUDE drops a manifest" $?
finish
