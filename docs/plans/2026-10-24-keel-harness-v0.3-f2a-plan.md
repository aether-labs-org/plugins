# keel-harness v0.3 — F2a Layout: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or superpowers:subagent-driven-development) to implement this plan task by task. Steps use checkbox (`- [ ]`) syntax for tracking. Follow the steps in order.

**Goal:** Move keel-harness to the v0.3 plugin layout (spec §4, D34, D35), with **no change in behaviour**:
- what is copied into a repository lives in `assets/`;
- what runs from the plugin lives in `scripts/`;
- skills reach both through `${CLAUDE_PLUGIN_ROOT}` instead of `${CLAUDE_SKILL_DIR}` and cross-skill `../` paths.

It also fixes one regression F0 introduced (`measure.sh language`).

**Scope:** F2a is the first of four F2 sub-phases. F2b covers `.agents/run/`, `ADR_DIR`, the schema 3 upgrade and `scripts/keel` phases. F2c covers the skill rewrite, `contracts/`, `disallowed-tools`, size and pressure tests. F2d covers `assess` dimensions, LSP, codemap and triggering evals. Each gets its own plan after the previous one is validated. F2a runs in parallel with F1, which measures the fixed commit `cf495ff`.

**Architecture:** One deterministic migration script does every move (`git mv`, so history follows) and every path rewrite. A layout test, written first, proves the result. `assets/core/` keeps v0.2's internal layout (`gate.sh`, `gate.env`, `harness-check.sh`, `README.agents.md`, `lib/`, `sensors/<stack>/`, `sensors/common/`), and the rule sensors move under it to `sensors/rules/`. The Claude Code hook goes to `assets/adapters/claude/`, and `measure.sh` and `render.sh` go to `scripts/`. Installed paths in user repositories do **not** change.

**Spec:** `docs/specs/2026-10-23-keel-harness-v0.3-design.md` §4 (layout), D34–D36.

**Provenance:** prototyped on 2026-10-24 on `cf495ff` (end of F0) and run. Results:
- `./tests/run.sh`: exit 0 with 991 → 993 (Task 1) → 1020 `ok` (Task 2);
- `claude plugin validate ./plugins/keel-harness --strict`: passed;
- `scripts/measure.sh language|file-size` and `scripts/render.sh depcruise` produce output from the new paths.

The prototype caught a wrong rewrite (the build skill pointed at the rule sensors); the script below scopes that rule to the rules skill, and the layout test now checks it. Copy everything **verbatim**. If any output differs from what is written here, stop and report.

## Global constraints

- Git: create the branch named below, commit once per task with the message shown, push after each commit, **no pull request without the owner's approval**.
- No behaviour change beyond Task 1. Do not edit by hand what the migration script rewrites; if a check fails after the script, stop and report.
- Do not bump the plugin version; do not touch `docs/` except as Task 3 says.

## Prerequisites

| Tool | Check |
| --- | --- |
| bash, git, awk, sed | `bash --version; git --version` |
| `jq` | `jq --version` |
| `shellcheck` | `shellcheck --version` (no root: `python3 -m venv .venv && .venv/bin/pip install shellcheck-py`) |
| `claude` CLI | `claude --version` |

Setup:
1. `git fetch origin claude/harness-engineering-autonomous-agents-d8xhvx`.
2. Create `feat/keel-harness-v0.3-f2a` from it and push with `-u`.
3. Confirm `git log --oneline -1 -- plugins/` shows `27c312b` or later (F0 is in), and that `./tests/run.sh` exits 0 with 991 `ok`.

---

## Task 1 — fix the F0 regression in `measure.sh language`

`measure.sh language` runs the `code-language` sensor from the plugin and passes it `KEEL_BASELINE_LIB`. Since F0, that sensor also sources `scripts/lib/envparse.sh`. In a repository that has no `scripts/lib/` yet, which is exactly when `rules` measures, it prints `skip … envparse.sh is missing` instead of measuring.

- [ ] **Step 1: failing test.** Apply:

