# keel-harness v0.3 — E2 Eval graders: Implementation Plan

> **For agentic workers:** Tasks 1–3 are free and run anywhere. Task 4 spends money and needs a host where Claude Code's nested Bash sandbox works (a Claude Code cloud session worked for E1). Steps use checkbox (`- [ ]`) syntax. Copy every file and script exactly as written here.

**Goal:** Make the eval suite measure what the skills do, so later phases have a ruler they can trust. Four problems, found in F1, F1b and E1:
1. **"Writes nothing" counts the harness's own files.** `assess-*` and `doctor-*` grade it with `file_exists` on `**/*`. That grader counts every file created during the run, including the `.claude/.cc-writes/` that Claude Code's Bash tool creates. In E1 it failed in both arms, so it measured the harness, not the skill.
2. **Cases do not list the tools they need.** `build-*` ask the agent to install a harness but list no `Bash`, `Write` or `Edit`. `gate-catches-defect` asks for `make` and a file but lists `[Read, Glob, Grep]`.
   - Facts from the docs: a case's `allowed_tools` grants read-only tools only; gated tools come only from `--allow-tools`, which applies to the whole run. When a case lists a tool the run did not grant, the progress output shows it as `not granted`.
   - So listing them changes no score. It makes an ungranted run visible.
3. **No way to run one grant group.** `--case` keeps only its last value. A run that grants Bash to `doctor-*` grants it to `assess-*` too. Each case gets one group tag (`readonly`, `bash`, `tools`, `effect`), selected with `--tag`.
4. **`should-not-trigger` misses the `rules` skill.** Its grader checks `assess|build|doctor`, but `rules` was added in v0.2.

**Spec:** `docs/specs/2026-10-23-keel-harness-v0.3-design.md` §2.2 (C9), D31, D50. Master plan: `docs/plans/2026-10-23-keel-harness-v0.3-plan.md`, phase E2.

**Sources** (`https://code.claude.com/docs/en/plugin-evals`, read 2026-10-28):
- `tool_used`: `min`/`max` bound the calls whose JSON input matches `input_match`. `min: 0, max: 0` asserts a tool was never called.
- `file_exists`: "Only files created during the run count."
- `weight`: "Any positive number."
- `allowed_tools`: grants only read-only tools; anything else needs `--allow-tools`, which applies to every case in the run.
- `--tag`: "A case runs if any of its tags matches."

**Provenance:** prototyped on 2026-10-28 on `cdd2c66`, then re-run from this plan's own text in a clean worktree (same result).
- `./tests/run.sh` goes from 1031 to **1080** `ok` (with `shellcheck` installed), and `claude plugin validate --strict` passes.
- The new test fails 16 checks on the old tree.
- The Bash write pattern was checked in node as the grader file carries it (YAML-parsed).
- Applied together with the F3a prototype, the suite gives 1112 `ok`.
- No eval was run.

## Global constraints

- **Git:**
  1. `git fetch origin claude/harness-engineering-autonomous-agents-d8xhvx`.
  2. Create `feat/keel-harness-v0.3-e2` from it and push with `-u`.
  3. One commit per task, push after each, no pull request without the owner's approval.
- Change only what this plan lists: no plugin skill, asset or script. F3a runs in parallel and changes those.
- **Money (Task 4):** run only with an approved ceiling; this plan proposes **USD 6**. For reference, F1 spent USD 2.04 on the read-only cases and E1 spent USD 1.10 on `doctor-*`. Never weaken the sandbox.

## Prerequisites

| Tool | Needed by | Check |
| --- | --- | --- |
| bash, git, python3, node, `shellcheck` | Tasks 1–3 | `./tests/run.sh` exits 0 before you start with **1031** `ok`. If F3a was merged first, expect 1063 before and **1112** at the end |
| nested Bash sandbox, node + npm with network, `gitleaks` ≥ 8.19, `claude` logged in | Task 4 | see `docs/plans/2026-10-28-keel-harness-v0.3-f1b-plan.md` Task 1, including the npm CA fix |

---

## Task 1 — the structural test (red)

- [ ] **Step 1:** create `tests/keel_evals_test.sh` (executable):

