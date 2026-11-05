#!/usr/bin/env bash
# baymax v0.5 read-only scripts: discover.sh and measure.sh print facts and write nothing.
# shellcheck disable=SC2319  # "check ... $?" after a test is this suite's idiom (see baymax_helpers.sh)
set -uo pipefail
. "$(dirname "$0")/baymax_helpers.sh"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SC="$REPO_ROOT/plugins/baymax/skills/harness/scripts"
FX="$REPO_ROOT/tests/fixtures/baymax-v05"
W="$(mktemp -d)"; _bmax_tmps="$_bmax_tmps $W"
TAB="$(printf '\t')"

bash -n "$SC/discover.sh" && bash -n "$SC/measure.sh"; check "discover.sh and measure.sh pass bash -n" $?
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$SC/discover.sh" "$SC/measure.sh"; check "discover.sh and measure.sh are shellcheck clean" $?
else
  echo "  skip shellcheck: not installed"
fi

# mkrepo STACK -> a git repository with the fixture, conventional commits and two prefixed branches
mkrepo() {
  local d
  d="$(mktemp -d "$W/$1.XXXXXX")" && cp -R "$FX/$1/." "$d/"
  (cd "$d" && git init -q . && git config user.email t@t && git config user.name t && git config core.quotepath off \
    && git add -A && git commit -q -m "feat: first" \
    && echo a > a.txt && git add a.txt && git commit -q -m "fix(core): second" \
    && echo b > b.txt && git add b.txt && git commit -q -m "chore: third" \
    && echo c > c.txt && git add c.txt && git commit -q -m "plain message" \
    && git branch feat/one && git branch feat/two && git branch fix/three) >/dev/null 2>&1
  printf '%s\n' "$d"
}
has_line() { printf '%s\n' "$1" | grep -qxF -- "$2"; }
line() { printf '%s' "$1$TAB$2"; [ -n "${3:-}" ] && printf '%s%s' "$TAB" "$3"; printf '\n'; }

# snapshot REPO -> a digest of the tree: git status, every file's hash outside .git
snapshot() {
  (cd "$1" && git status --porcelain --ignored && find . -path ./.git -prune -o -type f -print0 | sort -z | xargs -0 sha256sum && find . -path ./.git -prune -o -type d -print | sort)
}

# ------------------------------------------------------------------ discover.sh
r="$(mkrepo typescript)"
before="$(snapshot "$r")"; touch "$W/stamp"; sleep 1
out="$(cd "$r" && bash "$SC/discover.sh" 2>&1)"; rc=$?
[ "$rc" -eq 0 ]; check "discover.sh typescript: exit 0" $?
has_line "$out" "$(line language typescript '2 files')" ; check "discover typescript: language typescript" $?
has_line "$out" "$(line package-manager pnpm pnpm-lock.yaml)"; check "discover typescript: package-manager pnpm" $?
printf '%s\n' "$out" | grep -qE "^runtime${TAB}node${TAB}(v[0-9][0-9.]*|not installed|unknown), no pin$"; check "discover typescript: runtime node <version>, no pin" $?
printf '%s\n' "$out" | grep -qxE "test-runner${TAB}vitest(${TAB}.*)?"; check "discover typescript: test-runner vitest" $?
printf '%s\n' "$out" | grep -qxE "test-runner${TAB}playwright(${TAB}.*)?"; check "discover typescript: test-runner playwright (from package.json)" $?
has_line "$out" "$(line arch-tool dependency-cruiser .dependency-cruiser.cjs)"; check "discover typescript: arch-tool dependency-cruiser with its config" $?
has_line "$out" "$(line linter eslint eslint.config.js)"; check "discover typescript: linter eslint" $?
has_line "$out" "$(line formatter prettier .prettierrc)"; check "discover typescript: formatter prettier" $?
has_line "$out" "$(line type-checker tsc 'tsconfig.json (strict)')"; check "discover typescript: type-checker tsc (strict)" $?
has_line "$out" "$(line githook-manager husky .husky)"; check "discover typescript: githook-manager husky" $?
has_line "$out" "$(line commit-convention 'conventional 75%' '3 of 4 subjects')"; check "discover: commit-convention conventional 75% from the last subjects" $?
has_line "$out" "$(line branch-pattern 'feat/*' '2 branches')" && has_line "$out" "$(line branch-pattern 'fix/*' '1 branches')"; check "discover: branch-pattern counts prefixes" $?
has_line "$out" "$(line agents-dir absent)" && has_line "$out" "$(line bmax absent)"; check "discover: no .agents/ -> agents-dir absent, bmax absent" $?
! printf '%s\n' "$out" | grep -qE "^instructions${TAB}"; check "discover typescript: no instruction files yet" $?
[ "$(snapshot "$r")" = "$before" ]; check "discover.sh leaves the tree unchanged (git status --ignored and every file hash)" $?
[ -z "$(cd "$r" && find . -path ./.git -prune -o -type f -newer "$W/stamp" -print)" ]; check "discover.sh creates and modifies no file (find -newer)" $?

