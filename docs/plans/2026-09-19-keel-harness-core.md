# keel-harness Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the `keel-harness` Claude Code plugin with all three skills working end to end on TypeScript repositories, distributed from the `aether-labs` marketplace in `aether-labs-org/plugins`.

**Architecture:** The plugin is Markdown and JSON only — no runtime, no build step, no executables. Three skills (`assess`, `build`, `doctor`) share nothing at runtime; each carries its own `references/`. What the plugin *writes* into a user repository is POSIX `make` plus `sh` sensor wrappers, so the harness survives uninstalling the plugin. Tests are `claude plugin validate`, shell assertions over generated files, and `claude plugin eval` cases scored against a no-plugin baseline.

**Tech Stack:** Markdown, JSON, YAML, POSIX sh, GNU make, `claude plugin validate`/`eval`, jq, GitHub Actions.

**Spec:** `docs/specs/2026-09-19-keel-harness-design.md` — read it before Task 1. Every task below cites the spec section it implements; where the plan says "copy §N verbatim", that section is the content.

**Scope of this plan:** spec phases 0–5 and 7 — the plugin, TypeScript support, and `doctor`. Spec phase 6 (Python, Go, Java, Next.js, Terraform) and phase 8 (release) are a second plan, written once Task 5 has fixed the real shape of a sensor wrapper. v0.1 is not released until both plans are done.

## Global Constraints

- All code, file names, comments, documentation and commit messages are in **English**.
- Plugin name: `keel-harness`. Marketplace name: `aether-labs`. Skills invoke as `/keel-harness:<skill>`.
- License: Apache-2.0 (copy the `LICENSE` file from `aether-labs-org/skills`).
- Requires Claude Code **v2.1.269 or newer** for `claude plugin eval`. Installed here: 2.1.278.
- The plugin ships **no** `hooks/`, **no** `.mcp.json`, **no** `bin/`, **no** `commands/` directory. Spec §9.
- Component directories live at the **plugin root**; only `plugin.json` and `marketplace.json` live in `.claude-plugin/`.
- An installed plugin is copied to a cache and cannot read `../`. Nothing in `plugins/keel-harness/` may reference a path outside itself.
- `v0.1 informs, it does not block.` The only hook written into a user repo is `PostToolUse`. No `PreToolUse`, no `pre-commit`, no sandbox policy.
- No sensor may call a language model. The money ceiling of the generated gate is US$0.00.
- Generated `AGENTS.md` is **≤ 100 lines**, and every command in it must exist in the target repo — never invent a command.
- Generated state keys are English: `model_baseline`, `installed_at`, `runner`, `layers`, `not_installed`, `sensors[].id/class/snapshot/review_by`.
- Sensor classes: `security` and `correctness` never ratchet and never take a raisable threshold; `heuristic` does both and carries `review_by`.
- Host prerequisites for the eval tasks: `bwrap` (present), **`socat` (missing — install before Task 6)**, **`gitleaks` (missing — install before Task 6)**, `make`, `jq`, `node` + `npm`.
- `<abs-path>` in a command means the absolute path of this repository's checkout; substitute it before running.
- Never `git push` or create a remote without asking the repository owner first.

---

### Task 1: Repository scaffold, plugin manifest, three skill stubs

Implements spec phases 0–1 (spec §3, §4, §10).

**Files:**
- Create: `LICENSE`, `README.md`, `.gitignore`, `Makefile`
- Create: `tests/run.sh`, `tests/structure_test.sh`
- Create: `.claude-plugin/marketplace.json`
- Create: `plugins/keel-harness/.claude-plugin/plugin.json`
- Create: `plugins/keel-harness/README.md`
- Create: `plugins/keel-harness/skills/assess/SKILL.md`
- Create: `plugins/keel-harness/skills/build/SKILL.md`
- Create: `plugins/keel-harness/skills/doctor/SKILL.md`
- Create: `.github/workflows/validate.yml`

**Interfaces:**
- Consumes: nothing.
- Produces: the marketplace id `aether-labs`, the plugin id `keel-harness`, skill names `assess`, `build`, `doctor`, and the test entrypoint `tests/run.sh` (exit 0 = all checks pass) that every later task extends with one more `*_test.sh` file.

- [ ] **Step 1: Write the failing structure test**

Create `tests/structure_test.sh`:

```bash
#!/usr/bin/env bash
# Structural checks for the marketplace and the keel-harness plugin.
set -uo pipefail
fail=0
check() { # check <description> <condition-exit-code>
  if [ "$2" -eq 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fail=1; fi
}
root="$(cd "$(dirname "$0")/.." && pwd)"
mp="$root/.claude-plugin/marketplace.json"
pj="$root/plugins/keel-harness/.claude-plugin/plugin.json"

jq -e . "$mp" >/dev/null 2>&1; check "marketplace.json is valid JSON" $?
[ "$(jq -r .name "$mp" 2>/dev/null)" = "aether-labs" ]; check "marketplace name is aether-labs" $?
[ -n "$(jq -r '.owner.name // empty' "$mp" 2>/dev/null)" ]; check "marketplace has owner.name" $?
[ "$(jq -r '.plugins[0].source' "$mp" 2>/dev/null)" = "./plugins/keel-harness" ]; check "plugin source path" $?
[ -d "$root/plugins/keel-harness" ]; check "plugin source path exists" $?
[ "$(jq -r '.plugins[0].version // "unset"' "$mp" 2>/dev/null)" = "unset" ]; check "no version in marketplace entry" $?

jq -e . "$pj" >/dev/null 2>&1; check "plugin.json is valid JSON" $?
[ "$(jq -r .name "$pj" 2>/dev/null)" = "keel-harness" ]; check "plugin name is keel-harness" $?

for forbidden in hooks .mcp.json bin commands; do
  [ ! -e "$root/plugins/keel-harness/$forbidden" ]
  check "plugin has no $forbidden (spec 9)" $?
done

for s in assess build doctor; do
  f="$root/plugins/keel-harness/skills/$s/SKILL.md"
  [ -f "$f" ]; check "skills/$s/SKILL.md exists" $?
  grep -q "^name: $s$" "$f" 2>/dev/null; check "skills/$s frontmatter name" $?
  grep -q "^description: >" "$f" 2>/dev/null; check "skills/$s frontmatter description" $?
done

# The plugin must not reference anything outside its own directory.
! grep -rn '\.\./\.\.' "$root/plugins/keel-harness" --include='*.md' --include='*.json' >/dev/null 2>&1
check "plugin does not escape its directory" $?

exit $fail
```