```diff
diff --git a/tests/keel_measure_test.sh b/tests/keel_measure_test.sh
index a77a390..2790fb9 100644
--- a/tests/keel_measure_test.sh
+++ b/tests/keel_measure_test.sh
@@ -69,4 +69,9 @@ ro tests tests
 
 # --- unknown
 R="$(new_repo)"; m bogus >/dev/null; [ $? -eq 64 ]; check "unknown subcommand rc 64" $?
+# --- language (runs the code-language sensor from the plugin, in a repository without scripts/lib/)
+R="$(new_repo)"; mkdir -p "$R/src"; printf 'const valorTotal = 1; // calcula o total\n' > "$R/src/a.ts"; commit
+out="$(m language pt.txt src)"
+printf '%s\n' "$out" | grep -qx 'files 1' && printf '%s\n' "$out" | grep -qx 'flagged 2'; check "language measures with the bundled stop-list and libraries" $?
+ro language language pt.txt src
 finish
```

  Run `bash tests/keel_measure_test.sh | grep 'language measures'`. Expected: `  FAIL language measures with the bundled stop-list and libraries`.
- [ ] **Step 2: fix.** Apply:

```diff
diff --git a/plugins/keel-harness/skills/rules/assets/measure.sh b/plugins/keel-harness/skills/rules/assets/measure.sh
index 72cb7b9..cce8146 100755
--- a/plugins/keel-harness/skills/rules/assets/measure.sh
+++ b/plugins/keel-harness/skills/rules/assets/measure.sh
@@ -181,6 +181,7 @@ cmd_language() {
 }${p}"; done
   printf "INCLUDE='%s'\nSTOPLIST='%s'\n" "$inc" "$sl" > "$tmp/language.env"
   RULE_ENV="$tmp/language.env" KEEL_MEASURE=1 KEEL_MEASURE_WORDS=1 KEEL_BASELINE_LIB="$here/../../build/assets/lib/baseline.sh" \
+    KEEL_ENVPARSE_LIB="$here/../../build/assets/lib/envparse.sh" \
     bash "$here/sensors/code-language.sh"
 }
 
```

- [ ] **Step 3: verify.** `bash tests/keel_measure_test.sh` → exit 0; `./tests/run.sh` → exit 0 with **993** `ok`.
- [ ] **Step 4: commit and push.** `fix(keel-harness): measure.sh language passes the envparse library to code-language (F0 regression)`

---

## Task 2 — the v0.3 layout

- [ ] **Step 1: layout test first.** Create `tests/keel_layout_test.sh` (`chmod +x`):

```bash
#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/keel_helpers.sh"
# The v0.3 plugin layout (spec §4): what is copied into a repository lives in assets/, what runs from
# the plugin lives in scripts/, and skills reach both through ${CLAUDE_PLUGIN_ROOT}.
for d in skills/build/assets skills/rules/assets; do
  [ ! -e "$KEEL/$d" ]; check "no $d (moved to assets/ and scripts/)" $?
done
for f in assets/core/gate.sh assets/core/gate.env assets/core/harness-check.sh assets/core/README.agents.md \
         assets/core/lib/baseline.sh assets/core/lib/envparse.sh assets/core/lib/junit.sh \
         assets/core/sensors/common/guard.sh assets/core/sensors/common/secrets.sh \
         assets/core/sensors/typescript/lint.sh assets/core/sensors/python/lint.sh assets/core/sensors/jvm/lint.sh \
         assets/core/sensors/rules/file-size.sh assets/core/sensors/rules/slow/mutation.sh \
         assets/core/sensors/rules/stoplists/pt.txt \
         assets/adapters/claude/claude-stop.sh assets/adapters/claude/settings-stop.json \
         scripts/measure.sh scripts/render.sh; do
  [ -f "$KEEL/$f" ]; check "$f exists" $?
done
[ ! -e "$KEEL/bin" ]; check "no bin/ (claude.ai and Cowork do not install a plugin that has one)" $?
! grep -rn 'CLAUDE_SKILL_DIR}/\.\./' "$KEEL/skills" >/dev/null; check "no skill reaches into a sibling skill" $?
! grep -rn 'CLAUDE_SKILL_DIR}/assets' "$KEEL/skills" >/dev/null; check "skills reach bundled files through \${CLAUDE_PLUGIN_ROOT}" $?
missing="$(grep -rhoE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9_./-]+' "$KEEL/skills" | sed 's#^\${CLAUDE_PLUGIN_ROOT}/##; s#[.,]*$##' | sort -u |
  while IFS= read -r p; do [ -e "$KEEL/$p" ] || printf '%s\n' "$p"; done)"
[ -z "$missing" ]; check "every \${CLAUDE_PLUGIN_ROOT}/ path a skill cites exists${missing:+ (missing: $missing)}" $?
! grep -n 'assets/core/sensors/rules' "$KEEL/skills/build/SKILL.md" "$KEEL/skills/build/references/sensors-by-language.md" >/dev/null
check "build cites the stack sensors (assets/core/sensors/), not the rule sensors" $?
grep -q 'PLUGIN_ROOT}/assets/core/sensors/rules/' "$KEEL/skills/rules/SKILL.md"; check "rules copies its sensors from assets/core/sensors/rules/" $?
! grep -rnE 'skills/(build|rules)/assets' "$KEEL" "$(dirname "$0")"/*.sh --exclude=keel_layout_test.sh >/dev/null; check "no reference to the old asset paths in the plugin or the tests" $?
finish
```

  Run `bash tests/keel_layout_test.sh | grep -c FAIL`. Expected: `25`.