r="$(mkrepo python)"
out="$(cd "$r" && bash "$SC/discover.sh" 2>&1)"
has_line "$out" "$(line language python '2 files')"; check "discover python: language python" $?
has_line "$out" "$(line package-manager uv uv.lock)"; check "discover python: package-manager uv" $?
printf '%s\n' "$out" | grep -qxE "test-runner${TAB}pytest(${TAB}.*)?"; check "discover python: test-runner pytest" $?
printf '%s\n' "$out" | grep -qxE "linter${TAB}ruff(${TAB}.*)?"; check "discover python: linter ruff" $?
printf '%s\n' "$out" | grep -qxE "type-checker${TAB}mypy(${TAB}.*)?"; check "discover python: type-checker mypy" $?
printf '%s\n' "$out" | grep -qxE "arch-tool${TAB}import-linter(${TAB}.*)?"; check "discover python: arch-tool import-linter" $?
has_line "$out" "$(line githook-manager pre-commit .pre-commit-config.yaml)"; check "discover python: githook-manager pre-commit" $?

r="$(mkrepo jvm)"
out="$(cd "$r" && bash "$SC/discover.sh" 2>&1)"
has_line "$out" "$(line language java '2 files')"; check "discover jvm: language java" $?
has_line "$out" "$(line package-manager gradle wrapper)"; check "discover jvm: package-manager gradle with wrapper" $?
printf '%s\n' "$out" | grep -qxE "test-runner${TAB}junit(${TAB}.*)?"; check "discover jvm: test-runner junit" $?
printf '%s\n' "$out" | grep -qxE "arch-tool${TAB}archunit(${TAB}.*)?"; check "discover jvm: arch-tool archunit" $?
has_line "$out" "$(line linter checkstyle config/checkstyle/checkstyle.xml)"; check "discover jvm: linter checkstyle with its config" $?

r2="$(mkrepo typescript)"
printf '{"name":"x","engines":{"node":">=22"}}\n' > "$r2/package.json"
printf '%s\n' "$(cd "$r2" && bash "$SC/discover.sh")" | grep -qE "^runtime${TAB}node${TAB}v?[^,${TAB}]+, package.json engines$"; check "discover: runtime reports a package.json engines pin" $?
printf 'v22\n' > "$r2/.nvmrc"
printf '%s\n' "$(cd "$r2" && bash "$SC/discover.sh")" | grep -qE "^runtime${TAB}node${TAB}[^,${TAB}]+, \.nvmrc$"; check "discover: runtime reports a .nvmrc pin" $?