Create `tests/run.sh`:

```bash
#!/usr/bin/env bash
# Runs every *_test.sh in this directory. Exit 0 only if all pass.
set -uo pipefail
cd "$(dirname "$0")"
status=0
for t in *_test.sh; do
  echo "== $t"
  bash "$t" || status=1
done
exit $status
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
chmod +x tests/run.sh tests/structure_test.sh && ./tests/run.sh
```

Expected: FAIL — `marketplace.json is valid JSON` and every check after it.

- [ ] **Step 3: Write the marketplace and the plugin manifest**

`.claude-plugin/marketplace.json`:

```json
{
  "name": "aether-labs",
  "owner": {
    "name": "Aether Labs",
    "url": "https://github.com/aether-labs-org"
  },
  "description": "Claude Code plugins by Aether Labs.",
  "plugins": [
    {
      "name": "keel-harness",
      "source": "./plugins/keel-harness",
      "description": "Assess, install and maintain an AI-agent harness in a repository.",
      "category": "development",
      "tags": ["harness", "agents-md", "quality-gate", "sensors"]
    }
  ]
}
```

`plugins/keel-harness/.claude-plugin/plugin.json`:

```json
{
  "name": "keel-harness",
  "description": "Assess, install and maintain an AI-agent harness in a repository.",
  "version": "0.1.0",
  "author": { "name": "Aether Labs" },
  "license": "Apache-2.0",
  "repository": "https://github.com/aether-labs-org/plugins",
  "keywords": ["harness", "agents", "agents-md", "quality-gate", "sensors"]
}
```

Do not add a `version` to the marketplace entry: Claude Code always uses the `plugin.json` value, and a second copy only goes stale.

- [ ] **Step 4: Write the three SKILL.md stubs**

Each file gets the frontmatter copied **verbatim** from spec §4 — the description is the trigger mechanism and must not be paraphrased — plus a one-paragraph body stating the skill's single rule. Example for `skills/assess/SKILL.md`:

```markdown
---
name: assess
description: >
  Diagnoses how ready a repository is for AI coding agents. Scans the repo against a
  six-axis rubric — bootstrap, guides, fast sensors, slow sensors, enforcement, context —
  reporting each axis as absent, partial or present with the file that proves it, plus the
  cost of closing each gap in setup minutes and seconds added to the gate. Writes nothing.
  Use when someone asks whether their repository is ready for AI agents, what is missing to
  work with coding agents, for an agent-readiness assessment or a harness diagnosis — and
  always before the build skill.
---

# Assess

Report how ready this repository is for AI coding agents. **This skill writes nothing** —
no files created, no files modified. Full behaviour lands in Task 2.
```

Do the same for `build` and `doctor` with their spec §4 descriptions and a one-line body naming their single rule: `build` writes nothing before the user confirms; `doctor` reports and proposes, never writes.

- [ ] **Step 5: Write the repo files**

`.gitignore`:

```
.agents/last-run.log
evals/results/
node_modules/
.DS_Store
```

`Makefile`:

```make
.PHONY: check validate

check:
	./tests/run.sh

validate:
	claude plugin validate ./plugins/keel-harness --strict
```

`LICENSE`: copy from `aether-labs-org/skills` (Apache-2.0, unmodified).

`README.md`: name the repository, list the plugins in a table (name, what it does, install command), and show the two install lines:

```
/plugin marketplace add aether-labs-org/plugins
/plugin install keel-harness@aether-labs
```

`plugins/keel-harness/README.md`: one paragraph on what the plugin does, the three commands `/keel-harness:assess`, `/keel-harness:build`, `/keel-harness:doctor`, one line each on what they read and write, and the v0.1 rule "informs, does not block".

- [ ] **Step 6: Run the structural test to verify it passes**

```bash
./tests/run.sh
```

Expected: PASS, every line `ok`.

- [ ] **Step 7: Verify the plugin validates and loads**

```bash
claude plugin validate ./plugins/keel-harness --strict
claude --plugin-dir ./plugins/keel-harness -p "/help" 2>&1 | grep -i keel-harness
```

Expected: validate reports no errors and no warnings; the `/help` output lists `keel-harness:assess`, `keel-harness:build` and `keel-harness:doctor`.

- [ ] **Step 8: Decide what CI can run, then write the workflow**

Check whether `claude plugin validate` works with no credentials, which decides whether CI can call it:

```bash
env -u ANTHROPIC_API_KEY -u CLAUDE_CODE_OAUTH_TOKEN claude plugin validate ./plugins/keel-harness --strict; echo "exit=$?"
```

