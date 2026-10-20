#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/keel_helpers.sh"
M="$KEEL/skills/rules/assets/measure.sh"
[ -f "$M" ]; check "measure.sh exists" $?
m() { (cd "$R" && bash "$M" "$@" 2>&1); }
snap() { (cd "$R" && git status --porcelain); }
ro() { # ro <description> <subcommand args...>: output unchanged tree
  local d="$1"; shift; local b a; b="$(snap)"; m "$@" >/dev/null; a="$(snap)"; [ "$b" = "$a" ]; check "read-only: $d" $?
}
lines() { local n="$1" f="$2"; mkdir -p "$(dirname "$R/$f")"; seq 1 "$n" | sed 's/.*/x/' > "$R/$f"; }
commit() { (cd "$R" && git add -A && git commit -q -m c); }

# --- file-size
R="$(new_repo)"
for i in 1 2 3 4 5 6 7 8 9 10; do lines $((i*10)) "src/f$i.ts"; done
lines 250 src/big.ts; lines 600 src/huge.ts
printf '\0\1\2' > "$R/src/blob.bin"; commit
out="$(m file-size 'src/f*.ts')"
printf '%s\n' "$out" | grep -qx 'files 10' && printf '%s\n' "$out" | grep -qx 'p50 50' && printf '%s\n' "$out" | grep -qx 'p75 80' && printf '%s\n' "$out" | grep -qx 'p90 90'; check "file-size percentiles (nearest-rank)" $?
printf '%s\n' "$out" | grep -qx 'max 100 src/f10.ts'; check "file-size max with path" $?
out="$(m file-size)"
printf '%s\n' "$out" | grep -qx 'files 13' && printf '%s\n' "$out" | grep -qx 'over:200 2' && printf '%s\n' "$out" | grep -qx 'over:500 1' && printf '%s\n' "$out" | grep -qx 'over:1000 0' && printf '%s\n' "$out" | grep -qx 'over:300 1'; check "file-size over:N buckets, binary skipped" $?
ro file-size file-size

# --- tree
R="$(new_repo)"; for f in src/a/x.ts src/a/y.ts src/b/z.ts README.md; do mkdir -p "$R/$(dirname "$f")"; echo 1 > "$R/$f"; done; commit
out="$(m tree 2)"
printf '%s\n' "$out" | grep -qx "$(printf '2\tsrc/a')" && printf '%s\n' "$out" | grep -qx "$(printf '1\tsrc/b')"; check "tree 2 counts per directory, largest first" $?
out="$(m tree 1)"; printf '%s\n' "$out" | grep -q "$(printf '3\tsrc')"; check "tree 1 groups by first component" $?
ro tree tree

# --- imports java
R="$(new_repo)"; mkdir -p "$R/src/main/java/com/acme/app" "$R/src/main/java/com/acme/domain"
printf 'package com.acme.app;\nimport com.acme.domain.X;\nimport com.acme.domain.Y;\nimport java.util.List;\nimport com.acme.app.Same;\n' > "$R/src/main/java/com/acme/app/S.java"
printf 'package com.acme.domain;\npublic class X {}\n' > "$R/src/main/java/com/acme/domain/X.java"; commit
out="$(m imports java com.acme)"; [ "$out" = "$(printf 'app\tdomain\t2')" ]; check "imports java matrix" $?
ro imports imports java com.acme
# python
R="$(new_repo)"; mkdir -p "$R/acme/domain" "$R/acme/infra"
printf 'from acme.infra import db\nimport acme.infra.x\nimport os\n' > "$R/acme/domain/m.py"; commit
out="$(m imports python acme)"; [ "$out" = "$(printf 'domain\tinfra\t2')" ]; check "imports python matrix" $?
# ts
R="$(new_repo)"; mkdir -p "$R/src/app" "$R/src/domain"
printf "import { y } from '../domain/y';\nimport z from '@/z';\nimport r from 'react';\nconst q = require('./local');\n" > "$R/src/app/x.ts"
printf 'export const y = 1;\n' > "$R/src/domain/y.ts"; commit
out="$(m imports ts src)"
printf '%s\n' "$out" | grep -qx "$(printf 'app\tdomain\t1')" && printf '%s\n' "$out" | tail -1 | grep -qx 'unresolved 2'; check "imports ts matrix + unresolved" $?
ro imports-ts imports ts src

# --- framework-imports
R="$(new_repo)"; d="$R/src/main/java/com/acme/domain"; mkdir -p "$d"
printf 'import org.springframework.stereotype.Service;\nimport java.util.List;\nimport jakarta.persistence.Entity;\n' > "$d/A.java"; commit
out="$(m framework-imports src/main/java/com/acme/domain)"
printf '%s\n' "$out" | grep -qx "$(printf 'org.springframework\t1')" && printf '%s\n' "$out" | grep -qx "$(printf 'jakarta.\t1')"; check "framework-imports" $?
ro framework-imports framework-imports src

# --- tests
R="$(new_repo)"; mkdir -p "$R/src/main/java/a" "$R/src/test/java/a" "$R/e2e"
echo c > "$R/src/main/java/a/Foo.java"; echo c > "$R/src/main/java/a/Baz.java"
echo c > "$R/src/test/java/a/FooTest.java"; echo c > "$R/src/test/java/a/BarIT.java"; echo c > "$R/e2e/login.spec.ts"
printf 'plugins { id("info.solidsoft.pitest") version "1.15.0" }\njacoco {}\n' > "$R/build.gradle.kts"; commit
out="$(m tests)"
for l in 'main 2' 'test 3' 'unit 1' 'integration 1' 'e2e 1' 'untested_main 1' 'mutation_tool pitest' 'coverage_tool jacoco'; do
  printf '%s\n' "$out" | grep -qx "$l"; check "tests: $l" $?
done
R="$(new_repo)"; echo c > "$R/a.txt"; commit; out="$(m tests)"; printf '%s\n' "$out" | grep -qx 'mutation_tool none' && printf '%s\n' "$out" | grep -qx 'coverage_tool none'; check "tests: none tools" $?
ro tests tests

# --- unknown
R="$(new_repo)"; m bogus >/dev/null; [ $? -eq 64 ]; check "unknown subcommand rc 64" $?
finish
