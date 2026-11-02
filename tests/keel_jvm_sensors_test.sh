#!/usr/bin/env bash
set -uo pipefail
qgrep() { grep "$@" >/dev/null; } # reads all its input: `| grep -q` can SIGPIPE the writer under pipefail
. "$(dirname "$0")/keel_helpers.sh"
SD=assets/core/sensors/jvm
mk() {
  local r; r="$(new_repo)"
  install_asset "$r" assets/core/lib/baseline.sh scripts/lib/baseline.sh
  for s in compile lint tests; do install_asset "$r" "$SD/$s.sh" "scripts/sensors/$s.sh"; done
  mkdir -p "$r/.agents/baselines" "$r/src/main/kotlin/a" "$r/src/test/kotlin/a"
  printf '%s\n' "$r"
}
run() { local r="$1" s="$2"; shift 2; out="$(cd "$r" && env STUB_LOG="$r/stub.log" "$@" bash "scripts/sensors/$s.sh" 2>&1)"; rc=$?; }

for s in compile lint tests; do
  f="$KEEL/$SD/$s.sh"
  [ -f "$f" ]; check "$s exists" $?
  sed -n 2p "$f" | qgrep '^# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.$'; check "$s managed header" $?
  grep -q '^# --- keel:repo-specific begin ---$' "$f" && grep -q '^# --- keel:repo-specific end ---$' "$f"; check "$s markers" $?
  grep -q "^id=$s\$" "$f"; check "$s id equals file name" $?
done

r="$(mk)"
for s in compile lint tests; do
  run "$r" $s; [ $rc -eq 2 ] && printf '%s\n' "$out" | head -1 | qgrep "^$s	.*	skip"; check "$s skips without tool" $?
done