Write `.github/workflows/validate.yml` running `./tests/run.sh` on every push and pull request (ubuntu-latest, `jq` is preinstalled). Add a second step running `npm i -g @anthropic-ai/claude-code && claude plugin validate ./plugins/keel-harness --strict` **only if** the command above exited 0 without credentials. If it did not, leave a comment in the workflow saying validation runs locally via `make validate` before release, and why.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: scaffold aether-labs marketplace and keel-harness plugin skeleton"
```

---

### Task 2: `assess` — rubric and full skill body

Implements spec phase 2 (spec §5).

**Files:**
- Create: `plugins/keel-harness/skills/assess/references/rubric.md`
- Create: `plugins/keel-harness/skills/assess/references/harness-model.md` (copied from `aether-labs-org/skills/skills/agents-md-architect/references/harness-model.md`, unmodified)
- Modify: `plugins/keel-harness/skills/assess/SKILL.md`
- Create: `tests/assess_test.sh`

**Interfaces:**
- Consumes: the skill stub and `tests/run.sh` from Task 1.
- Produces, and every later task depends on these exact strings:
  - Axis labels, in this order: `Bootstrap`, `Guides`, `Fast sensors`, `Slow sensors`, `Enforcement`, `Context`.
  - States: `present`, `partial`, `absent`.
  - The report is a Markdown table with the header `| Axis | State | Evidence | Cost to close |`, one row per axis, evidence as a backtick-quoted repo-relative path or `—`, cost as `N setup minutes`, `+N.Ns gate`, `not measured`, or `—`.
  - Confidence vocabulary for inferences: `high`, `low`, `none`.

- [ ] **Step 1: Write the failing test**

Create `tests/assess_test.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
fail=0
check() { if [ "$2" -eq 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fail=1; fi; }
root="$(cd "$(dirname "$0")/.." && pwd)"
sk="$root/plugins/keel-harness/skills/assess"

[ -f "$sk/references/rubric.md" ]; check "rubric.md exists" $?
for axis in "Bootstrap" "Guides" "Fast sensors" "Slow sensors" "Enforcement" "Context"; do
  grep -q "$axis" "$sk/references/rubric.md" 2>/dev/null; check "rubric has axis: $axis" $?
done
for state in present partial absent; do
  grep -qi "$state" "$sk/references/rubric.md" 2>/dev/null; check "rubric has state: $state" $?
done
[ -f "$sk/references/harness-model.md" ]; check "harness-model.md copied" $?
grep -q "Cost to close" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md pins the report table header" $?
grep -q "setup minutes" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md names the setup-minutes unit" $?
grep -q "not measured" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md forbids guessing a cost" $?
grep -qi "writes nothing" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md states the no-write rule" $?
grep -q "aggregate score" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md forbids an aggregate score" $?

exit $fail
```

- [ ] **Step 2: Run it to verify it fails**

```bash
chmod +x tests/assess_test.sh && bash tests/assess_test.sh
```

Expected: FAIL from `rubric.md exists` onward.

- [ ] **Step 3: Write `references/rubric.md`**

Copy the six-axis × three-state table from spec §5 verbatim as the file's core. Add, under it: the two cost units defined in spec §5 ("setup minutes" and "seconds added to the gate", measured by running the tool once, never estimated, and reported as `not measured` when the tool is absent), the rule that there is no aggregate score and why, and the three-confidence inference table from spec §5 including the `none` outcome that declines to install a layer and records the reason.

- [ ] **Step 4: Copy `harness-model.md`**

```bash
cp ../skills/skills/agents-md-architect/references/harness-model.md \
   plugins/keel-harness/skills/assess/references/harness-model.md
```

Adjust the path if the `skills` repository is checked out elsewhere. Do not edit the file.

- [ ] **Step 5: Write the `assess` body**

Keep the Task 1 frontmatter untouched. The body has five sections:

1. **The single rule** — this skill writes nothing; no `Write`, no `Edit`, no shell command that modifies the repository. Read-only discovery only.
2. **Discovery** — reuse the stack-marker table and the parallel discovery commands from steps 1–2 of `agents-md-architect/SKILL.md`, including the "never invent commands" rule. Monorepos can show several stacks.
3. **Scoring** — read `references/rubric.md`, classify each of the six axes as `present`, `partial` or `absent`, and record the file that proves it.
4. **Cost** — for each non-`present` axis, state setup minutes, and for a missing fast sensor also state the seconds it would add, measured by running the tool once when it is installed. When it is not installed, write `not measured`; never guess.
5. **The report** — emit exactly the table pinned in this task's Interfaces block, then a short paragraph per `absent` axis naming what is missing and the cheapest next step. Never emit a total or an overall grade.

- [ ] **Step 6: Run the test to verify it passes**

```bash
./tests/run.sh
```

Expected: PASS.

- [ ] **Step 7: Verify against a real repository**

```bash
git clone --depth 1 https://github.com/sindresorhus/type-fest /tmp/keel-probe
cd /tmp/keel-probe && git status --porcelain > /tmp/keel-before.txt
claude --plugin-dir <abs-path>/plugins/keel-harness \
  -p "Is this repository ready for AI coding agents?" 2>&1 | tee /tmp/keel-assess.txt
git status --porcelain > /tmp/keel-after.txt && diff /tmp/keel-before.txt /tmp/keel-after.txt
```

Expected: the output contains the six-axis table with a state and an evidence path per axis, and `diff` reports no difference — the repository is untouched.

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "feat(assess): add six-axis rubric and full assessment flow"
```

---

### Task 3: First eval cases — `assess-mature-repo` and `should-not-trigger`

Implements spec phase 3 (spec §8). Write the measurement before writing the skill that changes files.

**Files:**
- Create: `plugins/keel-harness/evals/assess-mature-repo/prompt.md`
- Create: `plugins/keel-harness/evals/assess-mature-repo/case.yaml`
- Create: `plugins/keel-harness/evals/assess-mature-repo/scaffold.sh`
- Create: `plugins/keel-harness/evals/assess-mature-repo/graders/{rubric-axes,rubric-states,evidence-path,no-writes,skill-fired}.md`
- Create: `plugins/keel-harness/evals/should-not-trigger/prompt.md`
- Create: `plugins/keel-harness/evals/should-not-trigger/graders/skill-silent.md`

**Interfaces:**
- Consumes: the axis labels, states and table header from Task 2.
- Produces: the eval suite root `plugins/keel-harness/evals/`, which Task 6 and Task 7 extend with more cases.

- [ ] **Step 1: Write the scaffold that builds a mature TypeScript repo**

`evals/assess-mature-repo/scaffold.sh` — runs as you, outside the sandbox, only with `--scaffold`:

```bash
#!/usr/bin/env bash
# Builds a small but mature TypeScript repository in the empty eval workspace:
# lockfile + build target + tsconfig + eslint + tests, no AGENTS.md, no docs/, no CI.
set -euo pipefail

mkdir -p src
cat > package.json <<'JSON'
{
  "name": "ledger",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "build": "tsc -p tsconfig.json",
    "lint": "eslint src",
    "test": "vitest run"
  },
  "devDependencies": { "typescript": "5.6.2", "eslint": "9.11.1", "vitest": "2.1.1" }
}
JSON
cat > package-lock.json <<'JSON'
{ "name": "ledger", "version": "1.0.0", "lockfileVersion": 3, "requires": true, "packages": {} }
JSON
cat > tsconfig.json <<'JSON'
{ "compilerOptions": { "strict": true, "target": "ES2022", "outDir": "dist" }, "include": ["src"] }
JSON
cat > eslint.config.js <<'JS'
export default [{ files: ["src/**/*.ts"], rules: { "no-console": "error" } }];
JS
cat > src/posting.ts <<'TS'
export function applyFee(cents: number): number {
  return Math.round(cents * 0.98);
}
TS
cat > src/posting.test.ts <<'TS'
import { expect, test } from "vitest";
import { applyFee } from "./posting";
test("applies the fee", () => { expect(applyFee(1224)).toBe(1200); });
TS
git init -q && git add -A && git -c user.email=eval@local -c user.name=eval commit -qm "initial"
```

`evals/assess-mature-repo/case.yaml`:

```yaml
schema_version: "1.1"
name: assess-mature-repo
description: The rubric is applied to a mature TypeScript repo, and nothing is written.
tags: [assess, smoke]
context:
  scaffold_script: scaffold.sh
```

`evals/assess-mature-repo/prompt.md`:

```markdown
---
max_turns: 25
allowed_tools: [Read, Glob, Grep, Skill]
---

I want to start using AI coding agents on this repository. Is it ready? What is missing?
```

- [ ] **Step 2: Write the graders**

`graders/rubric-axes.md` — the axes, in order, in one response:

```markdown
---
type: regex
pattern: 'Bootstrap[\s\S]*Guides[\s\S]*Fast sensors[\s\S]*Slow sensors[\s\S]*Enforcement[\s\S]*Context'
target: last_message
weight: 2
---
```

`graders/rubric-states.md` — exactly six state cells, which is the rubric's shape and not something a plain model emits:

```markdown
---
type: regex
pattern: '\|\s*(present|partial|absent)\s*\|'
match: "count:6"
flags: i
target: last_message
weight: 2
---
```

`graders/evidence-path.md` — at least one backticked file path as proof:

```markdown
---
type: regex
pattern: '`[\w./-]+\.(json|ts|js|mjs|cjs|yml|yaml|toml|md|xml)`'
target: last_message
---
```

`graders/no-writes.md` — the skill created nothing:

```markdown
---
type: file_exists
path: "**/*"
exists: false
---
```

`graders/skill-fired.md` — indicator only; excluded from the score in both arms:

```markdown
---
type: tool_used
tool: Skill
input_match: '"skill"\s*:\s*"(?:[\w-]+:)?assess"'
---
```

`should-not-trigger/prompt.md`:

```markdown
---
max_turns: 5
allowed_tools: [Read, Glob, Grep, Skill]
---

In git, what is the difference between rebasing and merging?
```

`should-not-trigger/graders/skill-silent.md` — scored in both arms on purpose:

```markdown
---
type: tool_used
tool: Skill
input_match: '"skill"\s*:\s*"(?:[\w-]+:)?(assess|build|doctor)"'
min: 0
max: 0
arm: both
---
```

- [ ] **Step 3: Run the suite with the plugin arm only, to shake out grader mistakes cheaply**

```bash
cd plugins/keel-harness
claude plugin eval . --scaffold --ablation none --runs 1
```

Expected: both cases run to completion. If `assess-mature-repo` scores below 1.0, read `evals/results/<timestamp>/report.html` and fix the graders or the skill body — not the prompt, which must stay the way a user would phrase it.

- [ ] **Step 4: Run the full two-arm suite and record Δ**

```bash
claude plugin eval . --scaffold
```

Expected: `assess-mature-repo` shows a **positive Δ** driven by `rubric-axes` and `rubric-states`; `skill-fired` appears as an indicator with `scored: false`; `should-not-trigger` scores 1.0 in both arms with Δ = 0, which is the correct result for that case.

If Δ is zero on `assess-mature-repo`, the without-arm is producing the same table — tighten `rubric-states` before changing anything else.

- [ ] **Step 5: Record the numbers**

Append a short `## Eval baseline` section to `plugins/keel-harness/README.md` with the date, the Claude Code version, and the WITH / W-OUT / Δ per case from this run. Task 6 adds its cases to the same table. This is the only Δ history that exists until v0.2.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "test(evals): add assess-mature-repo and should-not-trigger cases"
```

---

### Task 4: `build` phases 1–2 — bootstrap and minimal guides

Implements spec phase 4 (spec §4, §5, §6, §10).

**Files:**
- Create: `plugins/keel-harness/skills/build/references/agents-md-template.md` (copied, ceiling 120 → 100)
- Create: `plugins/keel-harness/skills/build/references/context-engineering.md` (copied unmodified)
- Modify: `plugins/keel-harness/skills/build/SKILL.md`
- Create: `tests/build_test.sh`

**Interfaces:**
- Consumes: the `assess` report format from Task 2 — `build` starts from that picture and never re-derives it silently.
- Produces `.agents/state.yml`, whose schema is fixed here and read by Task 5 and Task 7:

```yaml
model_baseline: claude-opus-5        # the model that installed the harness
installed_at: 2026-09-19             # ISO date
runner: Makefile
gate:
  fast:
    ceiling_seconds: 5               # a sensor that blows the ceiling is not installed
layers:                              # installed | not_installed
  bootstrap: installed
  guides: installed
  fast_gate: not_installed
  contract: not_installed
not_installed:                       # layer -> the reason, in the kit's own words
  fitness_functions: "could not infer module boundaries"
sensors: []                          # filled by Task 5
```

- Produces the confirmation gate: `build` writes nothing until the user accepts a single structured proposal. This rule has no exception and no flag; an eval case waives it only by saying so in the user's own prompt.

- [ ] **Step 1: Write the failing test**

Create `tests/build_test.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
fail=0
check() { if [ "$2" -eq 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fail=1; fi; }
root="$(cd "$(dirname "$0")/.." && pwd)"
sk="$root/plugins/keel-harness/skills/build"

[ -f "$sk/references/agents-md-template.md" ]; check "agents-md-template.md exists" $?
! grep -q "120" "$sk/references/agents-md-template.md" 2>/dev/null; check "template ceiling is not 120" $?
grep -q "100" "$sk/references/agents-md-template.md" 2>/dev/null; check "template ceiling is 100" $?
[ -f "$sk/references/context-engineering.md" ]; check "context-engineering.md copied" $?

grep -q "model_baseline" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md writes model_baseline" $?
grep -q "installed_at" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md writes installed_at" $?
grep -q "not_installed" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md records declined layers" $?
grep -qi "before writing anything" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md states the confirmation gate" $?
grep -qi "never invent" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md keeps the never-invent-commands rule" $?
grep -q "100 lines" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md enforces the 100-line ceiling" $?
grep -qi "resumable" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md is resumable layer by layer" $?

# Portuguese state keys are a regression: the spec fixed English keys.
! grep -qE "instalado_em|camadas|nao_instaladas|classe:|revisar_em" "$sk/SKILL.md" 2>/dev/null
check "state keys are English" $?

exit $fail
```

- [ ] **Step 2: Run it to verify it fails**

```bash
chmod +x tests/build_test.sh && bash tests/build_test.sh
```

Expected: FAIL from `agents-md-template.md exists` onward.

- [ ] **Step 3: Copy and adjust the two references**

```bash
cp ../skills/skills/agents-md-architect/references/context-engineering.md \
   plugins/keel-harness/skills/build/references/context-engineering.md
cp ../skills/skills/agents-md-architect/references/agents-md-template.md \
   plugins/keel-harness/skills/build/references/agents-md-template.md
```

In the copied template, change every statement of the size ceiling from "~100 lines (hard cap 120)" to a flat **100 lines**, and delete the `multi-agent-orchestration.md` row and any orchestration section — orchestration is outside the installed harness (spec §4).

- [ ] **Step 4: Write the `build` body, phases 1–2 only**

Keep the Task 1 frontmatter. The body is a numbered sequence, each phase resumable on its own:

1. **Read the picture.** If `assess` ran in this session, use its table. If not, run the same discovery (stack markers, real scripts, existing sensors) before proposing anything. Never invent a command.
2. **Phase 1 — bootstrap.** Find the real install+build commands. If a single target that does both does not exist, propose `make bootstrap` wrapping the real commands. Confirm before writing.
3. **Phase 2 — guides.** Fill `references/agents-md-template.md` with real, confirmed values, ≤ 100 lines, every deep topic replaced by a `→ docs/X.md` pointer. Create only the `docs/` stubs the user confirmed: a heading and a one-line TODO, never invented content.
4. **The single confirmation gate.** Present one structured proposal covering every file to be created or changed, then stop. Write nothing before the user accepts. Apply the three-confidence rule from `assess` (spec §5): high → state the inference and ask for acceptance; low → a narrow question listing the options seen; none → declare that you could not infer, **do not install that layer**, and record the reason under `not_installed` in `.agents/state.yml`.
5. **Write `.agents/state.yml`** using the schema in this task's Interfaces block, and add `.agents/last-run.log` to the project's `.gitignore`.
6. **Self-verify** with the eight checks from step 5 of `agents-md-architect`, plus: the file is ≤ 100 lines, every command in it exists, and `.agents/state.yml` parses as YAML.

State explicitly in the body that phases 3–4 (sensors, contract, hook) land in Task 5 and that `build` must say so when a user asks for the full harness before then.

- [ ] **Step 5: Run the test to verify it passes**

```bash
./tests/run.sh
```

Expected: PASS.

- [ ] **Step 6: Verify on a real repository**

```bash
rm -rf /tmp/keel-build && git clone --depth 1 https://github.com/sindresorhus/type-fest /tmp/keel-build
cd /tmp/keel-build && rm -f AGENTS.md
claude --plugin-dir <abs-path>/plugins/keel-harness \
  -p "Set up this repository for AI coding agents. Install what you recommend without asking me."
wc -l AGENTS.md && cat .agents/state.yml
grep -oE '`[^`]+`' AGENTS.md | tr -d '`' | sort -u   # inspect every cited command
```

Expected: `AGENTS.md` is ≤ 100 lines; `.agents/state.yml` shows `layers.bootstrap: installed` and `layers.guides: installed`; every command listed by the last line actually exists in that repository — check each one by hand. A single invented command fails this task.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat(build): install bootstrap and guide layers with a single confirmation gate"
```

---

### Task 5: `build` phases 3–4 — sensors, output contract and the gate hook (TypeScript)

Implements spec phase 5 (spec §6, §7, §9, §10).

**Files:**
- Create: `plugins/keel-harness/skills/build/references/sensor-contract.md`
- Create: `plugins/keel-harness/skills/build/references/sensors-by-language.md`
- Modify: `plugins/keel-harness/skills/build/SKILL.md`
- Modify: `tests/build_test.sh`

**Interfaces:**
- Consumes: `.agents/state.yml` from Task 4.
- Produces the wrapper protocol that Task 6's graders and Task 7's `doctor` both rely on. Every `scripts/sensors/<id>.sh` written into a user repo:
  - reads the environment variable `SCOPE`, a newline-separated list of changed files (empty means the whole repo);
  - writes **line 1** to stdout as four tab-separated fields: `<id>\t<class>\t<status>\t<summary>`, where `class` is `security|correctness|heuristic` and `status` is `pass|fail|skip`;
  - writes detail lines indented by two spaces, and on `fail` a block starting `guidance: ` saying what to do, in the user's repository terms;
  - exits `0` on pass, `1` on fail, `2` on skip (the tool is not installed — never a silent pass).
- Produces `scripts/gate.sh`, which runs every sensor listed in `.agents/state.yml`, times each one in milliseconds, renders the human report shown in spec §6, truncates stdout at 40 lines, writes the full output to `.agents/last-run.log`, and exits non-zero if any sensor failed.
- Produces the `PostToolUse` hook block written into the target repo's `.claude/settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "cd \"${CLAUDE_PROJECT_DIR}\" && make gate-fast"
          }
        ]
      }
    ]
  }
}
```

  Merge into an existing `settings.json` rather than overwriting it, and show the user the exact block before writing it.

- [ ] **Step 1: Extend the failing test**

Append to `tests/build_test.sh`, before the final `exit`:

```bash
[ -f "$sk/references/sensor-contract.md" ]; check "sensor-contract.md exists" $?
for field in "pass signal" "guidance" "scope" "class" "cost" "ceiling" "verbosity"; do
  grep -qi "$field" "$sk/references/sensor-contract.md" 2>/dev/null
  check "contract field: $field" $?