```bash
#!/usr/bin/env bash
# E2: every eval case belongs to one grant group, lists the tools it needs, and grades "writes
# nothing" from tool calls, not from files (Claude Code's Bash tool creates .claude/.cc-writes/).
set -uo pipefail
. "$(dirname "$0")/keel_helpers.sh"
EV="$KEEL/evals"
tags_of() { grep -h '^tags:' "$1/case.yaml" "$1/prompt.md" 2>/dev/null | head -1; }
tools_of() { grep -h '^allowed_tools:' "$1/prompt.md" | head -1; }

! grep -rqE 'path: "?\*\*/\*"?$' "$EV"/*/graders; check "no grader counts every created file (file_exists **/*)" $?
for d in "$EV"/*/; do
  c="$(basename "$d")"; t="$(tags_of "$d")"; a="$(tools_of "$d")"
  n=0; g=""
  for x in readonly bash tools effect; do printf '%s' "$t" | grep -qE "[[, ]$x[],]" && { n=$((n + 1)); g=$x; }; done
  [ "$n" = 1 ]; check "$c is in exactly one grant group (readonly | bash | tools | effect)" $?
  case "$g" in
    readonly) ! printf '%s' "$a" | grep -qE '\b(Bash|Write|Edit)\b'; check "$c (readonly) lists no gated tool" $? ;;
    bash) printf '%s' "$a" | grep -q '\bBash\b' && ! printf '%s' "$a" | grep -qE '\b(Write|Edit)\b'; check "$c (bash) lists Bash and no Write/Edit" $? ;;
    tools | effect) printf '%s' "$a" | grep -q '\bBash\b' && printf '%s' "$a" | grep -q '\bWrite\b'; check "$c ($g) lists Bash and Write" $? ;;
  esac
  if { [ "$g" = readonly ] || [ "$g" = bash ]; } && [ "$c" != should-not-trigger ]; then
    for f in no-write no-edit no-notebook-edit no-bash-write; do
      grep -q 'max: 0' "$d/graders/$f.md" 2>/dev/null; check "$c grades writes from tool calls ($f)" $?
    done
  fi
done
grep -q 'rules)' "$EV/should-not-trigger/graders/skill-silent.md"; check "should-not-trigger covers the rules skill" $?

# The Bash write pattern, as the graders carry it, on commands the read-only skills really run
if command -v node >/dev/null 2>&1; then
  re="$(sed -n "s/^input_match: '\(.*\)'$/\1/p" "$EV/doctor-finds-drift/graders/no-bash-write.md")"
  out="$(RE="$re" node -e '
    const re = new RegExp(process.env.RE), j = c => JSON.stringify({ command: c });
    const reads = ["bash scripts/harness-check.sh 2>&1", "make harness-check 2>/dev/null", "cmp a b >/dev/null 2>&1", "git status --short", "wc -l AGENTS.md"];
    const writes = ["echo x > f", "printf a >> f", "make gate-fast | tee out.txt", "rm -rf .agents/run", "sed -i s/a/b/ f", "git add -A", "git commit -m x", "cp a b", "mkdir -p x"];
    const bad = reads.filter(c => re.test(j(c))).concat(writes.filter(c => !re.test(j(c))));
    console.log(bad.length ? "misclassified: " + bad.join(" | ") : "ok");')"
  [ "$out" = ok ]; check "no-bash-write tells read commands from write commands ($out)" $?
else
  echo "  skip no-bash-write pattern (node not installed)"
fi
finish
```

- [ ] **Step 2:** `bash tests/keel_evals_test.sh | grep -c FAIL` → **16** (the old tree fails it). Do not commit yet.

## Task 2 — the eval edits (green)

- [ ] **Step 1:** save this script **outside the repository** (e.g. `/tmp/e2-apply.py`) and run it from the repository root with `python3 /tmp/e2-apply.py`. Expected output: `E2 eval edits applied`. Each edit asserts that its target text exists exactly once, so a mismatch stops it before it writes anything wrong.