# ignored harness paths and ignored directories (round 3)
r="$(mkrepo typescript)"
mkdir -p "$r/node_modules/x" "$r/build/out" "$r/.claude/worktrees/w" "$r/.claude/skills/local"
echo m > "$r/node_modules/x/a.js"; echo b > "$r/build/out/b.js"; echo s > "$r/.claude/skills/local/SKILL.md"
printf 'node_modules/\nbuild/\n.claude/\n' > "$r/.gitignore"
before="$(snapshot "$r")"
out="$(cd "$r" && bash "$SC/discover.sh" 2>&1)"
for p in .claude/settings.json .claude/agents/baymax-reviewer.md; do has_line "$out" "$(line ignored "$p")"; check "discover: a broad .claude/ rule -> ignored $p" $?; done
! printf '%s\n' "$out" | grep -qE "^ignored${TAB}(AGENTS.md|CLAUDE.md|\.agents/bmax\.yml|\.agents/bin/bmax)$"; check "discover: harness paths the rules do not hide are not reported" $?
for d in node_modules/ build/ .claude/; do has_line "$out" "$(line ignored-dir "$d")"; check "discover: ignored-dir $d" $?; done
! printf '%s\n' "$out" | grep -qE "^ignored-dir${TAB}\.claude/.+"; check "discover: only the top-most ignored directory is listed (not .claude/skills/ inside .claude/)" $?
[ "$(snapshot "$r")" = "$before" ]; check "discover with ignore rules leaves the tree unchanged" $?
# a narrow rule: only the exact path
printf '.claude/*\n!.claude/settings.json\n!.claude/agents/\n' > "$r/.gitignore"
out="$(cd "$r" && bash "$SC/discover.sh" 2>&1)"
! printf '%s\n' "$out" | grep -qE "^ignored${TAB}"; check "discover: .claude/* with !.claude/settings.json and !.claude/agents/ hides no harness path" $?
printf 'AGENTS.md\n.agents/\n' > "$r/.gitignore"
out="$(cd "$r" && bash "$SC/discover.sh" 2>&1)"
has_line "$out" "$(line ignored AGENTS.md)" && has_line "$out" "$(line ignored .agents/bmax.yml)" && has_line "$out" "$(line ignored .agents/bin/bmax)" && has_line "$out" "$(line ignored .agents/githooks/pre-commit)"; check "discover: ignored lists AGENTS.md and the .agents/ paths when they are ignored" $?
# the cap
r3="$(mkrepo typescript)"
for i in $(seq 1 60); do mkdir -p "$r3/gen$i/sub"; echo x > "$r3/gen$i/sub/f"; done
printf 'gen*/\n' > "$r3/.gitignore"
out="$(cd "$r3" && bash "$SC/discover.sh" 2>&1)"
[ "$(printf '%s\n' "$out" | grep -c "^ignored-dir${TAB}")" -eq 50 ] && printf '%s\n' "$out" | grep -qE "^ignored-dir-truncated${TAB}10${TAB}"; check "discover: at most 50 ignored-dir lines, then ignored-dir-truncated says how many were left out" $?

# instruction files, agent hooks, .agents/ and bmax
r="$(mkrepo typescript)"
mkdir -p "$r/.agents" "$r/.claude" "$r/.github" "$r/pkg"
printf '# a\nline\n' > "$r/AGENTS.md"; printf '@AGENTS.md\n' > "$r/CLAUDE.md"; printf 'x\n' > "$r/.github/copilot-instructions.md"; printf '# n\n' > "$r/pkg/AGENTS.md"
printf '{"hooks":{"PreToolUse":[],"Stop":[]}}\n' > "$r/.claude/settings.json"
printf 'version: 1\n' > "$r/.agents/bmax.yml"; printf 'version=0.5.0\n' > "$r/.agents/bmax.lock"; mkdir -p "$r/.agents/skills"
(cd "$r" && git add -A)
before="$(snapshot "$r")"
out="$(cd "$r" && bash "$SC/discover.sh" 2>&1)"
has_line "$out" "$(line instructions AGENTS.md '2 lines')" && has_line "$out" "$(line instructions CLAUDE.md '1 lines')" && has_line "$out" "$(line instructions .github/copilot-instructions.md '1 lines')"; check "discover: instructions lists AGENTS.md, CLAUDE.md and copilot-instructions.md with their sizes" $?
has_line "$out" "$(line instructions 'nested AGENTS.md' '1 below the root')"; check "discover: nested AGENTS.md counted" $?
has_line "$out" "$(line agent-hooks .claude/settings.json 'PreToolUse,Stop')"; check "discover: agent-hooks lists the events of .claude/settings.json" $?
has_line "$out" "$(line agents-dir bmax.yml file)" && has_line "$out" "$(line agents-dir skills dir)"; check "discover: agents-dir lists what is under .agents/" $?
has_line "$out" "$(line bmax 'installed 0.5.0' .agents/bmax.lock)"; check "discover: bmax installed <version> from bmax.lock" $?
[ "$(snapshot "$r")" = "$before" ]; check "discover.sh leaves the tree unchanged here too" $?

# outside a git repository, and a bad directory
nogit="$W/nogit"; mkdir -p "$nogit/src"; echo 'x = 1' > "$nogit/src/a.py"
out="$(cd "$nogit" && bash "$SC/discover.sh" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && has_line "$out" "$(line commit-convention none 'no commits')"; check "discover: outside git it still prints facts and commit-convention none" $?
bash "$SC/discover.sh" "$W/does-not-exist" >/dev/null 2>&1; [ $? -eq 1 ]; check "discover: a missing directory exits 1" $?
out="$(bash "$SC/discover.sh" "$r" 2>&1)"; has_line "$out" "$(line bmax 'installed 0.5.0' .agents/bmax.lock)"; check "discover: takes the directory as an argument" $?