done
for cls in security correctness heuristic; do
  grep -q "$cls" "$sk/references/sensor-contract.md" 2>/dev/null; check "contract class: $cls" $?
done
grep -qi "never" "$sk/references/sensor-contract.md" 2>/dev/null; check "contract forbids ratcheting security" $?
grep -q "review_by" "$sk/references/sensor-contract.md" 2>/dev/null; check "heuristic snapshots expire" $?

[ -f "$sk/references/sensors-by-language.md" ]; check "sensors-by-language.md exists" $?
grep -q "GitLeaks" "$sk/references/sensors-by-language.md" 2>/dev/null; check "secret scanner named" $?
grep -qi "names tools, never commands" "$sk/references/sensors-by-language.md" 2>/dev/null
check "language table states the tools-not-commands rule" $?

grep -q "PostToolUse" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md writes the PostToolUse hook" $?
! grep -q "PreToolUse" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md installs no blocking hook" $?
grep -q "gate-fast" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md writes the gate-fast target" $?
grep -q "ceiling_seconds" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md honours the gate ceiling" $?
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bash tests/build_test.sh
```

Expected: the Task 4 checks still pass; every new check fails.

- [ ] **Step 3: Write `references/sensor-contract.md`**

Document the seven fields from spec §6 — pass signal, guidance, scope, cost, bounded verbosity, class, ceiling — then the class table (security and correctness never ratchet and never take a raisable threshold; heuristic does both). Include the wrapper protocol from this task's Interfaces block verbatim, with a complete worked example of a passing and a failing wrapper. State the ratchet expiry rule: every heuristic sensor records its install-day snapshot and a `review_by` date six months out.

- [ ] **Step 4: Write `references/sensors-by-language.md`**

Copy the six-language table from spec §7, keeping the rule "the table names tools, never commands — the exact command comes from discovery". Carry over the content of `agents-md-architect/references/harness-cheatsheet.md` as the per-ecosystem notes. Include both consequences from spec §7: Terraform has three fast sensors, not four; a Java compile that blows the ceiling is left out of the fast gate, which is the ceiling rule working.

In this task only the TypeScript row needs to be actionable end to end. The other five rows are documentation until the second plan implements them — say so in the file.

- [ ] **Step 5: Extend the `build` body with phases 3–4**

Add to the body:

7. **Phase 3 — fast-gate sensors.** From `sensors-by-language.md`, propose the sensors whose tools the repository actually has. Measure each one by running it once and record the seconds. A sensor that alone blows `gate.fast.ceiling_seconds` is **not installed**; say which one and why. Write `scripts/sensors/<id>.sh` for each accepted sensor, following the wrapper protocol in `sensor-contract.md`, plus `scripts/gate.sh` and the `gate-fast` target in the `Makefile`.
8. **Phase 4 — the output contract.** Every wrapper emits the seven fields. A failing sensor must produce `guidance:` phrased in the repository's own terms — which file, which decision, what to do next — never a restatement of the tool's error.
9. **The hook.** Show the exact JSON block from this task's Interfaces, explain that `PostToolUse` fires after the tool already ran and therefore blocks nothing, and write it into `.claude/settings.json` only after the user accepts. Merge; never overwrite.
10. **Record in state.** Append each installed sensor to `sensors:` in `.agents/state.yml` with its `id`, `class`, and for heuristics a `snapshot` and a `review_by` six months out. Security sensors get no snapshot.

- [ ] **Step 6: Run the test to verify it passes**

```bash
./tests/run.sh
```

Expected: PASS.

- [ ] **Step 7: The self-correction test — the one that decides this task**

```bash
rm -rf /tmp/keel-gate && mkdir /tmp/keel-gate && cd /tmp/keel-gate
# Reuse the scaffold from Task 3 to get a real TypeScript repo:
bash <abs-path>/plugins/keel-harness/evals/assess-mature-repo/scaffold.sh
npm install
claude --plugin-dir <abs-path>/plugins/keel-harness \
  -p "Set up the full harness here, including sensors and the gate. Install everything you recommend without asking me."