```python
import os, re
E = 'plugins/keel-harness/evals/'
def sub(p, old, new):
    s = open(p).read(); assert s.count(old) == 1, (p, old); open(p, 'w').write(s.replace(old, new))
BASH_WRITE = r'''"command"\s*:\s*"(?:[^"\\]|\\.)*(?:(?<![0-9&])>>?(?!&|\s*/dev/null)|\btee\b|\brm\s|\bmv\s|\bcp\s|\bsed\s+-i|\btouch\s|\bmkdir\s|\bgit\s+(?:add|commit|apply|checkout|reset|stash)\b|\bnpm\s+(?:i|install|ci)\b)'''
GRADERS = {
 'no-write.md':          "---\ntype: tool_used\ntool: Write\nmin: 0\nmax: 0\nweight: 0.25\n---\n",
 'no-edit.md':           "---\ntype: tool_used\ntool: Edit\nmin: 0\nmax: 0\nweight: 0.25\n---\n",
 'no-notebook-edit.md':  "---\ntype: tool_used\ntool: NotebookEdit\nmin: 0\nmax: 0\nweight: 0.25\n---\n",
 'no-bash-write.md':     "---\ntype: tool_used\ntool: Bash\ninput_match: '" + BASH_WRITE + "'\nmin: 0\nmax: 0\nweight: 0.25\n---\n",
}
# 1. write graders: file_exists "**/*" counts Claude Code's own .claude/.cc-writes/ (E1)
for case, old in [('assess-claude-md', 'no-writes.md'), ('assess-mature-repo', 'no-writes.md'),
                  ('doctor-finds-drift', 'writes-nothing.md'), ('doctor-validator-drift', 'writes-nothing.md')]:
    os.remove(E + case + '/graders/' + old)
    for n, body in GRADERS.items():
        open(E + case + '/graders/' + n, 'w').write(body)
# 2. should-not-trigger also covers the rules skill (added in v0.2)
sub(E + 'should-not-trigger/graders/skill-silent.md', '(assess|build|doctor)', '(assess|build|doctor|rules)')
# 3. tools each case needs, so an ungranted one shows as "not granted"
for c in ['build-java', 'build-python', 'build-react', 'build-typescript']:
    sub(E + c + '/prompt.md', 'allowed_tools: [Read, Glob, Grep, Skill, TodoWrite]', 'allowed_tools: [Read, Glob, Grep, Skill, TodoWrite, Bash, Write, Edit]')
sub(E + 'gate-catches-defect/prompt.md', 'allowed_tools: [Read, Glob, Grep]', 'allowed_tools: [Read, Glob, Grep, Bash, Write]')
# 4. one grant group per case: readonly (no grant), bash (--allow-tools Bash), tools (--allow-tools Bash Write Edit)
groups = {'readonly': ['assess-claude-md', 'assess-mature-repo'], 'bash': ['doctor-finds-drift', 'doctor-validator-drift'],
          'tools': ['build-java', 'build-python', 'build-react', 'build-typescript', 'gate-catches-defect', 'rules-architecture-java',
                    'rules-brownfield', 'rules-greenfield']}
# rules-effect-* keep their existing `effect` tag as their group: same grant as tools, run with --ablation none
for g, cases in groups.items():
    for c in cases:
        p = E + c + '/case.yaml'; s = open(p).read()
        s2 = re.sub(r'^tags: \[(.*)\]$', lambda m: 'tags: [' + m.group(1) + ', ' + g + ']', s, count=1, flags=re.M)
        assert s2 != s, p; open(p, 'w').write(s2)
sub(E + 'should-not-trigger/prompt.md', 'allowed_tools: [Read, Glob, Grep, Skill]\n', 'allowed_tools: [Read, Glob, Grep, Skill]\ntags: [readonly]\n')
print('E2 eval edits applied')
```

- [ ] **Step 2: check.**
  - `bash tests/keel_evals_test.sh | grep -c FAIL` → 0, and `grep -c '  ok'` on it → 49.
  - `./tests/run.sh` exits 0 with **1080** `ok`.
  - `claude plugin validate ./plugins/keel-harness --strict` → `Validation passed`.
  - `git status --short`: 4 graders deleted, 19 files modified, 17 new files (16 graders and `tests/keel_evals_test.sh`). Nothing outside `evals/` and `tests/`.
- [ ] **Step 3:** `git add -A` and commit `test(keel-harness): grade eval writes from tool calls; one grant group per case` and push.

## Task 3 — README

- [ ] **Step 1:** apply this diff to `plugins/keel-harness/README.md` (`git apply`; if F3a landed first, `git apply --3way`):

