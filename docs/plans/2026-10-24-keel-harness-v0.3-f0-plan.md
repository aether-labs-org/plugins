# keel-harness v0.3 — F0 Fixes: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or superpowers:subagent-driven-development) to implement this plan task by task. Steps use checkbox (`- [ ]`) syntax for tracking. Follow the steps in order; each task starts with a failing test.

**Goal:** Close the v0.2 defects D-1…D-5 recorded in `docs/specs/2026-10-23-keel-harness-v0.3-design.md` §6, as phase F0 of `docs/plans/2026-10-23-keel-harness-v0.3-plan.md`. Above all D-1: today an agent can loosen its own baseline in the same change and the gate passes.

**Architecture:** Two new installed assets. `lib/envparse.sh` reads `KEY=value` files without executing them and replaces the nine `eval "$(tr -d '\r' < …)"` calls. `sensors/common/guard.sh` is a `security` sensor that compares the harness with the commit the branch started from. It fails when a baseline row grew or appeared, a rule limit relaxed, a list widened, `ENFORCEMENT` changed, a rule was deleted, a gate budget grew, or a sensor was removed or disabled, unless an ADR added in the same change names the loosened file. `build` installs both, `harness-check` gains a 13th check (`guard-missing`), and the docs follow.

**Tech stack:** bash 3.2-compatible shell, awk, git; the repository's own test harness (`tests/*.sh`, `tests/keel_helpers.sh`); `shellcheck`; `claude plugin validate`.

**Spec:** read `docs/specs/2026-10-23-keel-harness-v0.3-design.md` §5.3, §6 and decisions D32, D33 before Task 1.

**Provenance:** every file and edit below was prototyped on 2026-10-24 in a scratch clone of this branch at `0b52e55` and run there. Results: `./tests/run.sh` exit 0 with 991 `ok` (946 before), with `shellcheck` on `PATH` and without it; `claude plugin validate ./plugins/keel-harness --strict` passed; both edited eval scaffolds pass `bash -n`. The content is copied here **verbatim**: copy it, do not re-derive it. If a step's actual output differs from the expected output written here, stop and report instead of improvising.

## Global constraints

- Code, comments, docs and commit messages in **English**.
- Everything under `skills/*/assets/` is installed into user repositories. It stays bash 3.2-compatible (no `mapfile`, no `declare -A`, no `${x,,}`), uses no `jq`, no network and no model, and contains no `CLAUDE_` variable or `keel-harness/` path. `tests/keel_assets_test.sh` enforces this.
- `skills/build/SKILL.md` stays at or under 250 lines (`tests/build_test.sh`).
- **Git:** work on the branch you were given. Commit once per task with the message shown, push to that branch after each commit, and **never open a pull request without the owner's explicit approval**.
- Do not bump the plugin version. The release happens at the end of v0.3, not in F0.
- Do not start F1. Stop after Task 7 and report.

## Prerequisites

| Tool | Needed for | Check |
| --- | --- | --- |
| bash, git, awk | everything | `bash --version; git --version` |
| `jq` | existing tests (`keel_stop_hook_test.sh`) | `jq --version` |
| `shellcheck` | `tests/keel_assets_test.sh` (skipped locally without it after Task 1; required in CI) | `shellcheck --version` (no root: `python3 -m venv .venv && .venv/bin/pip install shellcheck-py`) |
| `claude` CLI | `make validate` | `claude --version` |

Baseline before Task 1: `./tests/run.sh` must exit 0 with `shellcheck` installed. Without it, the 25 `shellcheck:` assertions fail; that is defect D-5, fixed in Task 1.

---

## Task 1 — D-5: skip `shellcheck` locally when it is missing, require it in CI

**Files:** modify `tests/keel_assets_test.sh`.

- [ ] **Step 1: see the failure.** Run with `shellcheck` absent from `PATH`:
  `env PATH=/usr/bin:/bin bash tests/keel_assets_test.sh | grep -c 'FAIL shellcheck'`
  Expected: a count above zero (25 at `0b52e55`). If `shellcheck` lives in `/usr/bin`, skip this step.
- [ ] **Step 2: apply the edit.**

```diff
diff --git a/tests/keel_assets_test.sh b/tests/keel_assets_test.sh
index 4bbab86..ee997a7 100644
--- a/tests/keel_assets_test.sh
+++ b/tests/keel_assets_test.sh
@@ -6,7 +6,13 @@ while IFS= read -r f; do
   [ -n "$f" ] || continue
   n=$((n+1))
   rel="${f#"$KEEL"/}"
-  shellcheck -S warning "$f" >/dev/null 2>&1; check "shellcheck: $rel" $?
+  if command -v shellcheck >/dev/null 2>&1; then
+    shellcheck -S warning "$f" >/dev/null 2>&1; check "shellcheck: $rel" $?
+  elif [ -n "${CI:-}" ]; then
+    fail "shellcheck: $rel (shellcheck is required in CI)"
+  else
+    echo "  skip shellcheck: $rel (shellcheck not installed)"
+  fi
   ! grep -nE 'declare -A|mapfile|readarray|\$\{[A-Za-z_]+(,,|\^\^)\}|(^|[^a-z_])jq( |$)' "$f" >/dev/null; check "bash3.2/no-jq: $rel" $?
   case "$f" in
     */skills/build/assets/*|*/skills/rules/assets/sensors/*)
```

- [ ] **Step 3: verify.**
  - `env PATH=/usr/bin:/bin bash tests/keel_assets_test.sh; echo rc=$?`: `skip shellcheck:` lines and `rc=0`.
  - `env PATH=/usr/bin:/bin CI=1 bash tests/keel_assets_test.sh; echo rc=$?`: `FAIL shellcheck: … (shellcheck is required in CI)` and `rc=1`.
  - With `shellcheck` installed: `bash tests/keel_assets_test.sh; echo rc=$?` gives `rc=0`.
- [ ] **Step 4: commit and push.** `test(keel-harness): skip shellcheck locally when missing, require it in CI (D-5)`

---

## Task 2 — D-2: `lib/envparse.sh`, a `KEY=value` reader that executes nothing

**Files:** create `tests/keel_envparse_test.sh` and `plugins/keel-harness/skills/build/assets/lib/envparse.sh`.

- [ ] **Step 1: write the failing test.** Create `tests/keel_envparse_test.sh` (executable: `chmod +x`):

```bash
#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/keel_helpers.sh"
LIB="$KEEL/skills/build/assets/lib/envparse.sh"
[ -f "$LIB" ]; check "envparse.sh exists" $?

d="$(mktemp -d)"; _keel_tmps="$_keel_tmps $d"
# load FILE -> prints the named variables, one per line, or "ERR <message>"
load() {
  local f="$1"; shift
  bash -c '. "$1"; f="$2"; shift 2
    keel_env_load "$f" || { echo "ERR $KEEL_ENV_ERROR"; exit 1; }
    for k in "$@"; do eval "printf \"%s=[%s]\\n\" \"\$k\" \"\${$k-}\""; done' _ "$LIB" "$f" "$@"
}

cat > "$d/ok.env" <<'E'
# Managed by keel-harness - see .agents/README.md
RULE_ID=file-size
KIND=metric                       # metric | structure
  LIMIT=300
INCLUDE='src/'
LAYERS='domain|src/d|com.d||domainModels
web|src/w|com.w|domain|adapter'
NOTE="it's fine"   # trailing comment
LITERAL=$HOME
EMPTY=
E
printf 'CRLF=yes\r\nLAST=noeol' >> "$d/ok.env"
out="$(load "$d/ok.env" RULE_ID KIND LIMIT INCLUDE LAYERS NOTE LITERAL EMPTY CRLF LAST)"
[ "$out" = 'RULE_ID=[file-size]
KIND=[metric]
LIMIT=[300]
INCLUDE=[src/]
LAYERS=[domain|src/d|com.d||domainModels
web|src/w|com.w|domain|adapter]
NOTE=[it'"'"'s fine]
LITERAL=[$HOME]
EMPTY=[]
CRLF=[yes]
LAST=[noeol]' ]; check "parses comments, quotes, multi-line, CRLF, no trailing newline; expands nothing" $?

for case in 'X=$(touch PWNED)|contains $( or a backtick' 'X=`id`|contains $( or a backtick' \
            "X='open|unterminated quote" 'not a line|not a KEY=value line' 'lower=1|not a KEY=value line' \
            "X='a' junk|unexpected text after the closing quote"; do
  printf '%s\n' "${case%%|*}" > "$d/bad.env"
  out="$(cd "$d" && load "$d/bad.env" X)"; rc=$?
  [ $rc -ne 0 ] && printf '%s' "$out" | grep -qF "${case#*|}" && printf '%s' "$out" | grep -qF 'bad.env:1:'
  check "rejects '${case%%|*}' with file:line and reason" $?
done
[ ! -e "$d/PWNED" ]; check "nothing in an env file is executed" $?

finish
```