# Plant a behaviour change that breaks the test:
sed -i 's/cents \* 0.98/cents * 0.965/' src/posting.ts
make gate-fast; echo "gate exit=$?"
claude --plugin-dir <abs-path>/plugins/keel-harness -p "Run make gate-fast and fix what it reports."
npx vitest run
```

Expected: `make gate-fast` exits non-zero, prints the failing sensor with its class and a `guidance:` block, and the second Claude invocation fixes the defect **guided only by the sensor message**, with no extra human hint. If it needs help, the guidance text is the thing to fix — not the test.

- [ ] **Step 8: Verify portability and the no-block rule**

```bash
cd /tmp/keel-gate
claude -p "run make gate-fast"      # no --plugin-dir: the plugin is not loaded
grep -c "PreToolUse" .claude/settings.json   # expect 0
```

Expected: the gate runs identically with the plugin absent (spec §2, portability test), and no blocking hook was installed.

- [ ] **Step 9: Retire `agents-md-architect` as a standalone skill**

Everything it carried is now absorbed (spec §4): steps 1–2 into `assess`, steps 3–4 into `build`, step 5 into `doctor` (Task 7), and its references into both skills. Two skills competing for "configure my repo for agents" is the failure mode the study names.

In the `aether-labs-org/skills` checkout, delete `skills/agents-md-architect/`. It is untracked and was never published, so nothing to deprecate and no user to migrate. Confirm before deleting:

```bash
cd ../skills && git status --porcelain skills/agents-md-architect | head
ls skills/agents-md-architect/references/    # every file here must already exist under the plugin
```

Expected: `git status` shows the directory as untracked (`??`), and every reference file listed is accounted for — `harness-model.md` and `context-engineering.md` copied verbatim, `agents-md-template.md` copied with the 100-line ceiling, `harness-cheatsheet.md` absorbed into `sensors-by-language.md`, `multi-agent-orchestration.md` intentionally dropped, `evals/evals.json` used as source material only. Only then remove the directory.

- [ ] **Step 10: Commit**

```bash
git add -A && git commit -m "feat(build): add sensor contract, TypeScript fast gate and PostToolUse hook"
```

---

### Task 6: Eval cases for `build` and the gate

Implements the validation half of spec phase 5 (spec §8).

**Files:**
- Create: `plugins/keel-harness/evals/build-typescript/{case.yaml,prompt.md,scaffold.sh}`
- Create: `plugins/keel-harness/evals/build-typescript/graders/{agents-md-exists,agents-md-size,makefile-targets,state-yml,skill-fired}.md`
- Create: `plugins/keel-harness/evals/gate-catches-defect/{case.yaml,prompt.md,scaffold.sh}`
- Create: `plugins/keel-harness/evals/gate-catches-defect/fixtures/harness/` (Makefile, scripts/, .agents/ from the Task 5 run)
- Create: `plugins/keel-harness/evals/gate-catches-defect/graders/{gate-failed,gate-guidance,ran-gate}.md`
- Modify: `plugins/keel-harness/README.md` (the eval baseline table)

**Interfaces:**
- Consumes: the wrapper protocol and `Makefile` targets from Task 5, and the state schema from Task 4.
- Produces: the Δ numbers recorded in the README baseline table.

- [ ] **Step 1: Install the host prerequisites**

```bash
command -v socat || sudo apt-get install -y socat     # Bash-granting eval runs are refused without it
command -v gitleaks || echo "install gitleaks: https://github.com/gitleaks/gitleaks/releases"
command -v bwrap    # already present
```

Granting `Bash` puts every command under Claude Code's OS sandbox, and on Linux that backend needs `bubblewrap` **and** `socat`. Without them each run is refused and the case scores 0 for the wrong reason.

- [ ] **Step 2: Write the `build-typescript` case**

`scaffold.sh`: the Task 3 scaffold, plus `npm install` so the toolchain exists offline inside the sandbox, plus a planted secret in `src/config.ts` (`const STRIPE_KEY = "sk_live_" + "51H8xExampleNotReal000000000000000";`) so the secret sensor has something to find.

`case.yaml`:

```yaml
schema_version: "1.1"
name: build-typescript
description: Installs the full harness in a TypeScript repo without asking, as the prompt waives the gate.
tags: [build, typescript]
context:
  scaffold_script: scaffold.sh