# compile
use_stub "$r" gradlew gradlew
echo c > "$r/src/main/kotlin/a/A.kt"; (cd "$r" && git add -A && git commit -q -m a)
run "$r" compile; [ $rc -eq 0 ] && printf '%s\n' "$out" | head -1 | qgrep '^compile	correctness	pass	'; check "compile pass" $?
run "$r" compile STUB_EXIT=1 STUB_OUT=$'e: file:///x/src/main/kotlin/a/A.kt:3:5 Unresolved reference: foo\ne: file:///x/src/main/kotlin/a/A.kt:4:1 Type mismatch'
[ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | qgrep '^compile	correctness	fail	Found 2 compile error' && printf '%s\n' "$out" | qgrep -F '  e: file:///x/src/main/kotlin/a/A.kt:3:5 Unresolved reference: foo' && printf '%s\n' "$out" | qgrep '^  guidance: '; check "compile fail with Kotlin error detail" $?
run "$r" compile STUB_EXIT=1 STUB_OUT='src/main/java/A.java:3: error: cannot find symbol'
printf '%s\n' "$out" | qgrep 'Found 1 compile error'; check "compile javac error format" $?

# lint (ktlint at PATH via bin/)
mkdir -p "$r/bin"; use_stub "$r" ktlint bin/ktlint
KT="$r/src/main/kotlin/a/A.kt"
OUTK="$r/src/main/kotlin/a/A.kt:3:5: Unexpected blank line (no-blank-line)
$r/src/main/kotlin/a/A.kt:9:1: Missing newline (final-newline)"
run "$r" lint PATH="$r/bin:$PATH" KEEL_MEASURE=1 KEEL_TODAY=2026-10-20 STUB_EXIT=1 STUB_OUT="$OUTK"
[ "$out" = "$(printf '# measured_at: 2026-10-20 review_by: 2027-04-20\nsrc/main/kotlin/a/A.kt\t2')" ]; check "lint: absolute ktlint paths -> repo-relative rows" $?
run "$r" lint PATH="$r/bin:$PATH" STUB_EXIT=1 STUB_OUT="$OUTK"; [ $rc -eq 1 ] && printf '%s\n' "$out" | qgrep 'src/main/kotlin/a/A.kt: 2 problems (allowed 0)'; check "lint fails without baseline" $?
printf '# h\nsrc/main/kotlin/a/A.kt\t2\n' > "$r/.agents/baselines/lint.tsv"
run "$r" lint PATH="$r/bin:$PATH" STUB_EXIT=1 STUB_OUT="$OUTK"; [ $rc -eq 0 ]; check "lint passes at baseline" $?
rm "$r/.agents/baselines/lint.tsv"
run "$r" lint PATH="$r/bin:$PATH" STUB_EXIT=1 STUB_OUT="$OUTK" SCOPE=src/main/kotlin/a/B.kt; [ $rc -eq 0 ]; check "lint: SCOPE excludes unchanged files" $?
run "$r" lint PATH="$r/bin:$PATH" STUB_EXIT=1 STUB_OUT="boom"; [ $rc -eq 1 ] && printf '%s\n' "$out" | qgrep 'without a parseable report'; check "lint: crash is a failure" $?

# tests
mkdir -p "$r/src/test/kotlin/a"; echo c > "$r/src/test/kotlin/a/ATest.kt"; echo c > "$r/src/main/kotlin/a/Lonely.kt"; (cd "$r" && git add -A && git commit -q -m b)
: > "$r/stub.log"; run "$r" tests SCOPE=src/main/kotlin/a/A.kt STUB_OUT=""
[ $rc -eq 0 ] && grep -qx -- '-q test --tests \*ATest' "$r/stub.log"; check "tests: gradle --tests *ATest" $?
: > "$r/stub.log"; run "$r" tests SCOPE=src/main/kotlin/a/Lonely.kt; [ $rc -eq 0 ] && [ ! -s "$r/stub.log" ] && printf '%s\n' "$out" | qgrep 'no related test found'; check "tests: no test class -> pass without calling the tool" $?
: > "$r/stub.log"; run "$r" tests SCOPE=src/test/kotlin/a/ATest.kt; grep -q -- '--tests \*ATest' "$r/stub.log"; check "tests: changed test class runs itself" $?
: > "$r/stub.log"; run "$r" tests; grep -qx -- '-q test' "$r/stub.log"; check "tests: empty SCOPE -> whole suite" $?
run "$r" tests SCOPE=src/main/kotlin/a/A.kt STUB_EXIT=1 STUB_OUT=$'ATest > works() FAILED\n    org.opentest4j.AssertionFailedError: expected: <1> but was: <2>'
[ $rc -eq 1 ] && printf '%s\n' "$out" | qgrep '^  ATest > works() FAILED' && printf '%s\n' "$out" | qgrep '^  guidance: '; check "tests fail + guidance" $?
# A quiet build prints no assertion: the JUnit report written by this run supplies it.
JX="$(cd "$(dirname "$0")" && pwd)/fixtures/keel/junit"
r3="$(mk)"; install_asset "$r3" assets/core/lib/junit.sh scripts/lib/junit.sh
cp "$(cd "$(dirname "$0")" && pwd)/fixtures/keel/stubs/gradle-junit" "$r3/gradlew"; chmod +x "$r3/gradlew"
echo x > "$r3/src/main/kotlin/a/Fee.kt"; echo x > "$r3/src/test/kotlin/a/FeeTest.kt"; (cd "$r3" && git add -A && git commit -q -m a)
run "$r3" tests SCOPE=src/main/kotlin/a/Fee.kt STUB_EXIT=1 STUB_OUT="BUILD FAILED in 1s" STUB_XML="$JX/test-failure.xml"
[ $rc -eq 1 ] && printf '%s\n' "$out" | qgrep -F '  FeeTest.appliesTheFee(): expected: <1200> but was: <1181>' && printf '%s\n' "$out" | head -1 | qgrep '1 test failure(s)'; check "tests: assertion read from this run's JUnit report" $?
run "$r3" tests SCOPE=src/main/kotlin/a/Fee.kt STUB_EXIT=1 STUB_OUT="BUILD FAILED in 1s"
! printf '%s\n' "$out" | qgrep -F 'FeeTest.appliesTheFee()'; check "tests: a report left by an earlier run is not read" $?
run "$r3" tests SCOPE=src/main/kotlin/a/Fee.kt STUB_EXIT=1 STUB_OUT="BUILD FAILED in 1s" STUB_XML="$JX/archunit-failure.xml"
! printf '%s\n' "$out" | qgrep -F 'ArchitectureTest.layers'; check "tests: reports Gradle rewrote for classes this run did not select are ignored" $?
# maven
r2="$(mk)"; use_stub "$r2" mvnw mvnw; echo c > "$r2/src/main/kotlin/a/A.kt"; echo c > "$r2/src/test/kotlin/a/ATest.kt"
sed -i 's|^BUILD="gradle"|BUILD="maven"|; s|^CMD=.*|CMD=(./mvnw -q -o)|' "$r2/scripts/sensors/tests.sh"
run "$r2" tests SCOPE=src/main/kotlin/a/A.kt; grep -q -- '-Dtest=ATest' "$r2/stub.log" && grep -q 'failIfNoSpecifiedTests=false' "$r2/stub.log"; check "tests: maven -Dtest=ATest" $?
finish
