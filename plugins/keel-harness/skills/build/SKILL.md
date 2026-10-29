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
file under `${CLAUDE_PLUGIN_ROOT}/assets/core/`: you **copy** it and edit only the discovered,
repository-specific parts. You never regenerate a script from prose.

**Stacks with bundled sensors**, under `${CLAUDE_PLUGIN_ROOT}/assets/core/sensors/`:

| Stack | Sensors |
| --- | --- |
| TypeScript / Node, React | `sensors/typescript/` (React: discovery sets `LINT_PATHS` and the framework lint config) |
| Python | `sensors/python/` |
| Java / Kotlin | `sensors/jvm/` |

Every stack also gets `sensors/common/secrets.sh` and `sensors/common/guard.sh`. For Go, Terraform and anything else in
`references/sensors-by-language.md`, propose what that file documents, say plainly that the wrappers
are not bundled, and install only the layers that are. Each phase installs independently and is resumable.

## 0. Precondition

The order of this skill is enforced by `${CLAUDE_PLUGIN_ROOT}/scripts/keel` (`${CLAUDE_PLUGIN_ROOT}/contracts/flow.md`).
Start with `${CLAUDE_PLUGIN_ROOT}/scripts/keel check pre build` from the repository root. When it exits
non-zero, show its `missing:` lines and stop.

## Phases

### Read the picture

If `assess` already ran in this session, reuse its report table (axis states, evidence, costs). If
not, run the read-only discovery commands in `references/discovery.md` before proposing anything.
**Never invent a command.** Every command in the proposal, in `AGENTS.md` or in a sensor must be one
you found in discovery. If `.agents/state.yml` exists, read it first: a layer marked `installed` is not
re-proposed; one marked `not_installed` may be retried if new evidence appeared.

### Ask in rounds

Use `AskUserQuestion` when it is available, with at most 4 questions per round, the recommended
option first, and each option stating its trade-off. When it is not available (non-interactive
runs), ask in plain text; if the user's own request pre-authorised proceeding, take the recommended
option of each question and say so. Group the questions by layer (bootstrap, guides, gate, hook),
one round per group, and apply the three-confidence rule to each layer:

- **High**: one unambiguous path. State the inference and ask for acceptance.
- **Low**: more than one plausible path. Ask a narrow question listing the options seen.
- **None**: nothing can be inferred. Say so, give your recommendation with its reason, and ask.
  Never install a layer on a guess; record what was declined under `not_installed`.

### Phase 1 - bootstrap

The entry point is always **`make bootstrap`**: wrap the discovered install and build commands,
never cite a script bare. If there is no `Makefile`, propose one with just that target; if there is
one, add the target without touching the others. Show the exact target body (e.g. `bootstrap:` then
a tab and `npm install`).

If the stack has no build step, the target only installs; say so rather than inventing a build line.

### Phase 2 - guides

Fill `references/agents-md-template.md` with real, confirmed values only. Any topic that needs more
than one sentence becomes a `→ docs/X.md` pointer. Omit sections with nothing found. Read
`references/context-engineering.md` first. The rendered file is **100 lines** or fewer. Create no
TODO stubs: project rules and `docs/architecture.md`, `docs/conventions.md`, `docs/testing.md` come
from `/keel-harness:rules`, which this skill offers at the end. Also create `.agents/progress.md` (a heading and one line on what it holds, per `contracts/plan.md`): the template points at it.
Propose the stack's official LSP plugin from the table in `references/context-engineering.md` as its own accept-or-decline item (a name only from that table); record a decline as `lsp` under `not_installed`.

**Claude Code reads `AGENTS.md` only when no `CLAUDE.md` or `.claude/CLAUDE.md` exists.** So when
neither exists, create `CLAUDE.md` containing exactly `@AGENTS.md`. When one exists without that
line, propose inserting `@AGENTS.md` as its first line, as its own question.

### Phase 3 - the gates

