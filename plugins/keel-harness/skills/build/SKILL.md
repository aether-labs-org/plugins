---
name: build
description: >
  Installs an AI-agent harness in a repository: one-command bootstrap, an AGENTS.md index of
  at most 100 lines with pointer files, a fast gate of computational sensors (types, lint,
  affected tests, secret scanning) behind a single Makefile target, sensor wrappers that emit
  pass signal, guidance, scope, class and cost, and the Stop hook that hands gate guidance to Claude.
  Infers from the repository and confirms before writing; installs one layer at a time and is
  resumable. Use when someone asks to set up or build a harness, configure their repository
  for AI agents, add agent guardrails or quality gates, or make a repo agent-friendly.
---

# Build

Asks in rounds and writes nothing before the user confirms. Everything deterministic is a tested
file under `${CLAUDE_SKILL_DIR}/assets/`: you **copy** it and edit only the discovered,
repository-specific parts. You never regenerate a script from prose.

**Stacks with bundled sensors**, under `${CLAUDE_SKILL_DIR}/assets/sensors/`:

| Stack | Sensors |
| --- | --- |
| TypeScript / Node, React | `sensors/typescript/` (React: discovery sets `LINT_PATHS` and the framework lint config) |
| Python | `sensors/python/` |
| Java / Kotlin | `sensors/jvm/` |

Every stack also gets `sensors/common/secrets.sh`. For Go, Terraform and anything else in
`references/sensors-by-language.md`, propose what that file documents, say plainly that the wrappers
are not bundled, and install only the layers that are. Each phase installs independently and is
resumable.

## 1. Read the picture

If `assess` already ran in this session, reuse its report table (axis states, evidence, costs). If
not, do the same read-only discovery before proposing anything:

```bash
cat package.json 2>/dev/null | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('scripts',{}))" 2>/dev/null
grep -E "^[a-zA-Z_-]+:" Makefile 2>/dev/null | head -30
ls mvnw gradlew pnpm-lock.yaml yarn.lock package-lock.json uv.lock poetry.lock 2>/dev/null
find docs/ -maxdepth 2 -name "*.md" 2>/dev/null | sort; ls src/ lib/ app/ packages/ services/ 2>/dev/null
ls .eslintrc* eslint.config* tsconfig.json ruff.toml mypy.ini .pre-commit-config.yaml .github/workflows/ 2>/dev/null
ls AGENTS.md CLAUDE.md .claude/CLAUDE.md .agents/state.yml 2>/dev/null
```

**Never invent a command.** Every command in the proposal, in `AGENTS.md` or in a sensor must be one
you found in discovery. If `.agents/state.yml` exists, read it first: a layer marked `installed` is
not re-proposed; one marked `not_installed` may be retried if new evidence appeared.

## 2. Ask in rounds

Use `AskUserQuestion` when it is available, with at most 4 questions per round, the recommended
option first, and each option stating its trade-off. When it is not available (non-interactive
runs), ask in plain text; if the user's own request pre-authorised proceeding, take the recommended
option of each question and say so. Group the questions by layer (bootstrap, guides, gate, hook),
one round per group, and apply the three-confidence rule to each layer:

- **High**: one unambiguous path. State the inference and ask for acceptance.
- **Low**: more than one plausible path. Ask a narrow question listing the options seen.
- **None**: nothing can be inferred. Say so, give your recommendation with its reason, and ask.
  Never install a layer on a guess; record what was declined under `not_installed`.

## 3. Phase 1 - bootstrap

The entry point is always **`make bootstrap`**: wrap the discovered install and build commands,
never cite a script bare. If there is no `Makefile`, propose one with just that target; if there is
one, add the target without touching the others. Show the exact target body (e.g. `bootstrap:` then
a tab and `npm install`).

If the stack has no build step, the target only installs; say so rather than inventing a build line.

## 4. Phase 2 - guides

Fill `references/agents-md-template.md` with real, confirmed values only. Any topic that needs more
than one sentence becomes a `→ docs/X.md` pointer. Omit sections with nothing found. Read
`references/context-engineering.md` first. The rendered file is **100 lines** or fewer. Create no
TODO stubs: project rules and `docs/architecture.md`, `docs/conventions.md`, `docs/testing.md` come
from `/keel-harness:rules`, which this skill offers at the end.

**Claude Code reads `AGENTS.md` only when no `CLAUDE.md` or `.claude/CLAUDE.md` exists.** So when
neither exists, create `CLAUDE.md` containing exactly `@AGENTS.md`. When one exists without that
line, propose inserting `@AGENTS.md` as its first line, as its own question.

## 5. Phase 3 - the gates