~~~diff
--- a/plugins/keel-harness/README.md
+++ b/plugins/keel-harness/README.md
@@ -78,7 +78,19 @@ on the changed files; it is never run by the hook and never wired to CI.
 
 ## Evals (`claude plugin eval`, manual and paid)
 
-Run `claude plugin eval . --scaffold` from `plugins/keel-harness/`. Host prerequisites per case:
+Run from `plugins/keel-harness/`, one grant group at a time. `--allow-tools` applies to every case in
+a run, and `--case` keeps only its last value, so each group is selected by its tag:
+
+```bash
+claude plugin eval . --tag readonly --scaffold --trust-plugin --max-cost-usd <ceiling>
+claude plugin eval . --tag bash     --scaffold --trust-plugin --allow-tools Bash --max-cost-usd <ceiling>
+claude plugin eval . --tag tools    --scaffold --trust-plugin --allow-tools Bash Write Edit --max-cost-usd <ceiling>
+claude plugin eval . --tag effect   --scaffold --trust-plugin --allow-tools Bash Write Edit --ablation none --max-cost-usd <ceiling>
+```
+
+"Writes nothing" is graded from tool calls (`no-write`, `no-edit`, `no-notebook-edit`, `no-bash-write`,
+weight 0.25 each), not with `file_exists`, which also counts the `.claude/.cc-writes/` that Claude
+Code's Bash tool creates. Host prerequisites per case:
 
 | Case | Host prerequisites |
 | --- | --- |
~~~

- [ ] **Step 2:** `./tests/run.sh` still exits 0. Commit `docs(keel-harness): run evals by grant group` and push.

## Task 4 — re-measure the read-only and Bash groups (paid, after approval)

The goal is a new baseline for the five cases whose graders changed. F2c folds `doctor` into `assess`
(D51), and the merged skill must score no worse than this.

- [ ] **Step 1: smoke run** (one run per arm, ceiling USD 1), from `plugins/keel-harness/`:

```bash
claude plugin eval . --tag bash --runs 1 --scaffold --trust-plugin --allow-tools Bash \
  --no-publish --max-cost-usd 1 --json /tmp/e2-smoke.json
```

  Qualification:
  - the JSON lists the four `no-*` graders for both `doctor-*` cases, each with weight 0.25;
  - none of the four fails in either arm only because of `.claude/.cc-writes/`;
  - `no-bash-write` fails only on a run whose Bash calls really wrote something. Quote the command when it does.

  If a grader is rejected as invalid, or `no-bash-write` fails on a read command, **stop** and report it with the JSON excerpt.
- [ ] **Step 2: HARD STOP.** Send the owner:
  - the smoke cost;
  - the estimate for `--tag readonly` (3 cases) plus `--tag bash` (2 cases) at 3 runs per arm;
  - the proposed ceiling (USD 6 unless the estimate is higher).

  Wait for written approval.
- [ ] **Step 3: measured runs**, one per group, each with its share of the approved ceiling:

```bash
claude plugin eval . --tag readonly --scaffold --trust-plugin --no-publish \
  --max-cost-usd <A> --json /tmp/e2-readonly.json
claude plugin eval . --tag bash --scaffold --trust-plugin --allow-tools Bash --no-publish \
  --max-cost-usd <B> --json /tmp/e2-bash.json
```

  Exit 2 = ceiling hit: stop and report partial results. Exit 1 = some case below 1.0; that is data.
- [ ] **Step 4: record.**
  1. Copy the three JSON files and each run's `aggregate-result.json` to `docs/evals/keel-v0.3-e2/`.
  2. In the README, under the E1 results, add **"E2 results"**. Give the date, the Claude Code version, the commit and the host, and the total spent against the ceiling. Then a table with columns `Case | WITH | W-OUT | Δ | Cost (USD)`, one row per measured case.
  3. Add one line per case comparing it with its F1 or E1 row, naming what changed (graders, grants).
  4. Do not re-run anything to chase a number.
- [ ] **Step 5:** tick E2 in the master plan's status table, with the evidence column filled. Commit `docs(keel-harness): E2 results` and push. Report to the owner: the table, the cost, every deviation from this plan. Do not open a pull request.