- [ ] **Step 2: run it.** `bash tests/keel_envparse_test.sh`. Expected: the first line is `  FAIL envparse.sh exists` and the exit code is non-zero.
- [ ] **Step 3: create the library** `plugins/keel-harness/skills/build/assets/lib/envparse.sh` (`chmod +x`):

```bash
#!/usr/bin/env bash
# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.
# envparse.sh - reads KEY=value files without executing them. Sourced as: . scripts/lib/envparse.sh
# Accepts blank lines, `#` comment lines, unquoted values (a trailing ` # comment` is dropped) and
# single- or double-quoted values, which may span lines. Nothing is expanded: `$VAR` stays literal,
# and a value containing `$(` or a backtick is rejected, because v0.2 would have executed it.

KEEL_ENV_ERROR=""

# keel_env_load FILE -> sets each KEY in the caller's shell; returns 1 with KEEL_ENV_ERROR set.
keel_env_load() {
  local file="$1" n=0 line t key rest q="" buf="" open="" start=0
  KEEL_ENV_ERROR=""
  if [ ! -f "$file" ]; then KEEL_ENV_ERROR="$file: no such file"; return 1; fi
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    line="${line%$'\r'}"
    if [ -n "$open" ]; then
      case "$line" in
        *"$q"*)
          buf="$buf"$'\n'"${line%%"$q"*}"
          _keel_env_tail "$file" "$n" "${line#*"$q"}" || return 1
          _keel_env_set "$file" "$start" "$key" "$buf" || return 1
          open="" ;;
        *) buf="$buf"$'\n'"$line" ;;
      esac
      continue
    fi
    t="${line#"${line%%[![:space:]]*}"}"
    case "$t" in '' | '#'*) continue ;; esac
    key="${t%%=*}"
    case "$key" in
      "$t" | '' | [0-9]* | *[!A-Z0-9_]*)
        KEEL_ENV_ERROR="$file:$n: not a KEY=value line (keys are UPPER_CASE)"; return 1 ;;
    esac
    rest="${t#*=}"
    case "$rest" in
      \'* | \"*)
        q="${rest:0:1}"; rest="${rest:1}"
        case "$rest" in
          *"$q"*)
            _keel_env_tail "$file" "$n" "${rest#*"$q"}" || return 1
            _keel_env_set "$file" "$n" "$key" "${rest%%"$q"*}" || return 1 ;;
          *) open=1; start=$n; buf="$rest" ;;
        esac ;;
      *)
        rest="${rest%%[[:space:]]#*}"
        rest="${rest%"${rest##*[![:space:]]}"}"
        _keel_env_set "$file" "$n" "$key" "$rest" || return 1 ;;
    esac
  done < "$file"
  if [ -n "$open" ]; then KEEL_ENV_ERROR="$file:$start: $key has an unterminated quote"; return 1; fi
  return 0
}

# _keel_env_tail FILE LINE REST -> what follows a closing quote must be blank or a comment.
_keel_env_tail() {
  local t="${3#"${3%%[![:space:]]*}"}"
  case "$t" in '' | '#'*) return 0 ;; esac
  KEEL_ENV_ERROR="$1:$2: unexpected text after the closing quote"
  return 1
}

# _keel_env_set FILE LINE KEY VALUE
_keel_env_set() {
  case "$4" in
    *'$('* | *'`'*) KEEL_ENV_ERROR="$1:$2: $3 contains \$( or a backtick, which keel never executes"; return 1 ;;
  esac
  printf -v "$3" '%s' "$4"
}