Read `references/sensors-by-language.md` and `${CLAUDE_PLUGIN_ROOT}/contracts/sensor.md` first. Propose only
the sensors whose tool the repository has; a missing tool is either left out or installed as an
honest `skip`.

**Copy map** (source under `${CLAUDE_PLUGIN_ROOT}/assets/core/`, destination in the repository):

| Source | Destination |
| --- | --- |
| `gate.sh` | `scripts/gate.sh` |
| `gate.env` | `.agents/gate.env` |
| `lib/baseline.sh`, `lib/envparse.sh` (all stacks), `lib/junit.sh` (Java/Kotlin) | `scripts/lib/` |
| `sensors/<stack>/<id>.sh`, `sensors/common/secrets.sh`, `sensors/common/guard.sh` (JVM: `compile.sh` -> `scripts/sensors/compile.sh`) | `scripts/sensors/<id>.sh` |

The first command of the copy is `cp "${CLAUDE_PLUGIN_ROOT}/assets/core/gate.sh" scripts/gate.sh`, then
`chmod +x`. For each sensor, edit **only** the block between `# --- keel:repo-specific begin ---`
and `# --- keel:repo-specific end ---` (tool path, arguments, paths, guidance text), using what
discovery found. Never touch the managed-by header or the line-1 contract.

**Measure the cost before installing**: run each candidate once and record the wall seconds
(`time node_modules/.bin/tsc --noEmit -p tsconfig.json`). The budget is `CEILING_SECONDS` in
`.agents/gate.env` (default 30; `SLOW_CEILING_SECONDS` default 600 for the slow gate). A sensor that
alone blows the fast budget is not installed (or moves to `scripts/sensors/slow/`): name it, its
seconds and the budget, in the proposal and under `not_installed`. Profile L (autonomous runs) has one optional slow sensor, `reviewer` (`${CLAUDE_PLUGIN_ROOT}/assets/core/sensors/slow/reviewer.sh`, experimental, D52): a second model reviews the diff through the user's own `REVIEWER_CMD`, so every `make gate-slow` costs a model call and tokens and sends the diff to that command. Propose it only when the user asks for it or for an autonomous setup, with that cost stated, and install it as a separate item with its `reviewer.env` (`${CLAUDE_PLUGIN_ROOT}/contracts/profile-l.md`).

**Baselines.** A `heuristic` sensor that finds problems on day one gets a TSV baseline, written
with the sensor's own measurement and the user's approval:

```bash
KEEL_MEASURE=1 bash scripts/sensors/lint.sh > .agents/baselines/lint.tsv
```

`security` and `correctness` sensors never get one (`contracts/sensor.md`).

**Makefile targets**, added beside `bootstrap`:

```make
gate-fast:
	@bash scripts/gate.sh fast
gate-slow:
	@bash scripts/gate.sh slow
harness-check: ; @bash scripts/harness-check.sh
```

Also install the portable validator and the hand-editing guide:
`cp "${CLAUDE_PLUGIN_ROOT}/assets/core/harness-check.sh" scripts/harness-check.sh` (`chmod +x`) and
`cp "${CLAUDE_PLUGIN_ROOT}/assets/core/README.agents.md" .agents/README.md`.

Everything installed is plain `bash` that must run with this plugin absent: no `${CLAUDE_*}`
variable, no path into the plugin, no `claude` call, no network. Run `make gate-fast` and read it.

### Phase 4 - the Stop hook

Claude only sees a gate failure when a hook hands it back. `PostToolUse` sends exit-0 stdout to the debug log and, on exit 2, only stderr, where `make` puts no report. So the gate is wired to Claude Code's **`Stop`** hook, which gives the fast gate's guidance
back before Claude finishes. It blocks no action: the adapter always exits 0 and the conversation
continues only while the gate fails, up to its loop guard.

1. Copy `${CLAUDE_PLUGIN_ROOT}/assets/adapters/claude/claude-stop.sh` to `scripts/hooks/claude-stop.sh`
   (`chmod +x`).