```

`prompt.md` — the confirmation gate is waived **by the user's own sentence**, never by a flag in the skill:

```markdown
---
max_turns: 60
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, TodoWrite]
---

Set up the harness in this repository and install everything you recommend, without asking me
to confirm anything. When you are done, write the number of lines in AGENTS.md to linecount.txt.
```

Graders, one per file:

`graders/agents-md-exists.md`

```markdown
---
type: file_exists
path: "AGENTS.md"
---
```

`graders/agents-md-size.md` — 0–100 lines and nothing above it

```markdown
---
type: regex
pattern: '^\s*(?:[0-9]{1,2}|100)\s'
target: { source: file, path: linecount.txt }
weight: 2
---
```

`graders/makefile-targets.md`

```markdown
---
type: regex
pattern: '(?m)^gate-fast:[\s\S]*'
target: { source: file, path: Makefile }
weight: 2
---
```

`graders/state-yml.md`

```markdown
---
type: regex
pattern: 'model_baseline:[\s\S]*layers:[\s\S]*(bootstrap|guides)'
target: { source: file, path: .agents/state.yml }
weight: 2
---
```

`graders/skill-fired.md` — indicator only

```markdown
---
type: tool_used
tool: Skill
input_match: '"skill"\s*:\s*"(?:[\w-]+:)?build"'
---
```

- [ ] **Step 3: Write the `gate-catches-defect` case**

A scaffold cannot run the interactive `build` skill, so this case ships the harness as a committed fixture. Create it once from the harness Task 5 step 7 produced in `/tmp/keel-gate`:

```bash
cd plugins/keel-harness/evals/gate-catches-defect
mkdir -p fixtures/harness
cp -r /tmp/keel-gate/Makefile /tmp/keel-gate/scripts /tmp/keel-gate/.agents fixtures/harness/
rm -f fixtures/harness/.agents/last-run.log
```

`scaffold.sh` then runs the `build-typescript` scaffold, copies `fixtures/harness/` over the workspace, runs `npm install`, and plants the rounding change from Task 5 step 7 (`sed -i 's/cents \* 0.98/cents * 0.965/' src/posting.ts`) so exactly one sensor must fail.

`prompt.md`:

```markdown
---
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep]
---

