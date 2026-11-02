#!/usr/bin/env bash
set -uo pipefail
qgrep() { grep "$@" >/dev/null; } # reads all its input: `| grep -q` can SIGPIPE the writer under pipefail
. "$(dirname "$0")/keel_helpers.sh"
M="$KEEL/scripts/measure.sh"
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
printf '%s\n' "$out" | qgrep -x 'files 10' && printf '%s\n' "$out" | qgrep -x 'p50 50' && printf '%s\n' "$out" | qgrep -x 'p75 80' && printf '%s\n' "$out" | qgrep -x 'p90 90'; check "file-size percentiles (nearest-rank)" $?
printf '%s\n' "$out" | qgrep -x 'max 100 src/f10.ts'; check "file-size max with path" $?
out="$(m file-size)"
printf '%s\n' "$out" | qgrep -x 'files 13' && printf '%s\n' "$out" | qgrep -x 'over:200 2' && printf '%s\n' "$out" | qgrep -x 'over:500 1' && printf '%s\n' "$out" | qgrep -x 'over:1000 0' && printf '%s\n' "$out" | qgrep -x 'over:300 1'; check "file-size over:N buckets, binary skipped" $?
ro file-size file-size

# --- tree
R="$(new_repo)"; for f in src/a/x.ts src/a/y.ts src/b/z.ts README.md; do mkdir -p "$R/$(dirname "$f")"; echo 1 > "$R/$f"; done; commit
out="$(m tree 2)"
printf '%s\n' "$out" | qgrep -x "$(printf '2\tsrc/a')" && printf '%s\n' "$out" | qgrep -x "$(printf '1\tsrc/b')"; check "tree 2 counts per directory, largest first" $?
out="$(m tree 1)"; printf '%s\n' "$out" | qgrep "$(printf '3\tsrc')"; check "tree 1 groups by first component" $?
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
printf '%s\n' "$out" | qgrep -x "$(printf 'app\tdomain\t1')" && printf '%s\n' "$out" | tail -1 | qgrep -x 'unresolved 2'; check "imports ts matrix + unresolved" $?
ro imports-ts imports ts src

# --- framework-imports
R="$(new_repo)"; d="$R/src/main/java/com/acme/domain"; mkdir -p "$d"
printf 'import org.springframework.stereotype.Service;\nimport java.util.List;\nimport jakarta.persistence.Entity;\n' > "$d/A.java"; commit
out="$(m framework-imports src/main/java/com/acme/domain)"
printf '%s\n' "$out" | qgrep -x "$(printf 'org.springframework\t1')" && printf '%s\n' "$out" | qgrep -x "$(printf 'jakarta.\t1')"; check "framework-imports" $?
ro framework-imports framework-imports src

# --- tests
R="$(new_repo)"; mkdir -p "$R/src/main/java/a" "$R/src/test/java/a" "$R/e2e"
echo c > "$R/src/main/java/a/Foo.java"; echo c > "$R/src/main/java/a/Baz.java"
echo c > "$R/src/test/java/a/FooTest.java"; echo c > "$R/src/test/java/a/BarIT.java"; echo c > "$R/e2e/login.spec.ts"
printf 'plugins { id("info.solidsoft.pitest") version "1.15.0" }\njacoco {}\n' > "$R/build.gradle.kts"; commit
out="$(m tests)"
for l in 'main 2' 'test 3' 'unit 1' 'integration 1' 'e2e 1' 'untested_main 1' 'mutation_tool pitest' 'coverage_tool jacoco'; do
  printf '%s\n' "$out" | qgrep -x "$l"; check "tests: $l" $?
done
R="$(new_repo)"; echo c > "$R/a.txt"; commit; out="$(m tests)"; printf '%s\n' "$out" | qgrep -x 'mutation_tool none' && printf '%s\n' "$out" | qgrep -x 'coverage_tool none'; check "tests: none tools" $?
ro tests tests