- [ ] **Step 2: save the migration script outside the repository**, e.g. `"${TMPDIR:-/tmp}/f2a-migrate.sh"`:

```bash
#!/usr/bin/env bash
# F2a: move keel-harness to the v0.3 layout. Run once from the repository root on a clean tree.
set -euo pipefail
P=plugins/keel-harness
[ -d "$P/skills/build/assets" ] || { echo "already migrated (no $P/skills/build/assets)" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "working tree not clean" >&2; exit 1; }

# 1. Moves (git mv keeps history)
mkdir -p "$P/assets/core" "$P/assets/adapters" "$P/scripts"
git mv "$P/skills/build/assets/hooks" "$P/assets/adapters/claude"
for x in gate.sh gate.env harness-check.sh README.agents.md lib sensors; do
  git mv "$P/skills/build/assets/$x" "$P/assets/core/$x"
done
git mv "$P/skills/rules/assets/sensors" "$P/assets/core/sensors/rules"
git mv "$P/skills/rules/assets/measure.sh" "$P/scripts/measure.sh"
git mv "$P/skills/rules/assets/architecture/render.sh" "$P/scripts/render.sh"
rmdir "$P/skills/rules/assets/architecture" "$P/skills/rules/assets" "$P/skills/build/assets"

# 2. Path rewrites, most specific first
files="$(git ls-files "$P" tests | grep -E '\.(sh|md|json)$' | grep -v '^tests/keel_layout_test.sh$')"
rewrite() { printf '%s\n' "$files" | while IFS= read -r f; do sed -i.f2a "$1" "$f" && rm -f "$f.f2a"; done; }
# skills: bundled files through ${CLAUDE_PLUGIN_ROOT}
rewrite 's#${CLAUDE_SKILL_DIR}/assets/measure\.sh#${CLAUDE_PLUGIN_ROOT}/scripts/measure.sh#g'
rewrite 's#${CLAUDE_SKILL_DIR}/assets/architecture/render\.sh#${CLAUDE_PLUGIN_ROOT}/scripts/render.sh#g'
# in the rules skill only, ${CLAUDE_SKILL_DIR}/assets/sensors/ means the rule sensors
git ls-files "$P/skills/rules" | grep '\.md$' | while IFS= read -r f; do
  sed -i.f2a 's#${CLAUDE_SKILL_DIR}/assets/sensors/#${CLAUDE_PLUGIN_ROOT}/assets/core/sensors/rules/#g' "$f" && rm -f "$f.f2a"
done
rewrite 's#${CLAUDE_SKILL_DIR}/assets/hooks/#${CLAUDE_PLUGIN_ROOT}/assets/adapters/claude/#g'
rewrite 's#${CLAUDE_SKILL_DIR}/\.\./build/assets/#${CLAUDE_PLUGIN_ROOT}/assets/core/#g'
rewrite 's#${CLAUDE_SKILL_DIR}/assets/#${CLAUDE_PLUGIN_ROOT}/assets/core/#g'
# repository-relative paths (tests, eval scaffolds, references)
rewrite 's#skills/build/assets/hooks/#assets/adapters/claude/#g'
rewrite 's#skills/build/assets/#assets/core/#g; s#skills/build/assets"#assets/core"#g'
rewrite 's#skills/rules/assets/measure\.sh#scripts/measure.sh#g'
rewrite 's#skills/rules/assets/architecture/render\.sh#scripts/render.sh#g'
rewrite 's#skills/rules/assets/sensors#assets/core/sensors/rules#g'
rewrite 's#skills/rules/assets/#assets/core/sensors/rules/#g; s#skills/rules/assets"#assets/core/sensors/rules"#g'
# tests: install_asset paths become relative to the plugin root
sed -i.f2a 's#build/assets/hooks/#assets/adapters/claude/#g; s#build/assets/#assets/core/#g; s#rules/assets/sensors#assets/core/sensors/rules#g; s#\$KEEL/skills/\$#$KEEL/$#g' tests/keel_*.sh && rm -f tests/*.f2a
sed -i.f2a 's#^\# install_asset REPO SRC_REL DEST_REL  (SRC_REL relative to \$KEEL/skills/)#\# install_asset REPO SRC_REL DEST_REL  (SRC_REL relative to $KEEL, the plugin root)#; s#cp "\$KEEL/skills/\$2"#cp "$KEEL/$2"#' tests/keel_helpers.sh && rm -f tests/keel_helpers.sh.f2a
sed -i.f2a 's#find "\$KEEL"/skills/\*/assets -type f#find "$KEEL"/assets "$KEEL"/scripts -type f#; s#\*/skills/build/assets/\*|\*/skills/rules/assets/sensors/\*)#*/assets/*)#' tests/keel_assets_test.sh && rm -f tests/keel_assets_test.sh.f2a
# scripts/ runs from the plugin: its sibling paths change
sed -i.f2a 's#\$here/sensors/#$here/../assets/core/sensors/rules/#g; s#\$here/\.\./\.\./build/assets/lib/#$here/../assets/core/lib/#g' "$P/scripts/measure.sh" && rm -f "$P/scripts/measure.sh.f2a"
sed -i.f2a 's#/\.\./\.\./\.\./build/assets/lib/envparse\.sh#/../assets/core/lib/envparse.sh#' "$P/scripts/render.sh" && rm -f "$P/scripts/render.sh.f2a"
# eval harness: rule sensors now sit directly under the rules directory
sed -i.f2a 's#\$rassets/sensors/#$rassets/#g' "$P/evals/rules-brownfield/harness.sh" && rm -f "$P/evals/rules-brownfield/harness.sh.f2a"
echo "migrated; now run: ./tests/run.sh"
```