Read `references/sensors-by-language.md` and `references/sensor-contract.md` first. Propose only
the sensors whose tool the repository has; a missing tool is either left out or installed as an
honest `skip`.

**Copy map** (source under `${CLAUDE_SKILL_DIR}/assets/`, destination in the repository):

| Source | Destination |
| --- | --- |
| `gate.sh` | `scripts/gate.sh` |
| `gate.env` | `.agents/gate.env` |
| `lib/baseline.sh` (all stacks), `lib/junit.sh` (Java/Kotlin) | `scripts/lib/` |
| `sensors/<stack>/<id>.sh`, `sensors/common/secrets.sh` (JVM: `compile.sh` -> `scripts/sensors/compile.sh`) | `scripts/sensors/<id>.sh` |

The first command of the copy is `cp "${CLAUDE_SKILL_DIR}/assets/gate.sh" scripts/gate.sh`, then
`chmod +x`. For each sensor, edit **only** the block between `# --- keel:repo-specific begin ---`
and `# --- keel:repo-specific end ---` (tool path, arguments, paths, guidance text), using what
discovery found. Never touch the managed-by header or the line-1 contract.

**Measure the cost before installing**: run each candidate once and record the wall seconds
(`time node_modules/.bin/tsc --noEmit -p tsconfig.json`). The budget is `CEILING_SECONDS` in
`.agents/gate.env` (default 30; `SLOW_CEILING_SECONDS` default 600 for the slow gate). A sensor that
alone blows the fast budget is not installed (or moves to `scripts/sensors/slow/`): name it, its
seconds and the budget, in the proposal and under `not_installed`.

**Baselines.** A `heuristic` sensor that finds problems on day one gets a TSV baseline, written
with the sensor's own measurement and the user's approval:

```bash
KEEL_MEASURE=1 bash scripts/sensors/lint.sh > .agents/baselines/lint.tsv
```

`security` and `correctness` sensors never get one (see `references/sensor-contract.md`).

**Makefile targets**, added beside `bootstrap`:

```make
gate-fast:
	@bash scripts/gate.sh fast

gate-slow:
	@bash scripts/gate.sh slow

harness-check: ; @bash scripts/harness-check.sh
```

Also install the portable validator and the hand-editing guide:
`cp "${CLAUDE_SKILL_DIR}/assets/harness-check.sh" scripts/harness-check.sh` (`chmod +x`) and
`cp "${CLAUDE_SKILL_DIR}/assets/README.agents.md" .agents/README.md`.

Everything installed is plain `bash` that must run with this plugin absent: no `${CLAUDE_*}`
variable, no path into the plugin, no `claude` call, no network. Verify by running `make gate-fast`
and reading it.

## 6. The output contract

Every sensor emits the seven fields of `references/sensor-contract.md` section 1; the copied assets
already do. When editing the repo-specific block keep: `guidance` on `fail` only, in this
repository's terms and naming the wrong fix ("never edit the test to match"); `class` deciding
baselines (`security` and `correctness` never get a TSV baseline); and the detail cap.

## 7. The Stop hook

Claude only sees a gate failure when a hook hands it back, and `PostToolUse` output never reaches
Claude. So the gate is wired to Claude Code's **`Stop`** hook, which gives the fast gate's guidance
back before Claude finishes. It blocks no action: the adapter always exits 0 and the conversation
continues only while the gate fails, up to its loop guard.

1. Copy `${CLAUDE_SKILL_DIR}/assets/hooks/claude-stop.sh` to `scripts/hooks/claude-stop.sh`
   (`chmod +x`).
2. Show the user the block in `${CLAUDE_SKILL_DIR}/assets/hooks/settings-stop.json` and, once they
   accept, **merge** it into `.claude/settings.json`: read the file, append the `Stop` entry to the
   existing `hooks` object (or array), keep every other key unchanged; create the file with exactly
   that block if it does not exist.

```json
{ "hooks": { "Stop": [ { "hooks": [ {
  "type": "command",
  "command": "\"${CLAUDE_PROJECT_DIR}\"/scripts/hooks/claude-stop.sh",
  "timeout": 120
} ] } ] } }
```

**`${CLAUDE_PROJECT_DIR}` is copied literally**, backslash-escaped quotes included. It is a variable
Claude Code sets when it runs the hook; never replace it with this repository's absolute path. The
hook is the item most worth declining on its own, so it is a separate line in the proposal.