# keel_env_load_sensor ID CLASS FILE -> loads FILE, or prints a fail line 1 with guidance and exits 1.
keel_env_load_sensor() {
  keel_env_load "$3" && return 0
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" fail "rule env file could not be read: $KEEL_ENV_ERROR"
  printf '  guidance: %s\n' "Fix that line of $3: plain KEY=value, quoted values may span lines, and nothing in it is executed. Do not delete the file or move the sensor to disabled/ to make this pass."
  exit 1
}
```

  Design notes:
  - Keys must be UPPER_CASE, so a key can never overwrite the parser's own lower-case locals.
  - `$VAR` stays literal, where `eval` would have expanded it. A value containing `$(` or a backtick fails, where `eval` would have run it.
- [ ] **Step 4: run it.** `bash tests/keel_envparse_test.sh` → 9 `ok`, exit 0; `./tests/run.sh; echo rc=$?` → `rc=0`.
- [ ] **Step 5: commit and push.** `feat(keel-harness): envparse library that reads env files without executing them (D-2)`

---

## Task 3 — D-2: the nine `eval` calls become `envparse`

**Files:** modify the eight rule sensors, `skills/rules/assets/architecture/render.sh`, `tests/keel_rule_sensors_test.sh`, `tests/keel_envparse_test.sh`, `skills/rules/references/rule-env.md`.

- [ ] **Step 1: write the failing sensor-level tests.** Append this block to `tests/keel_envparse_test.sh`, just before its final `finish` line:

```bash
# sensors: a hostile env file fails the sensor instead of running; a missing lib is a skip
r="$(new_repo)"
install_asset "$r" build/assets/lib/baseline.sh scripts/lib/baseline.sh
install_asset "$r" build/assets/lib/envparse.sh scripts/lib/envparse.sh
install_asset "$r" rules/assets/sensors/file-size.sh scripts/sensors/file-size.sh
mkdir -p "$r/.agents/rules" "$r/src"
printf 'LIMIT=$(touch PWNED)\nINCLUDE=src\n' > "$r/.agents/rules/file-size.env"
out="$(cd "$r" && bash scripts/sensors/file-size.sh)"; rc=$?
[ $rc -eq 1 ] && [ "$(printf '%s\n' "$out" | head -1 | cut -f1,3)" = "file-size	fail" ] && [ ! -e "$r/PWNED" ]
check "sensor: hostile env -> fail line 1, nothing executed" $?
printf '%s\n' "$out" | grep -q '^  guidance: '; check "sensor: hostile env -> guidance" $?
rm "$r/scripts/lib/envparse.sh"; printf 'LIMIT=10\nINCLUDE=src\n' > "$r/.agents/rules/file-size.env"
out="$(cd "$r" && bash scripts/sensors/file-size.sh)"; rc=$?
[ $rc -eq 2 ] && printf '%s' "$out" | head -1 | grep -q 'envparse.sh is missing'; check "sensor: missing lib -> skip naming it" $?
```

  Run `bash tests/keel_envparse_test.sh`. Expected: these three checks fail, because `eval` executes the hostile value. They pass after the next steps.
- [ ] **Step 2: replace the call in each of the eight sensors.** In every file below, replace the single line

```bash
eval "$(tr -d '\r' < "$RULE_ENV")"
```

  with exactly this block (the sensors already define `id` and `class` above it):

```bash
# shellcheck disable=SC1090,SC1091
. "${KEEL_ENVPARSE_LIB:-scripts/lib/envparse.sh}" 2>/dev/null || {
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "scripts/lib/envparse.sh is missing - run /keel-harness:build"
  exit 2
}
keel_env_load_sensor "$id" "$class" "$RULE_ENV"
```

  Files: `skills/rules/assets/sensors/architecture-grep.sh`, `skills/rules/assets/sensors/architecture.sh`, `skills/rules/assets/sensors/code-language.sh`, `skills/rules/assets/sensors/file-size.sh`, `skills/rules/assets/sensors/folder-layout.sh`, `skills/rules/assets/sensors/test-presence.sh`, `skills/rules/assets/sensors/slow/diff-coverage.sh`, `skills/rules/assets/sensors/slow/mutation.sh`.
- [ ] **Step 3: `render.sh`** (it runs from the plugin, so it sources the library by its plugin path):

```diff
diff --git a/plugins/keel-harness/skills/rules/assets/architecture/render.sh b/plugins/keel-harness/skills/rules/assets/architecture/render.sh
index 252991d..18d7de0 100755
--- a/plugins/keel-harness/skills/rules/assets/architecture/render.sh
+++ b/plugins/keel-harness/skills/rules/assets/architecture/render.sh
@@ -7,7 +7,7 @@
 #                    applicationServices|adapter|layer)
 #   FORBIDDEN lines  layer|import_prefix
 #   IGNORE_IMPORTS lines  importer -> imported   (import-linter's native baseline, brownfield)
-# Exit 64 on bad usage, 65 on an env file without STYLE or LAYERS.
+# Exit 64 on bad usage, 65 on an env file that cannot be read or lacks STYLE or LAYERS.
 set -uo pipefail
 
 target="${1:-}"; envf="${2:-}"
@@ -19,7 +19,9 @@ esac
 
 STYLE=""; LANG=""; BASE=""; LAYERS=""; FORBIDDEN=""; FREEZE=""; IGNORE_IMPORTS=""
 orig_lang="${LANG-}"
-eval "$(tr -d '\r' < "$envf")"
+# shellcheck disable=SC1091
+. "$(cd "$(dirname "$0")" && pwd)/../../../build/assets/lib/envparse.sh"
+keel_env_load "$envf" || { echo "render.sh: $KEEL_ENV_ERROR" >&2; exit 65; }
 LANG="$orig_lang"
 if [ -z "$STYLE" ] || [ -z "$LAYERS" ]; then
   echo "render.sh: $envf must define STYLE and LAYERS" >&2
```

- [ ] **Step 4: the rule-sensor tests install the library.**

```diff
diff --git a/tests/keel_rule_sensors_test.sh b/tests/keel_rule_sensors_test.sh
index d669aa0..9c0da80 100644
--- a/tests/keel_rule_sensors_test.sh
+++ b/tests/keel_rule_sensors_test.sh
@@ -7,6 +7,7 @@ RS="rules/assets/sensors"
 mk() {
   local r; r="$(new_repo)"
   install_asset "$r" build/assets/lib/baseline.sh scripts/lib/baseline.sh
+  install_asset "$r" build/assets/lib/envparse.sh scripts/lib/envparse.sh
   mkdir -p "$r/.agents/rules" "$r/.agents/baselines" "$r/src"
   printf '%s\n' "$r"
 }
```

- [ ] **Step 5: the contract describes the parser.**

```diff
diff --git a/plugins/keel-harness/skills/rules/references/rule-env.md b/plugins/keel-harness/skills/rules/references/rule-env.md
index 6b41f4a..2b2279b 100644
--- a/plugins/keel-harness/skills/rules/references/rule-env.md
+++ b/plugins/keel-harness/skills/rules/references/rule-env.md
@@ -1,7 +1,8 @@
 # Rule env file
 
 `.agents/rules/<rule-id>.env` holds the rule's metadata and its machine parameters; the prose stays
-in the topic file. It is plain `KEY=value` (bash-sourceable; CRLF is tolerated), committed, and every
+in the topic file. It is plain `KEY=value`, read by `scripts/lib/envparse.sh` and never sourced or
+executed (CRLF is tolerated; `$VAR` stays literal; a value with `$(` or a backtick fails), committed, and every
 rule has one, inferential rules included. Multi-line values (`INCLUDE`, `ALLOWED`, `LAYERS`,
 `FORBIDDEN`, `MAPPINGS`) are quoted strings, one item per line.
 
@@ -24,3 +25,6 @@ Parameters per sensor: `file-size` (`LIMIT`, `INCLUDE`, `EXCLUDE`), `folder-layo
 `IGNORE_IMPORTS`: one `importer -> imported` per line, import-linter's native baseline),
 `code-language` (`INCLUDE`, `STOPLIST`), `testing-strategy` (`INCLUDE`, `MAPPINGS`,
 `MUTATION_MIN_SCORE`, `DIFF_COVERAGE_MIN`). A sensor skips (exit 2) when its env file is missing.
+Keys are UPPER_CASE. `guard` treats a `*MIN*` key that goes down, a `*LIMIT*`/`*MAX*` key that goes up,
+a longer `ALLOWED`/`EXCLUDE`/`IGNORE_IMPORTS`, a shorter `INCLUDE`/`FORBIDDEN`, a changed `ENFORCEMENT`
+or a deleted env file as a loosening that needs an ADR in the same change.
```

- [ ] **Step 6: verify.**
  - `grep -rn 'eval "$(tr' plugins/keel-harness/skills | wc -l` → `0`
  - `bash tests/keel_envparse_test.sh` → 12 `ok`, exit 0
  - `bash tests/keel_rule_sensors_test.sh; echo rc=$?` → `rc=0`
  - `bash tests/keel_render_test.sh; echo rc=$?` → `rc=0`
  - `./tests/run.sh; echo rc=$?` → `rc=0`
- [ ] **Step 7: commit and push.** `fix(keel-harness): rule sensors and render.sh parse env files instead of eval (D-2)`

---

## Task 4 — D-1: the `guard` sensor

**Files:** create `tests/keel_guard_test.sh` and `plugins/keel-harness/skills/build/assets/sensors/common/guard.sh`; modify `tests/build_test.sh` and `tests/rules_test.sh`.

Behaviour, all relative to the base commit (`KEEL_GUARD_BASE`, else the merge-base with `origin/HEAD`, else `HEAD`). Using the merge-base means a loosening that was already committed is still caught:

| Loosening | Detected as |
| --- | --- |
| A `.agents/baselines/*.tsv` row whose count grew, or a row or file that appeared | `<file>: <path> <old> -> <new>` |
| A native baseline file under `.agents/baselines/` with more lines | `native baseline grew` |
| A `*MIN*` key lowered; a `*LIMIT*`/`*MAX*` key raised | `<KEY> lowered/raised from a to b` |
| More lines in `ALLOWED`/`EXCLUDE`/`IGNORE_IMPORTS`; fewer in `INCLUDE`/`FORBIDDEN` | `<KEY> widened/narrowed` |
| A changed `ENFORCEMENT`; a deleted `.agents/rules/*.env` | `ENFORCEMENT changed …` / `rule deleted` |
| `CEILING_SECONDS` / `SLOW_CEILING_SECONDS` raised | `… raised from a to b` |
| A sensor tracked at the base removed or moved to `disabled/` | `sensor removed or disabled` |

A loosening passes only when an ADR **added since the base** in `docs/adr`, `doc/adr`, `docs/decisions` or `docs/architecture/decisions` contains the loosened file's path. It also passes when there are no commits, or when `.agents/state.yml` is absent at the base (the harness is being installed in this change).

Known limits, by design (left to review by consequence):
- edits *inside* a sensor file are not judged;
- edited or deleted tests are not detected.

- [ ] **Step 1: write the failing test.** Create `tests/keel_guard_test.sh` (`chmod +x`):

```bash
#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/keel_helpers.sh"
G="$KEEL/skills/build/assets/sensors/common/guard.sh"
[ -f "$G" ]; check "guard.sh exists" $?

# mk -> committed harness: file-size rule (LIMIT=10, empty baseline) and a lint sensor
mk() {
  local r; r="$(new_repo)"
  install_asset "$r" build/assets/gate.sh scripts/gate.sh
  install_asset "$r" build/assets/lib/baseline.sh scripts/lib/baseline.sh
  install_asset "$r" build/assets/lib/envparse.sh scripts/lib/envparse.sh
  install_asset "$r" build/assets/sensors/common/guard.sh scripts/sensors/guard.sh
  install_asset "$r" rules/assets/sensors/file-size.sh scripts/sensors/file-size.sh
  mkdir -p "$r/.agents/rules" "$r/.agents/baselines" "$r/src" "$r/docs/adr"
  cp "$KEEL/skills/build/assets/gate.env" "$r/.agents/gate.env"
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

# committed loosening is still caught against the merge-base with origin/HEAD
r="$(mk)"; (cd "$r" && git update-ref refs/remotes/origin/main HEAD && git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main)
sed -i.bak 's/LIMIT=10/LIMIT=99/' "$r/.agents/rules/file-size.env"; rm -f "$r/.agents/rules/file-size.env.bak"; (cd "$r" && git commit -qam loosen)
run "$r"; [ $rc -eq 1 ]; check "a committed loosening fails against the merge-base with origin/HEAD" $?
out="$(cd "$r" && KEEL_GUARD_BASE=HEAD bash scripts/sensors/guard.sh)"; [ $? -eq 0 ]; check "KEEL_GUARD_BASE overrides the base" $?
out="$(cd "$r" && KEEL_GUARD_BASE=nope bash scripts/sensors/guard.sh)"; [ $? -eq 1 ] && printf '%s' "$out" | grep -q 'is not a commit'; check "a bad KEEL_GUARD_BASE fails" $?

# install and edge cases
r="$(new_repo --no-commit)"; install_asset "$r" build/assets/lib/envparse.sh scripts/lib/envparse.sh; install_asset "$r" build/assets/sensors/common/guard.sh scripts/sensors/guard.sh
run "$r"; [ $rc -eq 0 ] && printf '%s' "$out" | grep -q 'No commits yet'; check "no commits: pass" $?
r="$(new_repo)"; install_asset "$r" build/assets/lib/envparse.sh scripts/lib/envparse.sh; install_asset "$r" build/assets/sensors/common/guard.sh scripts/sensors/guard.sh
mkdir -p "$r/.agents/baselines"; printf 'schema_version: 2\n' > "$r/.agents/state.yml"; printf 'src/a.ts\t9\n' > "$r/.agents/baselines/lint.tsv"
run "$r"; [ $rc -eq 0 ] && printf '%s' "$out" | grep -q 'Harness installed in this change'; check "harness installed in this change: pass" $?
r="$(mk)"; rm "$r/scripts/lib/envparse.sh"; run "$r"; [ $rc -eq 2 ]; check "missing envparse lib: skip" $?
finish
```

- [ ] **Step 2: run it.** `bash tests/keel_guard_test.sh`. Expected: the first line is `  FAIL guard.sh exists`, exit non-zero.
- [ ] **Step 3: create the sensor** `plugins/keel-harness/skills/build/assets/sensors/common/guard.sh` (`chmod +x`):

```bash
#!/usr/bin/env bash
# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.
# guard - security. Fails when the harness itself was loosened since the base commit: a baseline row
# that grew or appeared, a rule limit that relaxed, a widened allow-list, a changed ENFORCEMENT, a
# deleted rule, a fast/slow budget that grew, or a sensor removed or moved to disabled/. A loosening
# passes only when an ADR added in the same change names the loosened file.
# Base: KEEL_GUARD_BASE, else the merge-base with origin/HEAD, else HEAD. SCOPE is not used.
# Out: line 1 = id<TAB>class<TAB>status<TAB>summary. Exit 0 pass / 1 fail / 2 skip.
set -uo pipefail
id=guard
class=security

# --- keel:repo-specific begin ---
ADR_DIRS="docs/adr doc/adr docs/decisions docs/architecture/decisions"
GUIDANCE='undo the loosening and fix the code instead. If loosening is really the decision, add an ADR in this same change that names each file listed above and says why. Editing, deleting or disabling this sensor is the wrong fix.'
# --- keel:repo-specific end ---

# shellcheck disable=SC1090,SC1091
. "${KEEL_ENVPARSE_LIB:-scripts/lib/envparse.sh}" 2>/dev/null || {
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "scripts/lib/envparse.sh is missing - run /keel-harness:build"
  exit 2
}
if ! git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "No commits yet - nothing to compare."
  exit 0
fi
base="${KEEL_GUARD_BASE:-}"
if [ -z "$base" ] && git rev-parse --verify -q refs/remotes/origin/HEAD >/dev/null 2>&1; then
  base="$(git merge-base HEAD refs/remotes/origin/HEAD 2>/dev/null)"
fi
: "${base:=HEAD}"
short="$(git rev-parse --short "$base" 2>/dev/null)" || {
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "KEEL_GUARD_BASE=$base is not a commit."
  printf '  guidance: %s\n' "Set KEEL_GUARD_BASE to the branch the change will merge into (e.g. origin/main), or unset it."
  exit 1
}
if ! git cat-file -e "$base:.agents/state.yml" 2>/dev/null; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "Harness installed in this change - nothing to compare (base $short)."
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
: > "$tmp/loose"
loose() { printf '%s\t%s\n' "$1" "$2" >> "$tmp/loose"; } # loose FILE WHAT
at_base() { git show "$base:$1" 2>/dev/null; }           # at_base PATH -> content at base
lines() { printf '%s' "$1" | grep -c '[^[:space:]]'; }
# env_get FILE KEY -> the value, read without executing anything
env_get() { (keel_env_load "$1" >/dev/null 2>&1 || exit 1; eval "printf '%s' \"\${$2-}\""); }
isnum() { case "$1" in '' | *[!0-9]*) return 1 ;; esac; }

# 1. Baselines. TSV: a row whose count grew, or appeared. Other files (native stores): net growth.
{ git ls-tree -r --name-only "$base" -- .agents/baselines/ 2>/dev/null
  git ls-files --cached --others --exclude-standard -- .agents/baselines/ 2>/dev/null; } | sort -u > "$tmp/bfiles"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  at_base "$f" > "$tmp/old"
  if [ -f "$f" ]; then tr -d '\r' < "$f" > "$tmp/new"; else : > "$tmp/new"; fi
  case "$f" in
    *.tsv)
      awk -F'\t' 'FILENAME == ARGV[1] { if ($0 !~ /^#/ && NF >= 2) old[$1] = $2 + 0; next }
        $0 !~ /^#/ && NF >= 2 { o = ($1 in old) ? old[$1] : 0; if ($2 + 0 > o) printf "%s %d -> %d\n", $1, o, $2 }' \
        "$tmp/old" "$tmp/new" | while IFS= read -r w; do loose "$f" "$w"; done ;;
    *)
      o=$(grep -c . "$tmp/old"); n=$(grep -c . "$tmp/new")
      [ "$n" -gt "$o" ] && loose "$f" "native baseline grew from $o to $n lines" ;;
  esac
done < "$tmp/bfiles"

# 2. Rule env files: relaxed limits, widened lists, changed enforcement, deleted rules.
git ls-tree --name-only "$base" -- .agents/rules/ 2>/dev/null | grep '\.env$' > "$tmp/rules"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if [ ! -f "$f" ]; then loose "$f" "rule deleted"; continue; fi
  at_base "$f" > "$tmp/old.env"
  { sed -n 's/^[[:space:]]*\([A-Z_][A-Z0-9_]*\)=.*/\1/p' "$tmp/old.env"; sed -n 's/^[[:space:]]*\([A-Z_][A-Z0-9_]*\)=.*/\1/p' "$f"; } | sort -u > "$tmp/keys"
  while IFS= read -r k; do
    o="$(env_get "$tmp/old.env" "$k")"; n="$(env_get "$f" "$k")"
    [ "$o" = "$n" ] && continue
    case "$k" in
      *MIN*) isnum "$o" && isnum "$n" && [ "$n" -lt "$o" ] && loose "$f" "$k lowered from $o to $n" ;;
      *LIMIT* | *MAX*) isnum "$o" && isnum "$n" && [ "$n" -gt "$o" ] && loose "$f" "$k raised from $o to $n" ;;
      ALLOWED | EXCLUDE | IGNORE_IMPORTS) [ "$(lines "$n")" -gt "$(lines "$o")" ] && loose "$f" "$k widened" ;;
      INCLUDE | FORBIDDEN) [ "$(lines "$n")" -lt "$(lines "$o")" ] && loose "$f" "$k narrowed" ;;
      ENFORCEMENT) loose "$f" "ENFORCEMENT changed from '$o' to '$n'" ;;
    esac
  done < "$tmp/keys"
done < "$tmp/rules"

# 3. Gate budgets.
if [ -f .agents/gate.env ] && at_base .agents/gate.env > "$tmp/old.gate"; then
  for k in CEILING_SECONDS SLOW_CEILING_SECONDS; do
    o="$(env_get "$tmp/old.gate" "$k")"; n="$(env_get .agents/gate.env "$k")"
    isnum "$o" && isnum "$n" && [ "$n" -gt "$o" ] && loose .agents/gate.env "$k raised from $o to $n"
  done
fi

# 4. Sensors removed or moved to disabled/.
git ls-tree --name-only "$base" -- scripts/sensors/ scripts/sensors/slow/ 2>/dev/null | grep '\.sh$' |
  while IFS= read -r f; do
    case "$(basename "$f")" in _*) continue ;; esac
    [ -f "$f" ] || loose "$f" "sensor removed or disabled"
  done

# A loosened file passes when an ADR added since the base names it.
for d in $ADR_DIRS; do
  git diff --name-only --diff-filter=A "$base" -- "$d" 2>/dev/null
  git ls-files --others --exclude-standard -- "$d" 2>/dev/null
done | sort -u > "$tmp/adrs"
: > "$tmp/left"; covered=0
while IFS="$(printf '\t')" read -r f what; do
  [ -n "$f" ] || continue
  ok=0
  while IFS= read -r a; do
    [ -f "$a" ] && grep -qF -- "$f" "$a" && { ok=1; break; }
  done < "$tmp/adrs"
  if [ "$ok" = 1 ]; then covered=$((covered + 1)); else printf '%s: %s\n' "$f" "$what" >> "$tmp/left"; fi
done < "$tmp/loose"

nl=$(grep -c . "$tmp/left")
if [ "$nl" -eq 0 ]; then
  if [ "$covered" -gt 0 ]; then
    printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "$covered loosening(s) since $short, each named by an ADR added in this change."
  else
    printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "No harness file loosened since $short."
  fi
  exit 0
fi
printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "$nl loosening(s) of the harness since $short without an ADR."
head -5 "$tmp/left" | sed 's/^/  /'
printf '  guidance: %s\n' "$GUIDANCE"
exit 1
```

  Watch line 61: the awk program uses `FILENAME == ARGV[1]`, not `NR == FNR`. With an empty base file, `NR == FNR` is also true for the second file, and new baseline files would pass unnoticed. The prototype hit exactly this bug.
- [ ] **Step 4: scope the v0.2 `docs/adr` tests to writers.** `guard.sh` *reads* `docs/adr`; keel still *writes* ADRs to `docs/decisions/` until F2 (D45).

```diff
diff --git a/tests/build_test.sh b/tests/build_test.sh
index 2d8e13c..14f744e 100755
--- a/tests/build_test.sh
+++ b/tests/build_test.sh
@@ -60,7 +60,8 @@ has "$S" '@AGENTS.md' && has "$S" '.claude/CLAUDE.md'; check "SKILL.md has the C
 CE="$sk/references/context-engineering.md"
 ! has "$CE" '150–200'; check "context-engineering drops the unsourced instruction count" $?
 has "$CE" '2602.11988'; check "context-engineering cites arXiv 2602.11988" $?
-! grep -rq 'docs/adr' "$root/plugins/keel-harness"; check "docs/adr appears nowhere in the plugin" $?
+# guard.sh only reads ADR folders (D45); keel writes ADRs to docs/decisions/ until F2.
+! grep -rq --exclude=guard.sh 'docs/adr' "$root/plugins/keel-harness"; check "docs/adr appears nowhere in the plugin (guard.sh reads it)" $?
 g="$root/plugins/keel-harness/evals/build-typescript/graders"
 [ -f "$g/claude-md-import.md" ] && [ -f "$g/linecount-measured.md" ]; check "claude-md-import and linecount-measured graders exist" $?
 ! grep -q "PreToolUse" "$S"; check "SKILL.md installs no blocking hook" $?
diff --git a/tests/rules_test.sh b/tests/rules_test.sh
index 63e6dd2..3808dcd 100644
--- a/tests/rules_test.sh
+++ b/tests/rules_test.sh
@@ -42,7 +42,7 @@ has "$R/plan-template.md" 'review_by' && has "$R/plan-template.md" 'make gate-fa
 [ -f "$R/nested-agents-md-template.md" ] && has "$R/nested-agents-md-template.md" '## Rules' && has "$R/nested-agents-md-template.md" '100 lines'; check "nested-agents-md-template.md" $?
 [ -f "$R/interview.md" ] && has "$R/interview.md" 'at most 4 questions'; check "interview.md" $?
 has "$sk/../build/SKILL.md" '/keel-harness:rules'; check "build SKILL.md offers /keel-harness:rules" $?
-! grep -rq 'docs/adr' "$root/plugins/keel-harness"; check "docs/adr appears nowhere" $?
+! grep -rq --exclude=guard.sh 'docs/adr' "$root/plugins/keel-harness"; check "docs/adr appears nowhere (guard.sh reads it)" $?
 ! grep -rq "docs/""rules" "$root/plugins" "$root/tests"; check "per-rule doc path is gone (D28)" $?
 
 # --- Task 17: rules evals
```

- [ ] **Step 5: run it.** `bash tests/keel_guard_test.sh` → 24 `ok`, exit 0; `./tests/run.sh; echo rc=$?` → `rc=0`. `shellcheck -S warning plugins/keel-harness/skills/build/assets/sensors/common/guard.sh` → no output.
- [ ] **Step 6: commit and push.** `feat(keel-harness): guard sensor fails a harness loosened without an ADR (D-1)`

---

## Task 5 — install `guard` and `envparse` everywhere, and validate them

**Files:** `skills/build/assets/harness-check.sh`, `tests/keel_harness_check_test.sh`, `skills/doctor/SKILL.md`, `tests/doctor_test.sh`, `README.md` (plugin), `skills/build/SKILL.md`, `skills/build/references/sensor-contract.md`, `skills/build/assets/README.agents.md`, `skills/rules/SKILL.md`, `evals/doctor-finds-drift/scaffold.sh`, `evals/gate-catches-defect/scaffold.sh`.

- [ ] **Step 1: tests first.** Apply these two diffs, then run `bash tests/keel_harness_check_test.sh` and `bash tests/doctor_test.sh`. Expected: both fail, on the new `guard-missing` checks.

```diff
diff --git a/tests/keel_harness_check_test.sh b/tests/keel_harness_check_test.sh
index cdd223e..e698208 100644
--- a/tests/keel_harness_check_test.sh
+++ b/tests/keel_harness_check_test.sh
@@ -10,6 +10,8 @@ mkclean() {
   install_asset "$r" build/assets/harness-check.sh scripts/harness-check.sh
   install_asset "$r" build/assets/gate.sh scripts/gate.sh
   install_asset "$r" build/assets/lib/baseline.sh scripts/lib/baseline.sh
+  install_asset "$r" build/assets/lib/envparse.sh scripts/lib/envparse.sh
+  install_asset "$r" build/assets/sensors/common/guard.sh scripts/sensors/guard.sh
   install_asset "$r" build/assets/hooks/claude-stop.sh scripts/hooks/claude-stop.sh
   mkdir -p "$r/.agents/baselines" "$r/.agents/rules" "$r/.claude" "$r/docs/decisions" "$r/scripts/sensors/slow" "$r/src"
   cp "$KEEL/skills/build/assets/gate.env" "$r/.agents/gate.env"
@@ -108,6 +110,10 @@ r="$(mkclean)"; chmod -x "$r/scripts/hooks/claude-stop.sh"; hc "$r"; only hook-m
 r="$(mkclean)"; printf '{ "hooks": { "PostToolUse": [] } }\n' > "$r/.claude/settings.json"; hc "$r"; only hook-missing settings.json; check "hook-missing: no Stop entry" $?
 r="$(mkclean)"; sed -i 's/hook: installed/hook: not_installed/' "$r/.agents/state.yml"; rm "$r/.claude/settings.json"; hc "$r"; [ $rc -eq 0 ]; check "hook-missing: skipped when the hook layer was declined" $?
 
+# guard-missing
+r="$(mkclean)"; rm "$r/scripts/sensors/guard.sh"; commit "$r"; hc "$r"; only guard-missing scripts/sensors/guard.sh; check "guard-missing: no guard sensor" $?
+r="$(mkclean)"; rm "$r/scripts/lib/envparse.sh"; commit "$r"; hc "$r"; printf '%s\n' "$out" | grep -q '^warn	guard-missing	'; check "guard-missing: no envparse lib" $?
+
 # sensor-malformed
 r="$(mkclean)"; sed -i 's/^id=lint/id=other/' "$r/scripts/sensors/lint.sh"; hc "$r"; only sensor-malformed scripts/sensors/lint.sh; check "sensor-malformed: id differs from file name" $?
 r="$(mkclean)"; sed -i 's/^class=heuristic/class=fuzzy/' "$r/scripts/sensors/lint.sh"; hc "$r"; only sensor-malformed lint.sh; check "sensor-malformed: bad class" $?
```

```diff
diff --git a/tests/doctor_test.sh b/tests/doctor_test.sh
index bc06110..04f1f4e 100755
--- a/tests/doctor_test.sh
+++ b/tests/doctor_test.sh
@@ -14,7 +14,7 @@ has 'prompt-audit'; check "points at /doctor prompt-audit" $?
 grep -qi "writes nothing" "$f"; check "doctor writes nothing" $?
 grep -qi "exactly one warning" "$f"; check "one condition produces one warning" $?
 has 'cmp'; check "proposes updating scripts/harness-check.sh when it differs (cmp)" $?
-for id in agents-size stale-command agents-not-loaded dangling-pointer hook-missing sensor-malformed sensor-unavailable \
+for id in agents-size stale-command agents-not-loaded dangling-pointer hook-missing guard-missing sensor-malformed sensor-unavailable \
           rule-inconsistent topic-size baseline-malformed baseline-stale review-due; do
   has "$id"; check "check id: $id" $?
 done
```

- [ ] **Step 2: the 13th check in `harness-check.sh`.**

```diff
diff --git a/plugins/keel-harness/skills/build/assets/harness-check.sh b/plugins/keel-harness/skills/build/assets/harness-check.sh
index db3e36a..1969b18 100755
--- a/plugins/keel-harness/skills/build/assets/harness-check.sh
+++ b/plugins/keel-harness/skills/build/assets/harness-check.sh
@@ -128,6 +128,12 @@ check_hook_missing() {
   warn hook-missing .claude/settings.json "no Stop hook pointing at an executable scripts/hooks/claude-stop.sh" "Run /keel-harness:build to install the Stop hook, or see .agents/README.md"
 }
 
+# --- guard-missing
+check_guard_missing() {
+  [ -f scripts/sensors/guard.sh ] && [ -f scripts/lib/envparse.sh ] && return 0
+  warn guard-missing scripts/sensors/guard.sh "no guard sensor or no scripts/lib/envparse.sh, so the harness can be loosened without anyone noticing" "Run /keel-harness:build to install scripts/sensors/guard.sh and scripts/lib/envparse.sh"
+}
+
 # --- sensor-malformed
 check_sensor_malformed() {
   local s name id cls problems
@@ -278,6 +284,7 @@ check_stale_command
 check_agents_not_loaded
 check_dangling_pointer
 check_hook_missing
+check_guard_missing
 check_sensor_malformed
 check_sensor_unavailable
 check_rule_inconsistent
```

- [ ] **Step 3: `doctor` and the plugin README count thirteen checks.**

```diff
diff --git a/plugins/keel-harness/skills/doctor/SKILL.md b/plugins/keel-harness/skills/doctor/SKILL.md
index 47c675b..c7a7f3e 100644
--- a/plugins/keel-harness/skills/doctor/SKILL.md
+++ b/plugins/keel-harness/skills/doctor/SKILL.md
@@ -4,7 +4,7 @@ description: >
   Checks whether an installed harness has drifted from the repository it guards, by running the
   same portable validator the repository carries: AGENTS.md over 100 lines, commands cited there
   that no longer resolve, a CLAUDE.md that hides AGENTS.md, dangling rule pointers, a missing Stop
-  hook, malformed or unavailable sensors, rules that disagree with their env files, oversize topic
+  hook, a missing guard sensor, malformed or unavailable sensors, rules that disagree with their env files, oversize topic
   files, malformed or stale baselines, and an overdue harness review. Explains each warning and
   proposes the fix; writes nothing. Use when someone asks whether their harness is out of date,
   stale or still valid, or wants a harness health check.
@@ -29,7 +29,7 @@ then `harness-check: N warning(s)` or `harness-check: harness is clean`. Exit 0
 2 no harness: with no `.agents/state.yml`, say so and point at `/keel-harness:build`; that is a
 precondition, not a warning.
 
-## 2. The twelve checks
+## 2. The thirteen checks
 
 | Check id | Condition | Fix goes through |
 | --- | --- | --- |
@@ -38,6 +38,7 @@ precondition, not a warning.
 | `agents-not-loaded` | `CLAUDE.md` or `.claude/CLAUDE.md` exists without `@AGENTS.md` | `build` (it proposes the import line) |
 | `dangling-pointer` | a `→ path#anchor` target, file or anchor, is missing or still a TODO stub | `rules` |
 | `hook-missing` | no Stop hook pointing at an executable `scripts/hooks/claude-stop.sh` | `build` (hook) |
+| `guard-missing` | no `scripts/sensors/guard.sh` or no `scripts/lib/envparse.sh` | `build` (gates) |
 | `sensor-malformed` | a sensor whose `id=` differs from its file name, whose `class=` is invalid, or that is not executable | edit the file, or `build` |
 | `sensor-unavailable` | a fast sensor exits 2 for a tracked file it covers (tool missing) | `build` (gates) |
 | `rule-inconsistent` | a rule env file is incomplete, points at a missing doc, anchor, sensor or ADR, or its numbers differ from the section | `rules` |
```

```diff
diff --git a/plugins/keel-harness/README.md b/plugins/keel-harness/README.md
index 6b83246..1784bc4 100644
--- a/plugins/keel-harness/README.md
+++ b/plugins/keel-harness/README.md
@@ -40,7 +40,7 @@ what the user approved and never migrates production code.
 
 ### `/keel-harness:doctor`
 
-Runs the repository's own validator (`harness-check.sh`, 12 checks), explains each warning and proposes
+Runs the repository's own validator (`harness-check.sh`, 13 checks), explains each warning and proposes
 the fix. Writes nothing.
 
 ## The v0.2 rule
```

- [ ] **Step 4: `build` installs both assets** (the file stays ≤ 250 lines: 248 after this task):

```diff
diff --git a/plugins/keel-harness/skills/build/SKILL.md b/plugins/keel-harness/skills/build/SKILL.md
index 55961d1..1f19653 100644
--- a/plugins/keel-harness/skills/build/SKILL.md
+++ b/plugins/keel-harness/skills/build/SKILL.md
@@ -24,7 +24,7 @@ repository-specific parts. You never regenerate a script from prose.
 | Python | `sensors/python/` |
 | Java / Kotlin | `sensors/jvm/` |
 
-Every stack also gets `sensors/common/secrets.sh`. For Go, Terraform and anything else in
+Every stack also gets `sensors/common/secrets.sh` and `sensors/common/guard.sh`. For Go, Terraform and anything else in
 `references/sensors-by-language.md`, propose what that file documents, say plainly that the wrappers
 are not bundled, and install only the layers that are. Each phase installs independently and is
 resumable.
@@ -93,8 +93,8 @@ honest `skip`.
 | --- | --- |
 | `gate.sh` | `scripts/gate.sh` |
 | `gate.env` | `.agents/gate.env` |
-| `lib/baseline.sh` (all stacks), `lib/junit.sh` (Java/Kotlin) | `scripts/lib/` |
-| `sensors/<stack>/<id>.sh`, `sensors/common/secrets.sh` (JVM: `compile.sh` -> `scripts/sensors/compile.sh`) | `scripts/sensors/<id>.sh` |
+| `lib/baseline.sh`, `lib/envparse.sh` (all stacks), `lib/junit.sh` (Java/Kotlin) | `scripts/lib/` |
+| `sensors/<stack>/<id>.sh`, `sensors/common/secrets.sh`, `sensors/common/guard.sh` (JVM: `compile.sh` -> `scripts/sensors/compile.sh`) | `scripts/sensors/<id>.sh` |
 
 The first command of the copy is `cp "${CLAUDE_SKILL_DIR}/assets/gate.sh" scripts/gate.sh`, then
 `chmod +x`. For each sensor, edit **only** the block between `# --- keel:repo-specific begin ---`
@@ -145,8 +145,7 @@ baselines (`security` and `correctness` never get a TSV baseline); and the detai
 
 ## 7. The Stop hook
 
-Claude only sees a gate failure when a hook hands it back, and `PostToolUse` output never reaches
-Claude. So the gate is wired to Claude Code's **`Stop`** hook, which gives the fast gate's guidance
+Claude only sees a gate failure when a hook hands it back. `PostToolUse` sends exit-0 stdout to the debug log and, on exit 2, only stderr, where `make` puts no report. So the gate is wired to Claude Code's **`Stop`** hook, which gives the fast gate's guidance
 back before Claude finishes. It blocks no action: the adapter always exits 0 and the conversation
 continues only while the gate fails, up to its loop guard.
 
@@ -183,7 +182,7 @@ accept-or-drop:
 1. The Stop hook of section 7 replaces the v0.1 PostToolUse entry (remove that entry, keep other keys).
 2. The sensor list in the old state is dropped: each entry already has its file; the gate
    discovers files now.
-3. A v0.1 `snapshot` entry becomes a TSV baseline, re-measured with `KEEL_MEASURE=1`, never copied.
+3. A v0.1 `snapshot` entry becomes a TSV baseline, re-measured with `KEEL_MEASURE=1`, never copied, and named in one upgrade ADR so `guard` accepts it.
 4. The v0.1 model-baseline key is replaced by `harness_review_by` (today + 6 months); state becomes section 9.
 5. The `.gitignore` entries above are added.
 
@@ -197,7 +196,7 @@ Proposed for this repository:
 BOOTSTRAP  make bootstrap -> {{real install command}}  (or: none could be inferred)
 GUIDES     AGENTS.md ({{N}} lines) - preview below; docs/ stubs: {{list or none}}
 GATES      fast (budget {{N}}s): typecheck [correctness], lint [heuristic, baseline {{N}} files],
-           tests [correctness], secrets [security]; left out: {{sensor}} - measured {{N}}s
+           tests [correctness], secrets [security], guard [security]; left out: {{sensor}} - measured {{N}}s
            scripts/gate.sh, .agents/gate.env, make gate-fast, make gate-slow
 HOOK       scripts/hooks/claude-stop.sh + a Stop entry in .claude/settings.json (fast gate, timeout 120)
 ```
@@ -237,7 +236,7 @@ Check what the copied assets do not already guarantee:
 - [ ] `make harness-check` was run and prints `harness is clean`.
 - [ ] Each `heuristic` sensor with a baseline has `.agents/baselines/<id>.tsv` from `KEEL_MEASURE=1`.
 - [ ] A sensor that blew the budget is named, with its seconds, under `not_installed`.
-- [ ] `scripts/` has no `${CLAUDE_*}`, plugin path or `claude` call.
+- [ ] `scripts/` has no `${CLAUDE_*}`, plugin path or `claude` call; `scripts/sensors/guard.sh` and `scripts/lib/envparse.sh` exist.
 - [ ] `.claude/settings.json` parses as JSON and kept every key it had; the `Stop` entry is
       present; there is no PostToolUse gate entry; `scripts/hooks/claude-stop.sh` is executable.
 - [ ] The hook `command` contains the literal `${CLAUDE_PROJECT_DIR}`
```

  This diff also carries the D-4 rewording of §7 (Task 6 only verifies it).
- [ ] **Step 5: contract, hand-editing guide and `rules`.**

```diff
diff --git a/plugins/keel-harness/skills/build/references/sensor-contract.md b/plugins/keel-harness/skills/build/references/sensor-contract.md
index 0de2a05..efdf232 100644
--- a/plugins/keel-harness/skills/build/references/sensor-contract.md
+++ b/plugins/keel-harness/skills/build/references/sensor-contract.md
@@ -52,7 +52,8 @@ is always allowed. The comparison lives in `scripts/lib/baseline.sh` (`baseline_
   `rules` writes at approval time (`KEEL_MEASURE=1 bash scripts/sensors/<id>.sh > .agents/baselines/<id>.tsv`).
 - Because baselines are per file, a baselined sensor may honour `SCOPE` and look only at the files
   that changed.
-- Only keel writes or tightens a baseline, with the user's approval. It never raises one.
+- Only keel writes or tightens a baseline, with the user's approval. It never raises one. `guard` fails a
+  row that grew or appeared unless an ADR added in the same change names the baseline file.
 - `review_by` is the ratchet's expiry. Past it, `harness-check.sh` warns (`baseline-stale`) unless
   the total has dropped; re-measure downward, never upward to accommodate drift.
 
@@ -122,10 +123,12 @@ Each stack sensor keeps everything repository-specific between two markers:
 | --- | --- | --- |
 | `gate.sh`, `gate.env` | - | `scripts/gate.sh`, `.agents/gate.env` |
 | `lib/baseline.sh` | - | `scripts/lib/baseline.sh` |
+| `lib/envparse.sh` | - | `scripts/lib/envparse.sh` (reads rule and gate env files; never executes them) |
 | `sensors/typescript/typecheck.sh` | correctness | `scripts/sensors/typecheck.sh` |
 | `sensors/typescript/lint.sh` | heuristic, TSV baseline | `scripts/sensors/lint.sh` |
 | `sensors/typescript/tests.sh` | correctness | `scripts/sensors/tests.sh` |
 | `sensors/common/secrets.sh` | security, no baseline | `scripts/sensors/secrets.sh` |
+| `sensors/common/guard.sh` | security, no baseline | `scripts/sensors/guard.sh` (fails when the harness was loosened without an ADR) |
 
 Python, Java/Kotlin and rule sensors are listed in `sensors-by-language.md` and in the `rules`
 catalog. The `rules` skill ships its own sensors under its `assets/sensors/` (slow ones install to
```

```diff
diff --git a/plugins/keel-harness/skills/build/assets/README.agents.md b/plugins/keel-harness/skills/build/assets/README.agents.md
index 24b3b65..7cf4707 100644
--- a/plugins/keel-harness/skills/build/assets/README.agents.md
+++ b/plugins/keel-harness/skills/build/assets/README.agents.md
@@ -37,7 +37,9 @@ Installed scripts start with a "Managed by keel-harness" line. Edit only between
 1. Edit the value in `.agents/rules/<rule-id>.env` (for example `LIMIT=400`).
 2. Edit the same number in the rule's section in its topic file.
 3. Run `make harness-check`; it flags a number that differs between the two.
-4. Write an ADR in `docs/decisions/` if the change is a real trade-off.
+4. Write an ADR in `docs/decisions/` if the change is a real trade-off. Loosening the limit (raising a
+   `LIMIT`/`MAX`, lowering a `MIN`) always needs one: `guard` fails until an ADR added in the same
+   change names `.agents/rules/<rule-id>.env`.
 
 ### Add a sensor
 Drop an executable file in `scripts/sensors/` (fast) or `scripts/sensors/slow/` (slow). It must:
@@ -51,7 +53,8 @@ Files starting with `_` and subdirectories are never run by the gate.
 ### Disable a sensor
 Move it to `scripts/sensors/disabled/`. The gate runs only top-level `*.sh` files. Move it back to
 re-enable it. `make harness-check` warns when a rule still points at a sensor that is not in
-`scripts/sensors/` or `scripts/sensors/slow/`.
+`scripts/sensors/` or `scripts/sensors/slow/`. Disabling a committed sensor is a loosening: `guard`
+fails until an ADR added in the same change names `scripts/sensors/<id>.sh`.
 
 ### Shrink a baseline after a fix
 ```bash
@@ -82,7 +85,13 @@ Remove the `Stop` entry from `.claude/settings.json`. Copilot and Devin never ha
 
 ### Raise the time budget
 Edit `.agents/gate.env`. The fast gate should stay fast; prefer moving a slow sensor to
-`scripts/sensors/slow/`.
+`scripts/sensors/slow/`. A higher budget needs an ADR in the same change that names `.agents/gate.env`.
+
+### Loosen the harness on purpose
+`guard` compares the harness with the commit the branch started from (`KEEL_GUARD_BASE`, else the
+merge-base with `origin/HEAD`, else `HEAD`). To loosen a baseline, a limit, a list, a budget or a
+sensor deliberately, add an ADR in the same change that names each file by path and says why; then
+`make gate-fast` passes. Without it, undo the loosening and fix the code.
 
 ## Commands
 
```

```diff
diff --git a/plugins/keel-harness/skills/rules/SKILL.md b/plugins/keel-harness/skills/rules/SKILL.md
index e0dbc70..5567f8b 100644
--- a/plugins/keel-harness/skills/rules/SKILL.md
+++ b/plugins/keel-harness/skills/rules/SKILL.md
@@ -25,8 +25,8 @@ Reference files live next to this one: `references/catalog.md` (the entries and
 
 ## 0. Precondition
 
-Rule sensors run inside the gates, so this skill needs `scripts/gate.sh`, `scripts/lib/baseline.sh`
-and the Makefile targets `gate-fast` and `gate-slow`. If any is missing, offer to run
+Rule sensors run inside the gates, so this skill needs `scripts/gate.sh`, `scripts/lib/baseline.sh`,
+`scripts/lib/envparse.sh`, `scripts/sensors/guard.sh` and the Makefile targets `gate-fast` and `gate-slow`. If any is missing, offer to run
 `/keel-harness:build` first (in greenfield, build installs the runner even when no tool sensor can
 run yet; a gate with zero sensors is valid). Continue only when the user agrees or they exist.
 
@@ -86,6 +86,8 @@ Write only what was approved, in this order:
 
 1. The ADR in `docs/decisions/`, when the round had a real trade-off, the rule is breaking, or the
    user overrode your recommendation (`adr-template.md`). Never edit an accepted ADR: supersede it.
+   The ADR names, by path, every baseline it introduces and every env file it loosens: `guard` accepts
+   a new or grown baseline, or a relaxed limit, only when an ADR added in the same change names it.
 2. The rule's section in its **topic file**, from `rule-section.md`: `docs/architecture.md` holds
    `architecture` and `folder-layout`; `docs/conventions.md` holds `file-size`, `code-language`,
    `adopted-patterns` and other code conventions; `docs/testing.md` holds `testing-strategy`. Create
```

- [ ] **Step 6: the eval scaffolds install both assets.** Without this, `doctor-finds-drift` would report a second warning (`guard-missing`) where the case expects exactly one.

```diff
diff --git a/plugins/keel-harness/evals/doctor-finds-drift/scaffold.sh b/plugins/keel-harness/evals/doctor-finds-drift/scaffold.sh
index 8543449..5633f23 100755
--- a/plugins/keel-harness/evals/doctor-finds-drift/scaffold.sh
+++ b/plugins/keel-harness/evals/doctor-finds-drift/scaffold.sh
@@ -22,8 +22,10 @@ mkdir -p scripts/lib scripts/sensors
 cp "$assets/gate.sh" scripts/gate.sh
 cp "$assets/gate.env" .agents/gate.env
 cp "$assets/lib/baseline.sh" scripts/lib/baseline.sh
+cp "$assets/lib/envparse.sh" scripts/lib/envparse.sh
 for s in typecheck lint tests; do cp "$assets/sensors/typescript/$s.sh" "scripts/sensors/$s.sh"; done
 cp "$assets/sensors/common/secrets.sh" scripts/sensors/secrets.sh
+cp "$assets/sensors/common/guard.sh" scripts/sensors/guard.sh
 chmod +x scripts/gate.sh scripts/sensors/*.sh
 
 cat > AGENTS.md <<'MD'
diff --git a/plugins/keel-harness/evals/gate-catches-defect/scaffold.sh b/plugins/keel-harness/evals/gate-catches-defect/scaffold.sh
index 4dc5e93..fb81f31 100755
--- a/plugins/keel-harness/evals/gate-catches-defect/scaffold.sh
+++ b/plugins/keel-harness/evals/gate-catches-defect/scaffold.sh
@@ -23,8 +23,10 @@ mkdir -p scripts/lib scripts/sensors
 cp "$assets/gate.sh" scripts/gate.sh
 cp "$assets/gate.env" .agents/gate.env
 cp "$assets/lib/baseline.sh" scripts/lib/baseline.sh
+cp "$assets/lib/envparse.sh" scripts/lib/envparse.sh
 for s in typecheck lint tests; do cp "$assets/sensors/typescript/$s.sh" "scripts/sensors/$s.sh"; done
 cp "$assets/sensors/common/secrets.sh" scripts/sensors/secrets.sh
+cp "$assets/sensors/common/guard.sh" scripts/sensors/guard.sh
 chmod +x scripts/gate.sh scripts/sensors/*.sh
 
 npm install --no-audit --no-fund --silent
```

- [ ] **Step 7: verify.** `bash tests/keel_harness_check_test.sh`, `bash tests/doctor_test.sh`, `bash tests/build_test.sh`, `bash tests/rules_test.sh` and `./tests/run.sh` each exit 0; `wc -l < plugins/keel-harness/skills/build/SKILL.md` → `248`; `bash -n` on both scaffolds → no output.
- [ ] **Step 8: commit and push.** `feat(keel-harness): build installs guard and envparse; harness-check warns guard-missing`

---

## Task 6 — D-3 and D-4: documentation fixes

**Files:** `skills/assess/references/harness-model.md` (D-3). D-4 (`build/SKILL.md` §7) was applied in Task 5, Step 4.

- [ ] **Step 1: D-3.** Remove the two references to the non-existent `reasoning-framework.md`:

```diff
diff --git a/plugins/keel-harness/skills/assess/references/harness-model.md b/plugins/keel-harness/skills/assess/references/harness-model.md
index e4ebf42..28e84f6 100644
--- a/plugins/keel-harness/skills/assess/references/harness-model.md
+++ b/plugins/keel-harness/skills/assess/references/harness-model.md
@@ -54,8 +54,7 @@ be:
 - **Opinionated frameworks** (Spring, Django) reduce agent freedom → higher first-try success.
 - **Legacy / high-debt systems** are hardest to harness; scope sensors to changed files first.
 
-Assess harnessability before choosing how aggressive the gates should be (see
-`reasoning-framework.md` Step 1).
+Assess harnessability before choosing how aggressive the gates should be.
 
 ---
 
@@ -82,7 +81,7 @@ generate a small block
 run the slow gates (full suite + architecture-fitness) before declaring "done"
 ```
 
-**Per-step vs end-of-run** (decide in `reasoning-framework.md` Step 5):
+**Per-step vs end-of-run** (the fast and slow gates; the budget rule is in `build/references/sensor-contract.md` §1, field 7):
 
 | Run at every step (fast, localized) | Run at the end (slow, global)         |
 | ----------------------------------- | ------------------------------------- |
```

- [ ] **Step 2: verify.**
  - `grep -rn 'reasoning-framework' plugins/keel-harness` → no output.
  - `grep -n 'only stderr, where' plugins/keel-harness/skills/build/SKILL.md` → one line (D-4).
- [ ] **Step 3: commit and push.** `docs(keel-harness): drop dangling reasoning-framework refs; correct the PostToolUse note (D-3, D-4)`

---

## Task 7 — full verification and report

- [ ] **Step 1:** `./tests/run.sh; echo rc=$?` with `shellcheck` installed → `rc=0`, and `grep -cE '^\s+ok ' <log>` → **991** (946 + 45).
- [ ] **Step 2:** `./tests/run.sh; echo rc=$?` without `shellcheck` on `PATH` → `rc=0` with `skip shellcheck:` lines.
- [ ] **Step 3:** `make validate` → `Validation passed` for all three plugins.
- [ ] **Step 4: D-1 end to end.** Run the reproduction by hand in a scratch directory, outside the repository:

```bash
K=<repo>/plugins/keel-harness/skills
d=$(mktemp -d) && cd "$d" && git init -q && git config user.email t@t && git config user.name t
mkdir -p scripts/sensors scripts/lib .agents/rules .agents/baselines src
cp $K/build/assets/gate.sh scripts/; cp $K/build/assets/lib/baseline.sh $K/build/assets/lib/envparse.sh scripts/lib/
cp $K/rules/assets/sensors/file-size.sh $K/build/assets/sensors/common/guard.sh scripts/sensors/
printf 'schema_version: 2\n' > .agents/state.yml
printf 'RULE_ID=file-size\nENFORCEMENT=sensor:file-size\nLIMIT=10\nINCLUDE=src\n' > .agents/rules/file-size.env
printf '# measured_at: 2026-10-24 review_by: 2027-04-24\n' > .agents/baselines/file-size.tsv
git add -A && git commit -qm init
seq 1 20 > src/big.txt;               bash scripts/gate.sh fast | tail -2   # FAILED (1 of 2): file-size
printf 'src/big.txt\t20\n' >> .agents/baselines/file-size.tsv
bash scripts/gate.sh fast | grep -E '^x|guard|gate:'                         # FAILED (1 of 2): guard names the row
```

  Expected: the second run still fails, now on `guard`, with `.agents/baselines/file-size.tsv: src/big.txt 0 -> 20`. In v0.2, that same second run printed `PASSED`.
- [ ] **Step 5: tick F0** in `docs/plans/2026-10-23-keel-harness-v0.3-plan.md` (every F0 checkbox), commit (`docs(keel-harness): F0 done`) and push.
- [ ] **Step 6: report to the owner:**
  - the commit list;
  - the Step 1 count;
  - the Step 4 output;
  - any step whose output differed from this plan;
  - anything you skipped and why.

  Do not open a pull request; do not start F1.

