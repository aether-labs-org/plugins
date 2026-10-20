# keel-harness — Design Spec (v0.2)

**Date:** 2026-10-20
**Status:** implemented in v0.2.0
**Supersedes:** parts of `2026-09-19-keel-harness-design.md` (v0.1). Every principle that changes is
listed in §3; everything not mentioned here stays as v0.1 defined it.
**Origin:** a review of v0.1.0 (2026-10-19) plus four rounds of owner decisions. Review evidence is
in §14.

---

## 1. What this is

v0.1 is a careful scanner: it records what it finds, installs a fast gate for TypeScript, and leaves
`docs/` stubs as TODOs. v0.2 turns keel into an **opinionated harness engineer**. It is a software
engineer experienced in AI coding agents, harness engineering and context engineering. It first
listens to the team, then reverse engineers what the repository does today, proposes what it should
do and why, and records what the human approves, together with the decision behind it.

**The rule that defines v0.2: keel proposes, the human decides.** Facts (commands, current
structure, measurements) are only ever discovered or measured. Norms (rules, architecture style,
testing strategy, limits, tools) may be proposed by keel, always with a justification, and are
written only after the human approves them in rounds of questions. keel never migrates production
code. An approved breaking change becomes a rule, a baseline, an ADR and a local migration plan.

## 2. Decisions