Add these to `.gitignore` (fresh installs and upgrades alike): `.agents/last-run.log`,
`.agents/last-run-slow.log`, `.agents/last-green`, `.agents/last-seen`, `.agents/last-fail`, `.agents/.gate-lock/`,
`.agents/plans/`. Propose ignoring the tools' caches too when they are not (`.mypy_cache/`,
`.pytest_cache/`, `.ruff_cache/`, `.gradle/`, `build/`, `coverage/`): untracked, they enter `SCOPE`.

## 7b. Upgrading a v0.1 install

A repository whose `.agents/state.yml` lacks `schema_version: 2`, or whose `.claude/settings.json`
has a `PostToolUse` entry running `make gate-fast`, gets one round that proposes, each item
accept-or-drop:

1. The Stop hook of section 7 replaces the v0.1 PostToolUse entry (remove that entry, keep other keys).
2. The sensor list in the old state is dropped: each entry already has its file; the gate
   discovers files now.
3. A v0.1 `snapshot` entry becomes a TSV baseline, re-measured with `KEEL_MEASURE=1`, never copied.
4. The v0.1 model-baseline key is replaced by `harness_review_by` (today + 6 months); state becomes section 9.
5. The `.gitignore` entries above are added.

## 8. Propose, then write

After the rounds, show one structured proposal covering every file to be created or changed, so the
user can accept, drop or amend items in one pass:

```
Proposed for this repository:
BOOTSTRAP  make bootstrap -> {{real install command}}  (or: none could be inferred)
GUIDES     AGENTS.md ({{N}} lines) - preview below; docs/ stubs: {{list or none}}
GATES      fast (budget {{N}}s): typecheck [correctness], lint [heuristic, baseline {{N}} files],
           tests [correctness], secrets [security]; left out: {{sensor}} - measured {{N}}s
           scripts/gate.sh, .agents/gate.env, make gate-fast, make gate-slow
HOOK       scripts/hooks/claude-stop.sh + a Stop entry in .claude/settings.json (fast gate, timeout 120)
```

**Write nothing before the user accepts.** This rule has no exception. The user's own request can
grant that acceptance up front ("do not pause for confirmation") for every high- or low-confidence
layer in the proposal: present it and proceed in the same reply. A `none`-confidence layer stays
uninstalled regardless. In short: before writing anything, wait for the answer.

## 9. Write `.agents/state.yml`

State is **metadata only**; it does not configure the gate (budgets are in `.agents/gate.env`,
sensors are the files in `scripts/sensors/`).

```yaml
schema_version: 2
installed_at: 2026-10-20          # ISO date, today
harness_review_by: 2027-04-20     # installed_at + 6 months
mode: brownfield                  # greenfield | brownfield, confirmed by the user
layers: { bootstrap: installed, guides: installed, fast_gate: installed, slow_gate: not_installed, hook: installed, rules: not_installed }
not_installed:                    # layer or sensor -> the reason, in keel's words
  slow_gate: "no mutation or coverage tool configured"
```

Use the real reason for each `not_installed` entry; never a generic one. Ignore the generated files (section 7); `.agents/state.yml`, `.agents/gate.env` and `.agents/baselines/` are committed.

## 10. Self-verify

Check what the copied assets do not already guarantee:

- [ ] `AGENTS.md` is 100 lines or fewer; deep content is `→ docs/X.md` pointers; no `{{...}}` left.
- [ ] Every command cited in `AGENTS.md` really exists and runs here (re-check by hand).
- [ ] `Last updated: YYYY-MM-DD` is set; nothing was written before the user confirmed.
- [ ] `.agents/state.yml` parses as YAML and has `schema_version: 2`.
- [ ] `make gate-fast` was actually run and its output read; its verdict line reads
      `gate: fast - ...` and each sensor's `cut -f1` is its own id.
- [ ] `make harness-check` was run and prints `harness is clean`.
- [ ] Each `heuristic` sensor with a baseline has `.agents/baselines/<id>.tsv` from `KEEL_MEASURE=1`.
- [ ] A sensor that blew the budget is named, with its seconds, under `not_installed`.
- [ ] `scripts/` has no `${CLAUDE_*}`, plugin path or `claude` call.
- [ ] `.claude/settings.json` parses as JSON and kept every key it had; the `Stop` entry is
      present; there is no PostToolUse gate entry; `scripts/hooks/claude-stop.sh` is executable.
- [ ] The hook `command` contains the literal `${CLAUDE_PROJECT_DIR}`
      (`grep -q '\${CLAUDE_PROJECT_DIR}' .claude/settings.json`).

When it is all green, offer the next step: `/keel-harness:rules` to propose the project's own rules (architecture, testing strategy, conventions).

If a check fails, fix it and re-verify before reporting the layer installed. Each phase is
**resumable**: a layer already `installed` is not re-proposed on a later run.