# every output line has 2 or 3 tab-separated fields
out="$(cd "$(mkrepo typescript)" && bash "$SC/discover.sh")"
bad="$(printf '%s\n' "$out" | awk -F'\t' 'NF < 2 || NF > 3 || $1 == "" || $2 == ""')"
[ -z "$bad" ]; check "discover: every line is key<TAB>value[<TAB>detail]" $?
[ -z "$bad" ] || printf '%s\n' "$bad"

# ------------------------------------------------------------------ measure.sh
r="$W/m"; mkdir -p "$r/src/main/java/com/acme/domain" "$r/src/main/java/com/acme/adapter" "$r/src/test/java/com/acme" "$r/app/domain" "$r/app/infra" "$r/web/src/ui" "$r/web/src/data" "$r/tests"
printf 'package com.acme.domain;\nimport com.acme.adapter.Db;\nimport org.springframework.stereotype.Service;\nimport java.util.List;\npublic class Order {}\n' > "$r/src/main/java/com/acme/domain/Order.java"
printf 'package com.acme.adapter;\nimport com.acme.domain.Order;\npublic class Db {}\n' > "$r/src/main/java/com/acme/adapter/Db.java"
printf 'package com.acme;\nclass OrderTest {}\n' > "$r/src/test/java/com/acme/OrderTest.java"
printf 'from app.infra import db\nimport os\nimport django\n' > "$r/app/domain/order.py"
printf 'from app.domain import order\n' > "$r/app/infra/db.py"
printf '' > "$r/app/__init__.py"
printf "import { x } from '../data/repo'\nexport const y = x\n" > "$r/web/src/ui/page.ts"
printf "export const x = 1\n" > "$r/web/src/data/repo.ts"
printf 'def test_a():\n    pass\n' > "$r/tests/test_order.py"
(cd "$r" && git init -q . && git config user.email t@t && git config user.name t && git add -A && git commit -q -m "feat: a (#12)" && echo 1 > x && git add x && git commit -q -m "Fix the thing ABC-123" )
M() { (cd "$r" && bash "$SC/measure.sh" "$@" 2>&1); }
before="$(snapshot "$r")"
out="$(M tree 2)"
printf '%s\n' "$out" | grep -qE "^[0-9]+${TAB}src/main"; check "measure tree 2: count<TAB>dir" $?
out="$(M imports java com.acme)"
has_line "$out" "domain${TAB}adapter${TAB}1" && has_line "$out" "adapter${TAB}domain${TAB}1"; check "measure imports java: the matrix between packages" $?
out="$(M imports python app)"
has_line "$out" "domain${TAB}infra${TAB}1" && has_line "$out" "infra${TAB}domain${TAB}1"; check "measure imports python: the matrix between packages" $?
out="$(M imports ts web/src)"
has_line "$out" "ui${TAB}data${TAB}1" && printf '%s\n' "$out" | grep -qx "unresolved 0"; check "measure imports ts: relative imports resolved between top-level dirs" $?
out="$(M framework-imports src)"
has_line "$out" "org.springframework${TAB}1"; check "measure framework-imports: framework prefix and count" $?
out="$(M tests)"
printf '%s\n' "$out" | grep -qx "test 2" && printf '%s\n' "$out" | grep -q '^mutation_tool none$' && printf '%s\n' "$out" | grep -q '^coverage_tool none$'; check "measure tests: counts and tools" $?
out="$(M commits)"
printf '%s\n' "$out" | grep -qx "commits 2" && printf '%s\n' "$out" | grep -qx "conventional 1" && printf '%s\n' "$out" | grep -qx "ticket_refs 2" && printf '%s\n' "$out" | grep -qx "type:feat 1"; check "measure commits: subject statistics" $?
M file-size >/dev/null 2>&1; [ $? -eq 64 ]; check "measure: file-size is gone (bmax measure file-size); unknown subcommand exits 64" $?
M bogus >/dev/null 2>&1; [ $? -eq 64 ]; check "measure: an unknown subcommand exits 64" $?
M imports >/dev/null 2>&1; [ $? -eq 64 ]; check "measure imports without arguments exits 64" $?
[ "$(snapshot "$r")" = "$before" ]; check "measure.sh leaves the tree unchanged" $?
! grep -qE 'file-size|code-language|BMAX_MEASURE' "$SC/measure.sh" || grep -vE '^#' "$SC/measure.sh" | grep -qE 'cmd_(file_size|language|pattern|deps)'; check "measure.sh has no subcommand that duplicates a builtin" $?
TMPDIR="$W/no-such-dir" bash "$SC/measure.sh" tests >/dev/null 2>&1; [ $? -eq 1 ]; check "measure: no usable temporary directory -> exit 1, nothing written in the repository" $?

finish