| # | Decision | Decided by |
| --- | --- | --- |
| D1 | keel acts as a senior engineer in AI agents, harness engineering and context engineering, with opinions | owner |
| D2 | Greenfield: keel proposes the project's rules. Brownfield: keel reverse engineers the de facto rules first, then proposes improvements with justification, breaking changes included | owner |
| D3 | keel never assumes. Every inference and every proposal is confirmed in rounds of questions before anything is written | owner |
| D4 | An approved breaking change is recorded as a rule + a baseline + a migration plan. keel never executes the migration | owner |
| D5 | Target agents: **Claude Code, GitHub Copilot, Devin** | owner |
| D6 | Execution plans live **outside git** (local only). `docs/` holds specs, PRDs and long-lived reference (rules, decisions), never execution plans | owner |
| D7 | Gate feedback to the agent: **only a Claude Code `Stop` hook**. No CI workflow, no Copilot hooks in v0.2. Copilot and Devin get the gates as an instruction in `AGENTS.md` | owner |
| D8 | Rules are indexed in the root `AGENTS.md` (one line each) plus nested `AGENTS.md` files for directory-local rules; the detail of each rule is a section of a topic file (D28) | owner |
| D9 | Fast-gate stacks in v0.2: **TypeScript, React, Java/Kotlin (Spring), Python** | owner |
| D10 | "Code language" means the natural language of identifiers and comments (e.g. English), not the programming language | builder's reading, not contradicted by owner |
| D11 | **Architecture is a first-class rule:** keel proposes an architecture style (hexagonal / ports-and-adapters, layered, clean, modular) and enforces the approved map with the stack's native tool — ArchUnit (Java/Kotlin), dependency-cruiser (TS/React), import-linter (Python) — generated from that map. It runs in the fast gate when it fits the budget; otherwise a grep sensor derived from the same map gives the fast signal and the native tool moves to the slow gate | owner |
| D12 | **Testing strategy is a first-class rule:** keel recommends test types per layer, proportions, naming and location, coverage and mutation thresholds; installs a fast `test-presence` sensor and a local `make gate-slow` (mutation testing + diff coverage), never run by the hook and never in CI | owner |
| D13 | **Decisions are taken together and recorded:** keel opens with a short context interview (goals, pains, constraints, team, appetite for breaking changes) before measuring, and records every decision with a real trade-off as an ADR (MADR) in `docs/decisions/`, linked from the rule | owner |
| D14 | **The harness is easy to edit by hand:** keel installs `.agents/README.md` (task recipes) and a portable `scripts/harness-check.sh` (`make harness-check`, runs without the plugin); installed scripts carry a "managed by keel" header; the gate discovers sensors from `scripts/sensors/*.sh` (fast) and `scripts/sensors/slow/*.sh` (slow); `.agents/state.yml` stops being executable configuration | owner |
| D15 | Rules work is a new skill, `rules`. `build` keeps bootstrap, guides, gates, hook, guide and validator | builder's call |
| D16 | Deterministic code ships as files in the skills' `assets/` and is copied, never regenerated from Markdown. Installed files are sourced from any skill's `assets/`; skills reach a sibling's assets as `${CLAUDE_SKILL_DIR}/../<skill>/assets/` | builder's call |
| D17 | Baselines: the tool's **native** baseline when it has one (ArchUnit `FreezingArchRule`, dependency-cruiser known violations, import-linter `ignore_imports`); otherwise keel's per-file TSV `.agents/baselines/<id>.tsv` | builder's call |
| D18 | Executable configuration is plain `KEY=value`: gate budgets in `.agents/gate.env` (`CEILING_SECONDS=30`, `SLOW_CEILING_SECONDS=600`), rule parameters in `.agents/rules/<id>.env`. `state.yml` holds metadata only | builder's call |
| D19 | Rule metadata (kind, origin, approval, enforcement, doc anchor, decision, plan) lives in `.agents/rules/<id>.env` next to the rule's parameters, so every rule has an env file (inferential ones included). Topic files hold prose only; `state.yml` has no `rules:` list | builder's call |
| D20 | `model_baseline` is replaced by `harness_review_by` (install date + 6 months); a baseline's `review_by` is in its own header | builder's call |
| D21 | Root and nested `AGENTS.md` keep the **100-line** ceiling | builder's call |
| D22 | `build` always ensures a root `CLAUDE.md` that imports `@AGENTS.md` | builder's call |
| D23 | ADRs live in `docs/decisions/` (MADR's default), fixing v0.1's `docs/adr/` vs `docs/decisions/` split | builder's call |
| D24 | `state.yml` gets `schema_version: 2`; `build` upgrades a v0.1 install in place, under confirmation | builder's call |
| D25 | `doctor` runs the same `harness-check.sh` (from the plugin, so it is the latest) and adds explanations and fix proposals; there is one implementation of the checks | builder's call |
| D26 | Installed and plugin-run scripts are bash 3.2 compatible (macOS default): no associative arrays, no `mapfile`, no `${x,,}`; joins use `awk`; no `jq` | builder's call |
| D27 | `make gate-slow` runs mutation testing and diff coverage only; integration and e2e suites stay the project's own targets, cited in `AGENTS.md` and recommended by the testing strategy | builder's call |
| D28 | **Rules live in topic files under `docs/`:** `docs/architecture.md` (style, codemap, layer map, architecture invariants — matklad's ARCHITECTURE.md shape), `docs/conventions.md` (file size, code language, naming, adopted patterns), `docs/testing.md` (testing strategy). Each rule is a section with an explicit anchor. ADRs stay separate in `docs/decisions/`: rules say what holds now, ADRs say why | owner |

## 3. Principles that change

| v0.1 | v0.2 | Why |
| --- | --- | --- |
| "Never invent" — record only what is found | Never invent **facts**; **propose norms** with justification and approval | D1–D3 |
| Confidence `none` → the layer is not installed | Confidence `none` → keel says it could not infer, gives its recommendation and why, and asks | D1–D3 |
| One confirmation gate per `build` run | A context interview, then rounds: at most 4 questions per round, recommended option first, each option with its trade-off | D3, D13 |
| "Installs no new tool" | May **propose** a tool (ArchUnit, dependency-cruiser, import-linter, PIT, Stryker, mutmut, gitleaks) with justification; installs only with approval | D1, D11, D12 |
| Only `heuristic` sensors may carry a snapshot | Any rule adopted after the code existed may carry a baseline, with an ADR, a migration plan and `review_by`. `security` never carries a baseline | D4, D17 |
| `state.yml` lists the sensors the gate runs | Sensors are files; the gate runs what is in `scripts/sensors/`. `state.yml` is metadata | D14 |
| Informs, never blocks. `PostToolUse` after each edit | Still blocks no action. A `Stop` hook gives the fast gate's guidance back to Claude; the conversation continues until it is green or the loop guard stops it | D7; v0.1's hook never delivered guidance (§14.1) |
| Fitness functions and mutation testing out of scope | Architecture (D11) and testing strategy (D12) are in | owner |

## 4. What keel installs in a repository (v0.2)

```
AGENTS.md                         # ≤ 100 lines: identity, commands + pass signals, "before you finish", rule index
CLAUDE.md                         # created or amended: "@AGENTS.md" (D22)
<dir>/AGENTS.md                   # directory-local rules (D8), ≤ 100 lines
docs/architecture.md              # topic file (D28): style, codemap, layer map, architecture rules
docs/conventions.md               # topic file: file size, code language, naming, adopted patterns
docs/testing.md                   # topic file: testing strategy
docs/decisions/NNNN-<slug>.md     # ADRs (MADR); 0001 records the context interview
Makefile                          # bootstrap, gate-fast, gate-slow, harness-check
scripts/gate.sh                   # runner: `gate.sh fast` | `gate.sh slow`
scripts/harness-check.sh          # portable validator (D14, D25)
scripts/lib/baseline.sh           # per-file TSV baseline comparison
scripts/lib/junit.sh              # JVM: reads this run's JUnit reports (quiet Gradle/Maven print no assertion text)
scripts/sensors/<id>.sh           # fast sensors (tool and rule sensors)
scripts/sensors/slow/<id>.sh      # slow sensors (mutation, diff coverage, native architecture tool when over budget)
scripts/sensors/stoplists/        # word lists for the code-language sensor
scripts/hooks/claude-stop.sh      # Stop-hook adapter
.claude/settings.json             # Stop hook, merged
<generated tool config>           # e.g. src/test/java/.../ArchitectureTest.java, .dependency-cruiser.cjs, .importlinter
.agents/README.md                 # how to change this harness by hand (recipes)
.agents/state.yml                 # committed; metadata only; schema_version: 2
.agents/gate.env                  # committed; CEILING_SECONDS, SLOW_CEILING_SECONDS
.agents/rules/<rule-id>.env       # committed; the rule's parameters, sourced by its sensor
.agents/baselines/<id>.tsv        # committed; per-file TSV baseline
.agents/baselines/archunit/       # committed; ArchUnit freeze store (configured via archunit.properties)
.agents/last-run.log              # gitignored
.agents/last-green, last-seen,    # gitignored; Stop-hook state
.agents/last-fail
.agents/.gate-lock/               # gitignored
.agents/plans/                    # gitignored; local migration plans (D6)
```

`scripts/` is plain bash that runs with the plugin uninstalled (v0.1 §9 portability is unchanged).
Every installed script starts with:
`# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.`

`.agents/state.yml` (metadata only):

```yaml
schema_version: 2
installed_at: 2026-10-20
harness_review_by: 2027-04-20
mode: brownfield            # greenfield | brownfield, confirmed by the user
layers: { bootstrap: installed, guides: installed, fast_gate: installed, slow_gate: installed, hook: installed, rules: installed }
not_installed: {}           # layer or sensor -> the reason, in keel's words
```

## 5. The `rules` skill

### 5.1 Flow

0. **Precondition.** Rule sensors run inside the gates, so `rules` needs `scripts/gate.sh` and the
   Makefile targets. If they are missing, it offers to run `build` first. In greenfield, `build`
   installs the runner even when no tool sensor can run yet; a gate with zero sensors is valid.
1. **Context interview.** One round before any measurement: what the team wants from agents, what
   agents get wrong today, constraints (deadlines, compliance, legacy, team size), which agents are
   used, and the appetite for breaking changes. The answers go into `docs/decisions/0001-agent-harness-context.md`
   (the first ADR) and steer every later proposal.
2. **Mode.** keel classifies the repository as greenfield (no tracked source files in the stack's
   source roots) or brownfield, states the evidence, and asks the user to confirm. Stored as `mode:`.
3. **Inventory.** It reads every instruction file the target agents load: `AGENTS.md` (root and
   nested), `CLAUDE.md`, `.claude/CLAUDE.md`, `.claude/rules/`, `.github/copilot-instructions.md`,
   `.github/instructions/`, `.devin/rules/`, `.cursor/rules/`, plus `docs/`, lint and architecture
   tool configs, test layout and existing ADRs.
4. **Reverse engineering (brownfield).** For each catalog entry, keel measures the as-is state with
   `measure.sh` and reports it before proposing anything (§5.3).
5. **Proposals.** For each entry, keel proposes a rule with two kinds of justification:
   **repository data** ("p90 = 240 lines; 12 files over 500") and an **external source** from the
   catalog (official doc, tool default, study). It labels opinion as opinion, flags breaking
   proposals, and states their blast radius (files affected).
6. **Rounds.** Proposals are approved, amended or rejected in rounds (§3). keel uses
   `AskUserQuestion` when available. When it is not (non-interactive runs), it asks in plain text;
   if the user's own request pre-authorised proceeding, it takes the recommended option of each
   question and says so.
7. **Write** only what was approved, in this order: ADR (when the decision had a real trade-off,
   §5.8) → the rule's section in its topic file → the line in the right `AGENTS.md` → `.agents/rules/<id>.env` →
   the sensor(s) and any generated tool config → the baseline → `.agents/plans/` entry in
   `.gitignore` → then `make gate-fast` is run and read.
8. **Plan.** For each approved rule whose baseline is non-empty, keel writes a local migration plan
   (§5.5) and records it as `PLAN=` in the rule's env file.

Greenfield skips step 4, proposes from the catalog and the context interview, and starts every
baseline empty.

### 5.2 The rule record

A rule has two parts: **prose** in its topic file, for humans and agents, and **metadata plus
parameters** in `.agents/rules/<id>.env`, for the machine (D19).

Which topic file holds which rule:

| Topic file | Rules |
| --- | --- |
| `docs/architecture.md` | `architecture`, `folder-layout` |
| `docs/conventions.md` | `file-size`, `code-language`, `adopted-patterns`, any other code convention |
| `docs/testing.md` | `testing-strategy` |

Each topic file starts with a short introduction. For `docs/architecture.md` that is matklad's
shape: a bird's-eye overview of at most five lines, the codemap, and the layer boundaries. After
the introduction, each rule is one section:

```markdown
<a id="file-size"></a>
### Source files stay under 300 lines

**Rule.** <one verifiable sentence, quoting the parameters: 300 lines, `src/**`>
**Why.** <the reason, in this project's terms>
**✓ / ✗.** <a short good and bad example>
**When it fails.** <what to do — same text as the sensor's guidance>
**Decision.** [ADR 0003](decisions/0003-file-size-limit.md)   <!-- when an ADR was written -->
```

The anchor `<a id="<rule-id>"></a>` is the stable link target. Every pointer uses it, for example
`docs/conventions.md#file-size`, so renaming the heading breaks nothing. A topic file stays at or
under **300 lines**; past that, keel proposes splitting it by subtopic (e.g.
`docs/conventions-naming.md`).

`.agents/rules/file-size.env`:

```sh
# Managed by keel-harness - see .agents/README.md
RULE_ID=file-size
KIND=metric                       # metric | structure | convention | pattern | testing
ORIGIN=proposed                   # discovered | proposed | user
APPROVED_AT=2026-10-20
ENFORCEMENT=sensor:file-size      # sensor:<id>[,sensor:<id>] | inferential
DOC=docs/conventions.md#file-size
DECISION=docs/decisions/0003-file-size-limit.md   # optional
PLAN=.agents/plans/2026-10-20-file-size.md        # optional; local, may be absent on other clones
LIMIT=300
INCLUDE='src/'
```

The prose quotes the parameters, and the validator flags any divergence.

### 5.3 The catalog

`skills/rules/references/catalog.md` holds the engineer's knowledge. Each entry has: the questions
to ask, how to measure the as-is state (`measure.sh` subcommand), how the default is derived, its
justification with sources, the sensor per stack, its class, and where it is opinion.

| Entry | Kind | Sensor | Class |
| --- | --- | --- | --- |
| `file-size` | metric | agnostic: `git ls-files` + `wc -l` | heuristic, TSV baseline |
| `folder-layout` | structure | agnostic: path patterns over `git ls-files` | correctness, TSV baseline when adopted late |
| `architecture` | structure | native tool per stack (§5.6) + grep fallback | correctness, native baseline |
| `code-language` | convention | agnostic heuristic: non-ASCII letters plus a stop-list of the non-target language, string literals ignored | heuristic, TSV baseline |
| `testing-strategy` | testing | fast `test-presence`; slow `mutation` and `diff-coverage` (§5.7) | heuristic (presence, TSV baseline); correctness against thresholds (slow) |
| `adopted-patterns` | pattern | inferential; the catalog documents promotion to ast-grep/semgrep when a syntactic form exists | — |

Default proposals: in brownfield, derived from the measured distribution (e.g. the next round number
at or above p90, never below p75); in greenfield, the catalog default with its source (e.g. ESLint's
`max-lines` default of 300). The catalog says where a default is opinion.

### 5.4 Placement

- A rule that applies everywhere: one line in the root `AGENTS.md` → `docs/<topic>.md#<id>`.
- A rule that applies to one directory: one line in `<dir>/AGENTS.md` → `docs/<topic>.md#<id>`. All
  three target agents read the nearest `AGENTS.md`.
- A procedure (multi-step how-to): a doc under `docs/`, pointed to from the rule.
- A decision: an ADR in `docs/decisions/` (§5.8).
- Glob-scoped adapters (`.claude/rules/` with `paths:`, `.github/instructions/` with `applyTo`) are
  **out of scope** for v0.2.

### 5.5 Baselines and migration plans

- **TSV baselines** (`.agents/baselines/<id>.tsv`): first line
  `# measured_at: YYYY-MM-DD review_by: YYYY-MM-DD`, then `path<TAB>count`. Meaning: this file may
  keep up to `count` violations; a file absent from the baseline may have zero. A sensor fails when
  any file exceeds its count or a non-baselined file has any; shrinking is always allowed. Sensors
  never write baselines. Every TSV-baselined sensor supports `KEEL_MEASURE=1`, which prints the
  header and the current non-zero counts; that output is what keel writes at approval time. Because
  baselines are per file, baselined sensors may honour `SCOPE`.
- **Native baselines** (D17): ArchUnit's `FreezingArchRule` store under `.agents/baselines/archunit/`
  (via `archunit.properties`: `freeze.store.default.path`), dependency-cruiser's known-violations file
  `.agents/baselines/depcruise-known-violations.json` (`depcruise-baseline` / `--ignore-known`),
  import-linter's `ignore_imports` in the contract, rendered from `IGNORE_IMPORTS` in the env file
  with `unmatched_ignore_imports_alerting = warn`, so fixing a frozen import never fails the gate.
- Only keel writes or tightens baselines, and only with approval; keel never raises one.
- Each baselined rule gets a local plan `.agents/plans/YYYY-MM-DD-<rule-id>.md`: small steps, each
  with an acceptance criterion in the sensor's numbers ("file-size baseline: 12 → 8 files"), written
  so any agent or person can execute it later. The validator does not fail when a plan is absent
  (another clone).

### 5.6 Architecture

- **Styles in the catalog:** hexagonal / ports-and-adapters (domain, application, adapters), layered,
  clean, modular monolith. Each style has a template **map**: named layers, the path/package of
  each, and which layer may depend on which. Hexagonal also forbids framework imports in the domain
  (e.g. `org.springframework`, `jakarta.persistence`, `django`, `express`), listed per stack.
- **The approved map is the single source:** `.agents/rules/architecture.env` (`STYLE`, `LAYERS`
  lines `name|path_prefix|import_prefix|allowed_csv`, `FORBIDDEN` lines `layer|import_prefix`).
  From it, keel generates the native configuration with the user's approval:
  - Java/Kotlin: `ArchitectureTest` (JUnit 5, `@AnalyzeClasses`, `@ArchTest`) using
    `Architectures.onionArchitecture()` for hexagonal or `layeredArchitecture()` for layered,
    wrapped in `FreezingArchRule.freeze(...)` in brownfield, plus `archunit.properties`, plus the
    `archunit-junit5` test dependency.
  - TS/React: `.dependency-cruiser.cjs` forbidden rules.
  - Python: an `.importlinter` layers contract.
- **Empty imports:** ArchUnit fails a rule that checks no class (`failOnEmptyShould`). In greenfield,
  every rendered rule gets `.allowEmptyShould(true)`, so packages without code do not fail. In
  brownfield, one unfrozen guard rule (`classes_are_analysed`) fails when ArchUnit imports no class of
  the project, which happens when the ArchUnit release cannot read the project's JDK bytecode.
- **Where it runs:** `scripts/sensors/architecture.sh` runs the native tool (e.g. only the
  `ArchitectureTest` class). keel measures it at install. If it fits `CEILING_SECONDS` together with
  the other fast sensors, it stays fast. Otherwise it moves to `scripts/sensors/slow/` and
  `scripts/sensors/architecture-grep.sh` (the grep engine over the same `LAYERS`/`FORBIDDEN`) gives
  the fast signal.

### 5.7 Testing strategy

- **Recommendation** (catalog, decided in rounds): test types per layer, with the style's default
  (hexagonal: domain = unit tests without the framework; adapters = integration tests, e.g.
  Testcontainers; few end-to-end tests), the frameworks, naming and location, a diff-coverage
  threshold and a mutation-score threshold. Integration and e2e suites stay the project's own
  targets (D27), cited in `AGENTS.md`.
- **Fast:** `scripts/sensors/test-presence.sh`. For each changed main file matching the rule's
  scope, a test must exist per the approved mapping (`MAPPINGS` lines `from_regex|to_template`).
  TSV baseline in brownfield.
- **Slow (`make gate-slow`):**
  - `scripts/sensors/slow/mutation.sh`: PIT (JVM), Stryker (TS/React) or mutmut (Python), on the
    changed main files; fails when the score is under `MUTATION_MIN_SCORE`.
  - `scripts/sensors/slow/diff-coverage.sh`: line coverage of the changed lines only (the + side of `git diff -U0 HEAD`, every line of a new file) from lcov (TS,
    Python) or JaCoCo XML (JVM); fails when it is under `DIFF_COVERAGE_MIN`.

  The slow gate is never run by the hook and never wired to CI. `AGENTS.md` tells agents to run it
  before opening a PR.

### 5.8 Decisions (ADRs)

- MADR format: context and problem, decision drivers, considered options (each with pros and cons),
  decision outcome, consequences, and the evidence links keel used.
- Written when a round had a real trade-off (more than one viable option), when a rule is breaking,
  or when the user overrides keel's recommendation. They are numbered `NNNN`, never edited once
  accepted, and superseded by a new ADR.
- `0001-agent-harness-context.md` records the context interview.

## 6. Gates and feedback

### 6.1 The Stop hook (fixes §14.1)

`scripts/hooks/claude-stop.sh`, wired as:

```json
{ "hooks": { "Stop": [ { "hooks": [ {
  "type": "command",
  "command": "\"${CLAUDE_PROJECT_DIR}\"/scripts/hooks/claude-stop.sh",
  "timeout": 120
} ] } ] } }
```

Behaviour (fast gate only):
- Reads the hook input from stdin. Outside a git repository: exit 0, no output.
- **Skip:** the working-tree fingerprint covers `HEAD`, `git diff HEAD`, and the untracked files
  with their content hashes, so a change committed during the turn still counts. When it equals
  `.agents/last-green`, the hook exits 0 with no output. When it equals `.agents/last-seen`, the tree
  the hook last looked at whatever the result, the failure was already reported: the hook exits 0
  silently, or with the loop-guard message when `stop_hook_active` is true. On the very first look
  at a clean tree, it only records `.agents/last-seen`, so a chat-only turn never reports old failures.
- **Pass:** `scripts/gate.sh fast` is green → it writes the fingerprint to `.agents/last-green` and
  exits 0 with no output.
- **Fail:** it prints one JSON object on stdout:
  `{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":"<header + gate report>"}}`.
  The header tells Claude the gate failed after its changes and to follow each `guidance:` block
  before finishing. The report is truncated at 40 lines.
- **Loop guard:** if `stop_hook_active` is true and the failing report equals `.agents/last-fail`, it
  exits 0 with `{"systemMessage": "..."}` for the human instead of continuing. Claude Code's own cap
  (8 consecutive continuations) is the second guard.
- **Locking:** concurrent runs are serialised with a `mkdir` lock (`.agents/.gate-lock/`, stale
  after 10 minutes).
- **Constraints:** it never exits 2 and never emits `decision: "block"`. JSON is built without `jq`,
  with a tested escaping function.

### 6.2 Gate runner

`scripts/gate.sh fast|slow` (default `fast`) keeps v0.1's output contract (line-1 format, ✓/✗/○,
verdict line, 40-line truncation, `.agents/last-run.log`) and changes as follows:
- it runs every `scripts/sensors/*.sh` (fast) or `scripts/sensors/slow/*.sh` (slow), sorted by
  name; the id is the file name. Subdirectories and non-`.sh` files are not run, so moving a sensor
  to `scripts/sensors/disabled/` turns it off;
- the budget comes from `.agents/gate.env` (`CEILING_SECONDS`, default 30; `SLOW_CEILING_SECONDS`,
  default 600). It is total, and the verdict adds ` (over ceiling)` when spent exceeds it;
- the verdict line names the gate: `gate: fast - …` / `gate: slow - …`;
- `SCOPE` excludes deleted files; with no commits yet it is empty (whole repo);
- it passes `shellcheck` with no warnings.

### 6.3 Copilot and Devin

The root `AGENTS.md` carries "Before you finish": run `make gate-fast`, read line 1 of each sensor
and its `guidance:`, fix in order, re-run; and before opening a PR, run `make gate-slow`. This is
the only gate signal those agents get in v0.2 (D7).

### 6.4 Sensors per stack

| Stack | Types | Style | Affected tests | Architecture | Mutation | Secrets |
| --- | --- | --- | --- | --- | --- | --- |
| TypeScript | `tsc --noEmit` | ESLint or Biome | Vitest `related` / Jest `--findRelatedTests` | dependency-cruiser | Stryker | gitleaks `dir` per changed file |
| React | as TypeScript; framework build stays out | ESLint with the framework config found | as TypeScript | dependency-cruiser | Stryker | as TS |
| Python | mypy or pyright | ruff | pytest on tests mapped from changed modules | import-linter | mutmut | as TS |
| Java/Kotlin (Spring) | compile via the Gradle/Maven wrapper, measured | Checkstyle/Spotless (Java), ktlint or detekt (Kotlin) | `<Class>Test` for changed classes | ArchUnit | PIT | as TS |

As in v0.1, the table names tools, never commands. Commands come from discovery. Lint-type
heuristic sensors use TSV baselines.

## 7. `build` changes

- Copies assets via `${CLAUDE_SKILL_DIR}` (D16). It writes only the repo-specific parts: discovered
  commands and guidance text inside the markers.
- Installs `gate.sh`, `gate.env`, the Makefile targets `gate-fast`, `gate-slow` and `harness-check`,
  `harness-check.sh`, `.agents/README.md`, and the Stop hook (§6.1).
- Ensures `CLAUDE.md` imports `@AGENTS.md` (D22): if `CLAUDE.md` exists, it adds the import as the
  first line under confirmation; if not, it creates a one-line `CLAUDE.md`.
- Uses the new `AGENTS.md` template, which drops the File map, Docs Index, Metrics and Schemas
  sections (repository overviews do not help, §14.4). It keeps a one-line identity, commands with
  pass signals, "Before you finish", the rule index and output-reading notes.
- Uses rounds of questions instead of one confirmation gate (§3).
- Hands off to `rules` at the end ("propose project rules now?").
- Upgrades a v0.1 install (D24) under confirmation:
  - replaces the `PostToolUse` hook;
  - converts `snapshot:` into a re-measured TSV baseline;
  - turns `sensors:` into files and `model_baseline` into `harness_review_by`;
  - adds the new `.gitignore` entries.

## 8. `assess` changes

Seven axes. The three states and the evidence rule stay; there is still no aggregate score.

| Axis | Change |
| --- | --- |
| Bootstrap | unchanged |
| Guides | any instruction file read by a target agent counts (AGENTS.md, CLAUDE.md, copilot-instructions, `.devin/rules`). Present = ≤ 100 lines + `docs/` content |
| Fast sensors | unchanged; an architecture tool configured counts as a style/structure sensor |
| Slow sensors | present = a suite that runs, coverage configured **and** mutation testing configured; partial = suite without one of them |
| Enforcement | `.pre-commit-config.yaml`, husky or lefthook, plus CI running the same commands |
| Context | **redefined:** the instructions reach every target agent. Present = `AGENTS.md` exists and either there is no `CLAUDE.md` or `CLAUDE.md` imports `@AGENTS.md`. `.mcp.json` is no longer required |
| **Rules** (new) | present = at least one rule documented with a sensor; partial = documented rules without enforcement, or TODO stubs; absent = none |

`assess` also reports the mode (greenfield/brownfield) as an inference to confirm. "Setup minutes"
is renamed **estimated setup minutes**, since it cannot be measured before `build` runs.

## 9. `harness-check.sh` and `doctor`

One implementation (D25): `scripts/harness-check.sh`, installed in the repository (`make
harness-check`, usable by any agent or person) and run by `doctor` from the plugin's latest copy.
One broken condition produces exactly one warning, as
`warn<TAB><check-id><TAB><file><TAB><message><TAB><fix>`, followed by `harness-check: N warning(s)` or
`harness-check: harness is clean`. Exit 0 clean, 1 warnings, 2 no harness.

| Check id | Condition |
| --- | --- |
| `agents-size` | a tracked `AGENTS.md` over 100 lines |
| `stale-command` | a command cited in `AGENTS.md` no longer resolves (Makefile target, `package.json` script, file, `command -v`) |
| `agents-not-loaded` | `CLAUDE.md` or `.claude/CLAUDE.md` exists without `@AGENTS.md` |
| `dangling-pointer` | a `→ path[#anchor]` in an `AGENTS.md` whose target file or `<a id>` anchor is missing, or whose target is still a TODO stub |
| `hook-missing` | no Stop hook pointing at an executable `scripts/hooks/claude-stop.sh` |
| `sensor-malformed` | a sensor file whose `id=` differs from its file name, whose `class=` is not `security|correctness|heuristic`, or that is not executable |
| `sensor-unavailable` | a fast sensor that exits 2 when run with `SCOPE` set to one tracked file it covers |
| `rule-inconsistent` | a `.agents/rules/<id>.env` missing one of `RULE_ID KIND ORIGIN APPROVED_AT ENFORCEMENT DOC`; whose `DOC` file or anchor is missing; whose `sensor:<id>` file or `DECISION` ADR is missing; or whose numeric parameters do not appear in the anchored section (from the anchor to the next anchor or the end of the file) |
| `topic-size` | `docs/architecture.md`, `docs/conventions.md` or `docs/testing.md` over 300 lines |
| `baseline-malformed` | a TSV baseline without the header or with a line that is not `path<TAB>integer` |
| `baseline-stale` | a TSV baseline past its `review_by` whose current total (`KEEL_MEASURE=1`) is not below the stored total |
| `review-due` | `harness_review_by` has passed |

A missing `plan:` file is not a warning (D6). `doctor` explains each warning, proposes the fix
through `build` or `rules`, writes nothing, and points at Claude Code's `/doctor prompt-audit` for
contradictions between instruction files. When the installed `harness-check.sh` differs from the
plugin's copy, `doctor` proposes updating it.

## 10. `.agents/README.md`

Installed by `build`, ≤ 120 lines, task-oriented. Recipes:
- change a rule's limit (edit the env file and the doc, run `make harness-check`);
- add a sensor (drop an executable file in `scripts/sensors/` following the line-1 contract);
- disable a sensor (move it to `scripts/sensors/disabled/`);
- shrink a baseline after a fix (`KEEL_MEASURE=1 bash scripts/sensors/<id>.sh > .agents/baselines/<id>.tsv`);
- add a rule by hand (add an anchored section to the right topic file and copy an existing `.agents/rules/*.env`);
- record a decision (copy the ADR template);
- turn the Stop hook off (remove its entry from `.claude/settings.json`);
- where each file lives and which ones are generated tool config.

## 11. Fixes carried from the review

- ADR path (D23).
- The whole-repo snapshot is replaced by baselines (D17).
- gitleaks `detect` → `dir` over changed files.
- The self-reported eval metric (`linecount.txt`) is replaced by a grader on the real command.
- "Setup minutes" is labelled as an estimate.
- The unsourced "~150–200 instructions" claim is removed.
- The shellcheck warnings in `gate.sh` are fixed.

## 12. Validation

- **Deterministic tests (free, CI):**
  - shellcheck over every asset;
  - behaviour tests for `gate.sh` (fast/slow, discovery, budget), `claude-stop.sh` (skip, pass,
    fail-JSON, loop guard, escaping, lock), `harness-check.sh` (one fixture per check), every
    sensor (stub tools, synthetic git repos) and `measure.sh`;
  - structural tests for skills, catalog, templates and the README asset.
- **`claude plugin eval` (paid, manual):**
  - updated `assess-mature-repo` (seven axes) and new `assess-claude-md`;
  - `build-typescript` (Stop hook + `CLAUDE.md` import), `build-python`, `build-java`, `build-react`;
  - `rules-brownfield` (interview, measures, proposes with data and a source, writes rule + ADR +
    baseline + local plan, never edits `src/`);
  - `rules-greenfield`;
  - `rules-architecture-java` (proposes hexagonal, generates `ArchitectureTest` with `onionArchitecture`);
  - `doctor-*`;
  - **`rules-effect-with` / `-without`**: the same feature request with and without approved rule
    docs, graded by the installed gate. It is the only Δ that tests whether "proposed by keel,
    approved by a human" helps, since the published evidence covers unreviewed LLM-generated files
    only (§14.4).
- `claude plugin validate --strict` stays in CI.

## 13. Out of scope for v0.2

- Executing migrations (D4).
- CI workflow generation and Copilot hooks (D7).
- Glob-scoped adapters (`.claude/rules`, `.github/instructions`).
- Running integration or e2e suites inside keel's gates (D27).
- Inferential sensors.
- History-based checks.
- Go, Terraform and .NET wrappers (documentation only, as in v0.1).
- Moving this repository's existing `docs/plans/` (a separate decision for the owner).

## 14. Evidence

1. **v0.1's hook never delivered guidance.** For `PostToolUse`, exit-0 stdout goes to the debug log
   and exit 2 shows Claude only stderr ([hooks docs](https://code.claude.com/docs/en/hooks)). A
   failing `make gate-fast` exits 2 with only `make: *** [...] Error 1` on stderr, while the report
   is on stdout (reproduced with GNU Make 4.4.1). `PostToolUse` fires concurrently for parallel tool
   calls. `Stop` accepts `additionalContext`, with a continuation cap of 8.
2. **`AGENTS.md` is skipped when `CLAUDE.md` exists.** Claude Code reads `AGENTS.md` only when there
   is no `CLAUDE.md`, `.claude/CLAUDE.md` or `CLAUDE.local.md`; a `CLAUDE.md` with `@AGENTS.md` is
   the documented bridge ([memory docs](https://code.claude.com/docs/en/memory#agents-md)).
3. **The target agents read nested `AGENTS.md`:** Copilot ("the nearest AGENTS.md … will take
   precedence", [docs](https://docs.github.com/en/copilot/how-tos/configure-custom-instructions/add-repository-instructions))
   and Devin CLI and Desktop ([docs](https://docs.devin.ai/onboard-devin/agents-md)). Whether
   Devin's cloud product reads it is unverified (risk, §15).
4. **Context files:** Gloaguen et al., ICLR 2026 ([arXiv 2602.11988](https://arxiv.org/abs/2602.11988)).
   - LLM-generated files changed the success rate by −0.5 % / −2 %, at +20–23 % cost.
   - Developer-written files did 7 points better than generated ones (p = 3.8 %).
   - Repository overviews did not help; tool instructions were followed.

   Lulla et al. ([arXiv 2601.20404](https://arxiv.org/abs/2601.20404)) found −28.6 % median runtime
   with an `AGENTS.md`.
5. **Steering by iteration and the behaviour gap** ([Böckeler](https://martinfowler.com/articles/harness-engineering.html)):
   - "Whenever an issue happens multiple times, the feedforward and feedback controls should be improved".
   - Custom linter messages that carry self-correction instructions.
   - The behaviour harness is "the elephant in the room", and faith in AI-generated tests "is not
     good enough yet".
6. **Skills bundle scripts**, expose `${CLAUDE_SKILL_DIR}`, and every loaded line is a recurring
   token cost ([skills docs](https://code.claude.com/docs/en/skills)).
7. **Native baselines:**
   - ArchUnit: `onionArchitecture()` is "also known as Hexagonal Architecture or Ports and Adapters";
     `FreezingArchRule` records existing violations and reports only new ones
     ([ArchUnit user guide](https://www.archunit.org/userguide/html/000_Index.html)).
   - dependency-cruiser: `depcruise-baseline` with `--ignore-known`.
   - import-linter: `ignore_imports` ([docs](https://import-linter.readthedocs.io/en/v2.0/contract_types.html)).
   - ESLint: bulk suppressions count per file and rule
     ([ESLint](https://eslint.org/blog/2025/04/introducing-bulk-suppressions/)), the model for keel's TSV.
8. **gitleaks** deprecated `detect`/`protect` in v8.19.0 in favour of `git`/`dir`/`stdin`
   ([gitleaks](https://github.com/gitleaks/gitleaks)).

## 15. Risks and open questions

| Risk | Mitigation |
| --- | --- |
| Rules proposed by an LLM behave like the unhelpful generated files in §14.4 | Context interview; human approval per rule; verifiable rules only; no overviews; `rules-effect` eval |
| Devin's cloud product may not read `AGENTS.md` | Stated in the README; revisit if the owner sees it fail |
| Copilot also reads `CLAUDE.md` and may see `@AGENTS.md` as a literal line | Harmless: that line is the whole file, or the first line of the owner's file |
| Java/Kotlin compile or ArchUnit over the 30 s budget | The budget rule moves them to the slow gate (ArchUnit) or leaves them out (compile) and says so; the user may approve a higher budget |
| Mutation testing is slow and tool setup varies by build | Slow gate only, scoped to changed files, proposed per stack with approval; skip with the reason when the tool is absent |
| `code-language` heuristic is noisy | Heuristic class, baselined, scoped to changed files |
| A Stop hook that continues the conversation feels like blocking | Loop guard plus the cap of 8; skipped when nothing changed |
| Generated tool config (ArchitectureTest, `.dependency-cruiser.cjs`) drifts from the env map | It is regenerated only through `rules`; `.agents/README.md` says which is the source |