# --- pattern
R="$(new_repo)"; mkdir -p "$R/src" "$R/lib"
printf 'console.log(1);\nok();\nconsole.log(2);\nconsole.debug(3);\n' > "$R/src/a.ts"; printf 'console.log(9);\n' > "$R/src/b.ts"
printf 'console.log(5);\n' > "$R/lib/c.ts"; printf 'clean();\n' > "$R/src/clean.ts"; printf 'console.log\0\1\n' > "$R/src/blob.bin"
printf 'console.log(7);\n' > "$R/src/my file: ação.ts"; commit
out="$(m pattern 'console\.(log|debug)\(' src)"
printf '%s\n' "$out" | qgrep -x 'checked 5' && printf '%s\n' "$out" | qgrep -x 'files 3' && printf '%s\n' "$out" | qgrep -x 'total 5'; check "pattern: checked, files with a match and total matching lines (binary skipped)" $?
printf '%s\n' "$out" | qgrep -x "$(printf '3\tsrc/a.ts')" && printf '%s\n' "$out" | qgrep -x "$(printf '1\tsrc/my file: ação.ts')"; check "pattern: the top files, with a space, a colon and non-ASCII in a path" $?
[ "$(printf '%s\n' "$out" | sed -n '4p')" = "$(printf '3\tsrc/a.ts')" ]; check "pattern: the largest count comes first" $?
out="$(m pattern 'console\.log')"; printf '%s\n' "$out" | qgrep -x 'files 4' && printf '%s\n' "$out" | qgrep -x 'total 5'; check "pattern: no pathspec measures every tracked file" $?
out="$(m pattern 'nothing-like-this')"; printf '%s\n' "$out" | qgrep -x 'files 0' && printf '%s\n' "$out" | qgrep -x 'total 0'; check "pattern: no match gives zeros" $?
ro pattern pattern 'console' src
m pattern >/dev/null; [ $? -eq 64 ]; check "pattern: no ERE -> rc 64" $?
m pattern 'foo(' >/dev/null; [ $? -eq 64 ]; check "pattern: an invalid ERE -> rc 64" $?

# --- deps (F3d-2): direct dependencies per manifest, read with the dependencies sensor's parsers
R="$(new_repo)"; mkdir -p "$R/svc"
printf '{ "dependencies": {"a": "1", "b": "2"}, "devDependencies": {"c": "3"} }\n' > "$R/package.json"
printf 'dependencies {\n  implementation("g:a:1")\n  implementation(project(":core"))\n}\n' > "$R/svc/build.gradle.kts"
commit
out="$(m deps)"
printf '%s\n' "$out" | qgrep -x 'manifests 2' && printf '%s\n' "$out" | qgrep -x 'direct 4'; check "deps: manifests and direct dependencies" $?
printf '%s\n' "$out" | qgrep -x "$(printf '3\tpackage.json')" && printf '%s\n' "$out" | qgrep -x "$(printf '1\tsvc/build.gradle.kts')"; check "deps: count per manifest, largest first" $?
[ "$(printf '%s\n' "$out" | sed -n '3p')" = "$(printf '3\tpackage.json')" ]; check "deps: the largest manifest comes first" $?
out="$(m deps svc)"; printf '%s\n' "$out" | qgrep -x 'manifests 1' && printf '%s\n' "$out" | qgrep -x 'direct 1'; check "deps: a pathspec limits the manifests" $?
ro deps deps
R="$(new_repo)"; echo x > "$R/a.txt"; commit
out="$(m deps)"; printf '%s\n' "$out" | qgrep -x 'manifests 0' && printf '%s\n' "$out" | qgrep -x 'direct 0'; check "deps: no manifest gives zeros" $?

# --- unknown
R="$(new_repo)"; m bogus >/dev/null; [ $? -eq 64 ]; check "unknown subcommand rc 64" $?
# --- language (runs the code-language sensor from the plugin, in a repository without scripts/lib/)
R="$(new_repo)"; mkdir -p "$R/src"; printf 'const valorTotal = 1; // calcula o total\n' > "$R/src/a.ts"; commit
out="$(m language pt.txt src)"
printf '%s\n' "$out" | qgrep -x 'files 1' && printf '%s\n' "$out" | qgrep -x 'flagged 2'; check "language measures with the bundled stop-list and libraries" $?
ro language language pt.txt src
finish