Run `make gate-fast` and write its complete output to gate-output.txt. Do not fix anything.
```

Graders, one per file:

`graders/gate-failed.md`

```markdown
---
type: regex
pattern: '(✗|FAILED)'
target: { source: file, path: gate-output.txt }
weight: 2
---
```

`graders/gate-guidance.md`

```markdown
---
type: regex
pattern: 'guidance:'
target: { source: file, path: gate-output.txt }
weight: 2
---
```

`graders/ran-gate.md`

```markdown
---
type: tool_used
tool: Bash
input_match: 'make\s+gate-fast'
---
```

- [ ] **Step 4: Run the two new cases with Bash granted**

```bash
cd plugins/keel-harness
claude plugin eval . --scaffold --ablation none --runs 1 \
  --case 'build-typescript' --case 'gate-catches-defect' \
  --allow-tools Write Edit Bash
```

Expected: both cases complete with no `not granted` lines on stderr and no run errors. If a run reports the sandbox is unavailable, go back to step 1.

- [ ] **Step 5: Run the whole suite in two arms**

```bash
claude plugin eval . --scaffold --allow-tools Write Edit Bash
```

Expected: four cases reported. `build-typescript` and `gate-catches-defect` show clearly positive Δ — a model with no plugin does not produce a `Makefile` with a `gate-fast` target or a `.agents/state.yml`.

- [ ] **Step 6: Apply the existence floor**

Any case with Δ ≤ 0 across three consecutive runs is rewritten or deleted (spec §8). Record the verdict per case in the README baseline table, with the date and the Claude Code version.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "test(evals): add build-typescript and gate-catches-defect cases"
```