2. Show the user the block in `${CLAUDE_PLUGIN_ROOT}/assets/adapters/claude/settings-stop.json` (one `Stop`
   entry, `"timeout": 120`, command `"\"${CLAUDE_PROJECT_DIR}\"/scripts/hooks/claude-stop.sh"`) and, once they
   accept, **merge** it into `.claude/settings.json`: read the file, append the `Stop` entry to the
   existing `hooks` object (or array), keep every other key unchanged; create the file with exactly
   that block if it does not exist.

**`${CLAUDE_PROJECT_DIR}` is copied literally**, backslash-escaped quotes included. It is a variable
Claude Code sets when it runs the hook; never replace it with this repository's absolute path. The
hook is the item most worth declining on its own, so it is a separate line in the proposal.

Add `.agents/run/` (all run state: logs, fingerprints, lock) to `.gitignore`, fresh installs and
upgrades alike. `.agents/plans/` and `.agents/progress.md` are versioned, not ignored (D6). Propose ignoring the tools' caches too when they are not (`.mypy_cache/`,
`.pytest_cache/`, `.ruff_cache/`, `.gradle/`, `build/`, `coverage/`): untracked, they enter `SCOPE`.

### Phase 5 - enforcement (ci, precommit)

The Stop hook reaches only Claude Code. CI and pre-commit run the same `make gate-fast` for every author, and each is its own layer (`ci`, `precommit` in `.agents/state.yml`), accepted or declined on its own. Read `references/enforcement.md` before proposing: it has the CI workflow (`${CLAUDE_PLUGIN_ROOT}/assets/core/ci/keel.yml`, only its repo-specific block is edited) and the pre-commit merge for the hook manager the repository already uses.

### Phase 6 - authority (consequence map, protect hook, CODEOWNERS)

Gates return guidance; this layer decides what the agent may touch. Read `references/authority.md`: it installs `.agents/consequence.yml` (discovered, shown, confirmed), `scripts/hooks/claude-protect.sh` with its settings entry and the secrets deny rules, and proposes CODEOWNERS lines. Never invent an owner: ask who owns each path, and leave a line nobody answered out. The layer is `authority` in `.agents/state.yml`.

### Upgrading an earlier install

A `schema_version: 2` state (v0.2), a state without `schema_version`, or a `PostToolUse` entry running
`make gate-fast` (v0.1) gets one upgrade round, each item accept-or-drop. The items (including the
Stop hook that replaces the v0.1 PostToolUse entry) are in `references/upgrade.md`.

### Propose, then write

After the rounds, write one structured proposal covering every file to be created or changed, to a
temporary file (`mktemp`; under `.agents/run/tmp/` when that fails), and record it with `${CLAUDE_PLUGIN_ROOT}/scripts/keel plan build <file>`, which prints
`proposal build <hash>`; show the user the proposal so they can accept, drop or amend items in one pass:

```
Proposed for this repository:
BOOTSTRAP  make bootstrap -> {{real install command}}  (or: none could be inferred)
GUIDES     AGENTS.md ({{N}} lines) - preview below; docs/ stubs: {{list or none}}
GATES      fast (budget {{N}}s): typecheck [correctness], lint [heuristic, baseline {{N}} files],
           tests [correctness], secrets [security], guard [security]; left out: {{sensor}} - measured {{N}}s
           scripts/gate.sh, .agents/gate.env, make gate-fast, make gate-slow
HOOK       scripts/hooks/claude-stop.sh + a Stop entry in .claude/settings.json (fast gate, timeout 120)
ENFORCE    ci: .github/workflows/keel.yml; precommit: {{lefthook | pre-commit | husky | none}} (references/enforcement.md)
AUTHORITY  .agents/consequence.yml ({{categories}}), scripts/hooks/claude-protect.sh + settings entry; CODEOWNERS: {{lines with the owners given}} (references/authority.md)
```