- [ ] **Step 3: commit the test, then migrate.** The script requires a clean tree, so first commit the layout test, then run the script:
  - `git add tests/keel_layout_test.sh && git commit -m "test(keel-harness): layout test for the v0.3 plugin structure"` (no push yet);
  - `bash "${TMPDIR:-/tmp}/f2a-migrate.sh"`. Expected last line: `migrated; now run: ./tests/run.sh`.
- [ ] **Step 4: verify the change set.**
  - `git add -A && git diff --cached --shortstat` → `56 files changed, 92 insertions(+), 92 deletions(-)`;
  - `git diff --cached -M --name-status | awk '{print $1}' | sort | uniq -c` → `25 M`, `1 R097`, `1 R099`, `29 R100`.
- [ ] **Step 5: verify behaviour.**
  - `./tests/run.sh; echo rc=$?` → `rc=0`, **1020** `ok`.
  - `grep -rnE 'skills/(build|rules)/assets|CLAUDE_SKILL_DIR\}/(assets|\.\.)|build/assets|rules/assets' plugins/keel-harness tests | grep -v keel_layout_test` → no output.
  - `grep -rn 'CLAUDE_SKILL_DIR' plugins/keel-harness` → no output.
  - `for f in plugins/keel-harness/evals/*/scaffold.sh plugins/keel-harness/evals/rules-brownfield/harness.sh; do bash -n "$f"; done` → no output.
  - In a scratch git repository with one committed `src/a.ts` containing `const valorTotal = 1; // calcula o total`:
    - `bash <repo>/plugins/keel-harness/scripts/measure.sh language pt.txt src` → `files 1`, `flagged 2`;
    - `bash <repo>/plugins/keel-harness/scripts/render.sh depcruise <repo>/tests/fixtures/keel/architecture/layered-ts.env | head -1` → a line starting `// Generated by keel-harness`.
  - `claude plugin validate ./plugins/keel-harness --strict` → `Validation passed`.
- [ ] **Step 6: commit and push** (both commits). `refactor(keel-harness): move to the v0.3 layout (assets/core, assets/adapters/claude, scripts)`

---

## Task 3 — record and report

- [ ] **Step 1:** in `docs/plans/2026-10-23-keel-harness-v0.3-plan.md`, tick the F2a checkboxes. Commit `docs(keel-harness): F2a done` and push.
- [ ] **Step 2: report to the owner:**
  - the commit list;
  - the Task 2 Step 4 and Step 5 outputs;
  - anything that differed from this plan.

  Do not open a pull request; do not start F2b.