---

### Task 7: `doctor`

Implements spec phase 7 (spec §4, §10).

**Files:**
- Modify: `plugins/keel-harness/skills/doctor/SKILL.md`
- Create: `tests/doctor_test.sh`
- Create: `plugins/keel-harness/evals/doctor-finds-drift/{case.yaml,prompt.md,scaffold.sh}`
- Create: `plugins/keel-harness/evals/doctor-finds-drift/graders/{names-the-drift,writes-nothing}.md`

**Interfaces:**
- Consumes: `.agents/state.yml` (Task 4), the `Makefile` and wrapper protocol (Task 5).
- Produces: nothing at runtime — `doctor` reports and proposes, and every fix goes back through `build`.

- [ ] **Step 1: Write the failing test**

Create `tests/doctor_test.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
fail=0
check() { if [ "$2" -eq 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fail=1; fi; }
root="$(cd "$(dirname "$0")/.." && pwd)"
f="$root/plugins/keel-harness/skills/doctor/SKILL.md"

grep -q "100 lines" "$f" 2>/dev/null; check "check 1: AGENTS.md size" $?
grep -qi "no longer exist" "$f" 2>/dev/null; check "check 2: stale command" $?
grep -qi "not installed\|fails to run" "$f" 2>/dev/null; check "check 3: missing sensor tool" $?
grep -q "model_baseline" "$f" 2>/dev/null; check "check 4: stale model baseline" $?
grep -qi "writes nothing" "$f" 2>/dev/null; check "doctor writes nothing" $?
grep -qi "exactly one warning" "$f" 2>/dev/null; check "one condition produces one warning" $?
# v0.2 checks must not sneak in: they need history that does not exist yet.
! grep -qi "capture rate" "$f" 2>/dev/null; check "no history-dependent checks" $?

exit $fail
```

- [ ] **Step 2: Run it to verify it fails**

```bash
chmod +x tests/doctor_test.sh && bash tests/doctor_test.sh
```

Expected: FAIL on every check.

- [ ] **Step 3: Write the `doctor` body**

Keep the Task 1 frontmatter. Four checks, and only four — each reads the current repository in a single look, with no history:

1. `AGENTS.md` is over 100 lines.
2. A command cited in `AGENTS.md` no longer exists in the project (resolve each cited command against `package.json` scripts, `Makefile` targets and `$PATH`).
3. A sensor declared in the `Makefile` or in `.agents/state.yml` whose tool is missing or exits 2 (`skip`) when run.
4. `model_baseline` in `.agents/state.yml` is behind the model running the session by one version or more.

State the output rule: **one broken condition produces exactly one warning** — not zero, not two. Each warning names the file, what is wrong, and the `build` step that fixes it. `doctor` writes nothing; it proposes and stops.

Add a closing note that capture rate per sensor and document-versus-code freshness are v0.2 checks, because they need accumulated history.

- [ ] **Step 4: Run the test to verify it passes**

```bash
./tests/run.sh
```

Expected: PASS.

- [ ] **Step 5: The one-warning-per-condition verification**

Start from the harness produced in Task 5 step 7, then break each condition on its own, running `doctor` after each and restoring before the next:

```bash
cd /tmp/keel-gate
# 1. oversize AGENTS.md
cp AGENTS.md /tmp/agents.bak && yes "- filler pointer line" | head -120 >> AGENTS.md
claude --plugin-dir <abs-path>/plugins/keel-harness -p "Is my harness still valid?" | tee /tmp/d1.txt
cp /tmp/agents.bak AGENTS.md
# 2. stale command
sed -i 's/npm run build/npm run compile/' AGENTS.md
claude --plugin-dir <abs-path>/plugins/keel-harness -p "Is my harness still valid?" | tee /tmp/d2.txt
git checkout AGENTS.md
# 3. missing sensor tool
mv node_modules/.bin/tsc node_modules/.bin/tsc.off
claude --plugin-dir <abs-path>/plugins/keel-harness -p "Is my harness still valid?" | tee /tmp/d3.txt
mv node_modules/.bin/tsc.off node_modules/.bin/tsc
# 4. stale baseline
sed -i 's/^model_baseline: .*/model_baseline: claude-3-opus/' .agents/state.yml
claude --plugin-dir <abs-path>/plugins/keel-harness -p "Is my harness still valid?" | tee /tmp/d4.txt
```

Expected: each of `/tmp/d1.txt` … `/tmp/d4.txt` reports **exactly one** warning, and it is the right one. Two warnings for one break means a check is over-eager; zero means it is not looking.

- [ ] **Step 6: Add the `doctor-finds-drift` eval case**

`scaffold.sh`: copy the same `fixtures/harness/` used by `gate-catches-defect`, then append 120 filler lines to `AGENTS.md` so exactly one condition is broken.

`prompt.md`:

```markdown
---
max_turns: 20
allowed_tools: [Read, Glob, Grep, Skill]
---

Is the agent harness in this repository still up to date?
```

`graders/names-the-drift.md`:

```markdown
---
type: regex
pattern: 'AGENTS\.md[\s\S]{0,200}(100|too long|over the)'
target: last_message
weight: 2
---
```

`graders/writes-nothing.md`:

```markdown
---
type: file_exists
path: "**/*"
exists: false
---
```

- [ ] **Step 7: Run the full suite and update the baseline**

```bash
cd plugins/keel-harness && claude plugin eval . --scaffold --allow-tools Write Edit Bash
```

Expected: five cases. Update the README baseline table with WITH / W-OUT / Δ per case, the date and the Claude Code version.

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "feat(doctor): add the four history-free drift checks"
```

---

## After this plan

1. `claude plugin validate ./plugins/keel-harness --strict` with zero warnings, and `./tests/run.sh` green.
2. Write the second plan: spec phase 6 (Python, Go, Java, Next.js, Terraform — one task per language, each with a scaffold, a `build-<lang>` case and the five planted defects from spec §7) and spec phase 8 (release).
3. Only then create `aether-labs-org/plugins` on GitHub and push — with the owner's explicit confirmation, as stated in the Global Constraints.