Once they accept, run `${CLAUDE_PLUGIN_ROOT}/scripts/keel approve build <hash>` with the hash `plan` printed; if they amend
the proposal, run `keel plan build <file>` again (the old approval no longer counts). The user's own
request can grant that acceptance up front ("do not pause for confirmation") for every high- or
low-confidence layer: present the proposal, run `plan` and `approve` in the same reply, and say in
that reply that the acceptance came from the request. A `none`-confidence layer stays uninstalled
regardless. Then run `${CLAUDE_PLUGIN_ROOT}/scripts/keel apply build` **before the first write** and
stop if it exits non-zero. In short: before writing anything, wait for the answer.

## Output contract

**The sensor output.** Every sensor emits the seven fields of `${CLAUDE_PLUGIN_ROOT}/contracts/sensor.md` section 1; the copied assets
already do. In the repo-specific block keep `guidance` on `fail` only, in this repository's terms and
naming the wrong fix ("never edit the test to match"), and the detail cap.

**The proposal block** is the one shown in "Propose, then write", one line per layer, with the real values filled in.

**`.agents/state.yml`** is **metadata only**; it does not configure the gate (budgets are in
`.agents/gate.env`, sensors are the files in `scripts/sensors/`). Write it after `keel apply`:

```yaml
schema_version: 3
installed_at: 2026-10-20          # ISO date, today
harness_review_by: 2027-04-20     # installed_at + 6 months
mode: brownfield                  # greenfield | brownfield, confirmed by the user
layers: { bootstrap: installed, guides: installed, fast_gate: installed, slow_gate: not_installed, hook: installed, authority: installed, ci: installed, precommit: not_installed, rules: not_installed }
not_installed:                    # layer or sensor -> the reason, in keel's words
  slow_gate: "no mutation or coverage tool configured"
```

Each key's type, writer and reader are in `${CLAUDE_PLUGIN_ROOT}/contracts/state.md`. Use the real reason for each `not_installed` entry, not a generic one. Ignore the generated files (hook phase); `.agents/state.yml`, `.agents/gate.env` and `.agents/baselines/` are committed.

## Discipline

**Write nothing before the user accepts and `keel apply` exits 0.** This rule has no exception.
`${CLAUDE_PLUGIN_ROOT}/scripts/keel` enforces the order (`plan`, `approve`, `apply`) in code.

| The excuse | Why it is wrong |
| --- | --- |
| "They obviously want AGENTS.md, I'll write it while we talk" | `keel apply build` has not run, so no write is allowed. Show the proposal first. |
| "The proposal changed only a little, the old approval still covers it" | An amended proposal needs `keel plan build` again; the old approval no longer counts. |
| "I can approve it myself to save a round" | Run `keel approve build` only after the user accepted that proposal, or after the request itself accepted it up front (say so in the reply). |
| "The test command is probably `npm test`" | Never invent a command: every command must be one found in discovery. |
| "Nothing can be inferred, but this layer is standard" | Never install a layer on a guess: a `none`-confidence layer stays uninstalled, under `not_installed` with a real reason. |
| "Regenerating `gate.sh` from the description is quicker" | Never regenerate a script from prose. Copy the tested asset and edit only the `keel:repo-specific` block. |
| "I'll put this repository's absolute path in the hook command" | `${CLAUDE_PROJECT_DIR}` is copied literally, escaped quotes included; Claude Code sets it when it runs the hook. |

## Done when

Run `make gate-fast` and read it, then `${CLAUDE_PLUGIN_ROOT}/scripts/keel verify build`. Fix every `fail` line and run it again until it
exits 0; only then report the layer installed. The items are in `${CLAUDE_PLUGIN_ROOT}/contracts/flow.md`.
Two things it cannot check, so check them by hand:

- Every command cited in `AGENTS.md` really exists and runs here.
- Deep content in `AGENTS.md` is `→ docs/X.md` pointers.

When it exits 0, offer the next step: `/keel-harness:rules` to propose the project's own rules
(architecture, testing strategy, conventions). Each phase is **resumable**: a layer already `installed`
is not re-proposed on a later run.
