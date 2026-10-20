#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/keel_helpers.sh"
R="$KEEL/skills/rules/assets/architecture/render.sh"
A="$FIXTURES/architecture"
[ -f "$R" ]; check "render.sh exists" $?
golden() { # golden <target> <env> <expected>
  local got; got="$(bash "$R" "$1" "$A/$2" 2>&1)"
  [ "$got" = "$(cat "$A/expected/$3")" ]; check "golden: $1 $2 == $3" $?
}
golden archunit-java hexagonal-java.env ArchitectureTest.java
golden archunit-kotlin hexagonal-kotlin.env ArchitectureTest.kt
golden archunit-properties hexagonal-java.env archunit.properties
golden depcruise layered-ts.env dependency-cruiser.cjs
golden importlinter hexagonal-python.env importlinter

# expected files carry the contract text
grep -q 'onionArchitecture()' "$A/expected/ArchitectureTest.java" && grep -q '@AnalyzeClasses(packages = "com.acme", importOptions = ImportOption.DoNotIncludeTests.class)' "$A/expected/ArchitectureTest.java"; check "java: onionArchitecture and AnalyzeClasses" $?
grep -q 'freeze.store.default.path=.agents/baselines/archunit' "$A/expected/archunit.properties" && grep -q 'freeze.store.default.allowStoreCreation=true' "$A/expected/archunit.properties"; check "properties: freeze store" $?

# FREEZE=1 (brownfield): every architecture rule is frozen, plus one unfrozen guard that fails when
# ArchUnit imports no class at all (e.g. an ArchUnit release older than the project's JDK).
bad=$(grep -E 'static final ArchRule' "$A/expected/ArchitectureTest.java" | grep -v 'classes_are_analysed' | grep -vc '= FreezingArchRule.freeze(')
[ "$bad" = 0 ] && [ "$(grep -c 'static final ArchRule' "$A/expected/ArchitectureTest.java")" -ge 4 ]; check "FREEZE=1: all architecture rules wrapped" $?
grep -q 'static final ArchRule classes_are_analysed = classes().that().resideInAPackage("com.acme..").should().resideInAPackage("com.acme..")' "$A/expected/ArchitectureTest.java" && grep -q 'import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.classes;' "$A/expected/ArchitectureTest.java"; check "FREEZE=1: guard rule against an empty import" $?
bash "$R" archunit-java "$A/hexagonal-java.env" | grep -c '@ArchTest' | grep -q '^4$'; check "one @ArchTest per rule, plus the guard" $?
# FREEZE=0 (greenfield): no freeze, no guard, and every rule may check no classes yet.
kt="$(bash "$R" archunit-kotlin "$A/hexagonal-kotlin.env")"
! printf '%s\n' "$kt" | grep -q Freezing && ! printf '%s\n' "$kt" | grep -q classes_are_analysed; check "FREEZE=0: no FreezingArchRule, no guard" $?
[ "$(printf '%s\n' "$kt" | grep -c '@ArchTest')" = "$(printf '%s\n' "$kt" | grep -c '\.allowEmptyShould(true)')" ]; check "FREEZE=0: every rule allows an empty package" $?

# IGNORE_IMPORTS: import-linter's native baseline, in every contract, warning (not failing) once fixed
t="$(mktemp)"; cp "$A/hexagonal-python.env" "$t"; printf "IGNORE_IMPORTS='acme.domain.fee -> acme.infra.db'\n" >> "$t"
out="$(bash "$R" importlinter "$t")"
[ "$(printf '%s\n' "$out" | grep -c '^    acme.domain.fee -> acme.infra.db$')" = "$(printf '%s\n' "$out" | grep -c '^type = ')" ] && [ "$(printf '%s\n' "$out" | grep -c '^unmatched_ignore_imports_alerting = warn$')" = "$(printf '%s\n' "$out" | grep -c '^type = ')" ]; check "importlinter: IGNORE_IMPORTS in every contract, unmatched only warns" $?
! bash "$R" importlinter "$A/hexagonal-python.env" | grep -q ignore_imports; check "importlinter: no IGNORE_IMPORTS -> no ignore_imports" $?
rm -f "$t"

# layered style
t="$(mktemp)"; sed 's/^STYLE=hexagonal/STYLE=layered/' "$A/hexagonal-java.env" > "$t"
out="$(bash "$R" archunit-java "$t")"
printf '%s\n' "$out" | grep -q 'layeredArchitecture().consideringAllDependencies()' && printf '%s\n' "$out" | grep -q '.whereLayer("domain").mayOnlyBeAccessedByLayers("application", "web", "persistence")'; check "layered: layers and whereLayer derived from allowed_csv" $?
rm -f "$t"

# missing LAYERS / STYLE
t="$(mktemp)"; printf 'STYLE=hexagonal\nLANG=java\n' > "$t"; bash "$R" archunit-java "$t" >/dev/null 2>&1; [ $? -eq 65 ]; check "missing LAYERS -> rc 65" $?
printf 'LAYERS="a|b|c||layer"\n' > "$t"; bash "$R" depcruise "$t" >/dev/null 2>&1; [ $? -eq 65 ]; check "missing STYLE -> rc 65" $?
rm -f "$t"
bash "$R" bogus "$A/hexagonal-java.env" >/dev/null 2>&1; [ $? -eq 64 ]; check "unknown target -> rc 64" $?
finish
