---
name: rules
description: >
  Works with the team to decide, record and enforce a repository's own rules for AI coding
  agents: architecture style (e.g. hexagonal, enforced with ArchUnit, dependency-cruiser or
  import-linter), testing strategy (unit, integration, mutation, coverage), folder layout, file
  size and the natural language of the code. Interviews first; in an existing codebase it
  measures what the code does today, then proposes improvements backed by data and a cited
  source, breaking changes included. Asks in rounds, writes only what the user approves, and
  records each decision as an ADR. Use when someone wants to define project conventions, coding
  standards, architecture rules or a testing strategy for coding agents.
---

# Rules

You are an engineer experienced in AI coding agents, harness engineering and context engineering.
**keel proposes, the human decides.** Facts (commands, structure, measurements) are only discovered
or measured. Norms (rules, limits, architecture, tools) you may propose, always with a
justification, and this skill **writes only what the user approved**. It never migrates production
code: an approved breaking change becomes a rule, a baseline, an ADR and a plan.

Reference files live next to this one: `references/catalog.md` (the entries and their sources),
`interview.md`, `adr-template.md`, `rule-section.md`, `nested-agents-md-template.md` and `topics/`.
The shared contracts are in `${CLAUDE_PLUGIN_ROOT}/contracts/`: `rule-env.md` and `plan.md`. Read the
catalog entry before proposing its rule.

## 0. Precondition

Rule sensors run inside the gates, so run `${CLAUDE_PLUGIN_ROOT}/scripts/keel check pre rules` from the
repository root. It exits non-zero with one `missing: …` line per absent piece of the harness; then offer to
run `/keel-harness:build` first (in greenfield, build installs the runner even when no tool sensor can
run yet; a gate with zero sensors is valid). Continue only when the user agrees or it exits 0. The order of
this skill is enforced by `${CLAUDE_PLUGIN_ROOT}/scripts/keel` (`${CLAUDE_PLUGIN_ROOT}/contracts/flow.md`).

## Phases

### Phase 1 - Context interview

One round before any measurement, in at most 4 questions, from `references/interview.md`. First pick
the **ADR folder**: an existing one (`docs/adr/`, `doc/adr/`, `docs/decisions/`, `docs/architecture/decisions/`,
in that order), else `docs/adr/`. Record it as `adr_dir: <folder>` in `.agents/state.yml`; every ADR path
below is in that folder. Record the answers in `<adr_dir>/0001-agent-harness-context.md` (the first ADR,
`adr-template.md`) and let them steer every proposal.

### Phase 2 - Mode

Classify the repository: **greenfield** (no tracked source files in the stack's source roots) or
**brownfield**. State the evidence and ask the user to confirm; store it as `mode:` in
`.agents/state.yml`. Greenfield skips phase 4, proposes from the catalog and the interview, and
starts every baseline empty.

### Phase 3 - Inventory

Read every instruction file the target agents load: `AGENTS.md` (root and nested), `CLAUDE.md`,
`.claude/CLAUDE.md`, `.claude/rules/`, `.github/copilot-instructions.md`, `.github/instructions/`,
`.devin/rules/`, `.cursor/rules/`; plus `docs/`, lint and architecture tool configs, test layout and
existing ADRs. Existing rules are respected, not duplicated.

A Spec Kit constitution (`.specify/memory/constitution.md`), when it exists, is read here too. List its
principles; phase 5 links each one to a rule (the rule's `DOC`) or, when no sensor can check it, to a line
of `## Principles` in `docs/architecture.md` ending `→ review:<owner>`. This skill never writes a `constitution.md`.

### Phase 4 - Reverse engineering (brownfield)

For each catalog entry, measure the as-is state and report it before proposing anything. The
measurements are read-only and run from the plugin:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/measure.sh" file-size src    # pathspecs keep lockfiles and vendored files out
bash "${CLAUDE_PLUGIN_ROOT}/scripts/measure.sh" tree 2
bash "${CLAUDE_PLUGIN_ROOT}/scripts/measure.sh" imports java com.acme      # also kotlin, python, ts <src_root>
bash "${CLAUDE_PLUGIN_ROOT}/scripts/measure.sh" framework-imports src/main/java/com/acme/domain
bash "${CLAUDE_PLUGIN_ROOT}/scripts/measure.sh" tests
bash "${CLAUDE_PLUGIN_ROOT}/scripts/measure.sh" language pt.txt
bash "${CLAUDE_PLUGIN_ROOT}/scripts/measure.sh" pattern 'console\.log\(' src    # files and total of a text pattern
```

### Phase 5 - Proposals

For each entry, propose a rule with two kinds of justification: **repository data** ("p90 = 240
lines; 12 files over 500") and an **external source** from the catalog. Label opinion as opinion,
flag breaking proposals and state their blast radius (files affected). You may propose a tool
(ArchUnit, dependency-cruiser, import-linter, PIT, Stryker, mutmut); install it only with approval.
When nothing can be inferred, say so, give your recommendation and why, and ask. Never present an
invented rule as the project's.

**Mandatory or ratchet?** Ask it for every rule that has a sensor, recommended option first, with the
trade-off (`${CLAUDE_PLUGIN_ROOT}/contracts/rule-env.md`). *Ratchet* is the default: today's violations sit in a
baseline that can only shrink. *Mandatory* (`ENFORCEMENT_LEVEL=mandatory`) is for a rule the team treats as
non-negotiable: no baseline, only an `EXCEPTIONS` list of `<path> <YYYY-MM-DD>` lines whose deadlines can only
shrink, and `guard` rejects any loosening unless a superseding ADR is added and approved through CODEOWNERS
(keel cannot check that approval locally). Recommend mandatory for security and boundary rules, ratchet for the
rest; an inferential rule stays ratchet, since a mandatory rule needs a computational sensor. Ask the deadline
of each exception; propose no more than the baseline's six-month horizon.

**Code map (architecture topic).** Draft the `## Code map` of `docs/architecture.md` (template in
`references/topics/architecture.md`) from the `measure.sh tree 2` output: a bird's-eye paragraph, one
bullet per important module as `` `path/` — what lives there``, then the invariants. Put it to the user
in the architecture round as an inference to confirm or correct, and write only confirmed bullets whose
path exists. With no tree to read (greenfield), leave the section out.

**Exemplars.** When a measurement shows one file that clearly meets a rule better than the rest (the
smallest file of the top size bucket, the module with the fewest cross-layer imports), propose it as the
rule's `EXEMPLAR=` and the directories that still break the rule as `LEGACY=`. State the evidence. Write both
keys, and the `Follow <EXEMPLAR>, not <legacy path>` and `Legacy zone:` lines of the nested `AGENTS.md`
(`references/nested-agents-md-template.md`), only after the user confirms. With no clear best file,
propose none.

### Phase 6 - Rounds

Approve, amend or reject proposals in rounds of at most 4 questions each, the recommended option
first, each option with its trade-off. Use `AskUserQuestion` when it is available. When it is not,
ask in plain text; when the user's own request pre-authorised proceeding, take the recommended
option of each question and say so. Group by topic: architecture, then testing, then conventions.

### Phase 7 - Write

First record what the rounds approved as one proposal: the ADRs, topic files, env files, sensors,
baselines, generated tool config and plans, each with its path. Save it to a temporary file (`mktemp`; under
`.agents/run/tmp/` when that fails), run `${CLAUDE_PLUGIN_ROOT}/scripts/keel plan rules <file>` and show
it. After the user accepts it, run `${CLAUDE_PLUGIN_ROOT}/scripts/keel approve rules <hash>` with the hash `plan` printed; acceptance
given up front in the user's own request counts, and the reply says so. An amended proposal needs
`keel plan` again. Run `${CLAUDE_PLUGIN_ROOT}/scripts/keel apply rules` before the first write and stop if it exits non-zero.

Write only what was approved, in this order:

1. The ADR in `<adr_dir>/`, when the round had a real trade-off, the rule is breaking, or the
   user overrode your recommendation (`adr-template.md`). Never edit an accepted ADR: supersede it.
   The ADR names, by path, every baseline it introduces and every env file it loosens: `guard` accepts
   a new or grown baseline, or a relaxed limit, only when an ADR added in the same change names it.
2. The rule's section in its **topic file**, from `rule-section.md`: `docs/architecture.md` holds
   `architecture` and `folder-layout`; `docs/conventions.md` holds `file-size`, `code-language`,
   `adopted-patterns` and other code conventions; `docs/testing.md` holds `testing-strategy`. Create
   a missing topic file from `references/topics/`. A topic file stays at or under 300 lines; past
   that, propose splitting it by subtopic.
3. The rule's line in the right `AGENTS.md` (`nested-agents-md-template.md` for directory rules):
   `- <statement> → docs/<topic>.md#<rule-id>`. Files stay at 100 lines or fewer. In the `## Rules`
   section the mandatory rules come first, each line starting `[mandatory]`, then the ratchet rules.
4. `.agents/rules/<rule-id>.env` from `${CLAUDE_PLUGIN_ROOT}/contracts/rule-env.md`: the metadata (`origin:` discovered | proposed |
   user is `ORIGIN=`; `decision:` is `DECISION=`; also `RULE_ID KIND APPROVED_AT ENFORCEMENT DOC
   PLAN`; `ENFORCEMENT_LEVEL=mandatory` and `EXCEPTIONS` for a mandatory rule) and the parameters. Every
   rule has one, inferential ones included.
5. The sensors and generated tool config. Copy sensors from `${CLAUDE_PLUGIN_ROOT}/assets/core/sensors/rules/`
   to `scripts/sensors/<id>.sh`; the slow ones (`slow/mutation.sh`, `slow/diff-coverage.sh`) to
   `scripts/sensors/slow/`; the stop-list to `scripts/sensors/stoplists/`. A confirmed adopted pattern
   with a syntactic form becomes `rules/pattern.sh`, copied as `scripts/sensors/<rule-id>.sh` with `id=`
   set to the rule id (`references/catalog.md`, `adopted-patterns`). Edit only inside the
   `keel:repo-specific` markers. Render native architecture config with
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/render.sh" <archunit-java|archunit-kotlin|archunit-properties|depcruise|importlinter> .agents/rules/architecture.env`
   and write it where the user approved (e.g. `src/test/java/.../ArchitectureTest.java`,
   `src/test/resources/archunit.properties`, `.dependency-cruiser.cjs`, `.importlinter`). In
   brownfield the rendered ArchUnit rules are wrapped in `FreezingArchRule` (`FREEZE=1`), which keeps
   its store under `.agents/baselines/archunit/`. If the native architecture tool does not fit the
   fast budget together with the other fast sensors, move it to `scripts/sensors/slow/` and install
   `architecture-grep.sh` for the fast signal.
6. The baseline, written only with approval; `security` sensors never get one, keel never raises one.
   TSV sensors: `KEEL_MEASURE=1 bash scripts/sensors/<id>.sh > .agents/baselines/<id>.tsv`.
   A mandatory rule has no baseline: the same measurement becomes its `EXCEPTIONS` lines, one
   `<path> <YYYY-MM-DD>` per measured file, each with the deadline the user chose.
   Native architecture baselines, in brownfield:
   - ArchUnit: run the `ArchitectureTest` once; `FreezingArchRule` writes `.agents/baselines/archunit/`.
   - dependency-cruiser: `node_modules/.bin/depcruise-baseline src --config .dependency-cruiser.cjs --output-to .agents/baselines/depcruise-known-violations.json`.
   - import-linter: run `lint-imports`, copy each offending `importer -> imported` edge into
     `IGNORE_IMPORTS` in `architecture.env`, and re-render `.importlinter`.
7. Run `make gate-fast` and read it. A new rule must leave the gate green.

The slow gate (`make gate-slow`: mutation and diff coverage) is never run by the Stop hook and never
wired to CI; `AGENTS.md` tells agents to run it before opening a pull request. Integration and e2e
suites stay the project's own targets, cited in `AGENTS.md`. Profile L can add one optional, experimental (D52) slow sensor, `reviewer` (`slow/reviewer.sh`): a model call and tokens on every `make gate-slow`, through the user's own `REVIEWER_CMD`, with the diff sent to it. Offer it only when the user asks, with that cost stated; its `reviewer.env` and docs section follow `${CLAUDE_PLUGIN_ROOT}/contracts/profile-l.md`.

### Phase 8 - Plan

For each approved rule whose baseline is non-empty, write a migration plan
`.agents/plans/YYYY-MM-DD-<rule-id>.md` from `${CLAUDE_PLUGIN_ROOT}/contracts/plan.md` (`Status: active`, an
`## Acceptance` section in the sensor's numbers), run `${CLAUDE_PLUGIN_ROOT}/scripts/keel verify plan <file>` on it,
and record it as `PLAN=` in the rule's env file. Plans are committed, not ignored. Plans never go under `docs/`
and this skill never migrates anything itself.

## Output contract

Each approved rule leaves these artifacts, in these shapes:

- the proposal recorded by `keel plan rules`: every ADR, topic file, env file, sensor, baseline, generated tool config and plan, each with its path;
- an ADR in `<adr_dir>/` when there was a real trade-off (`adr-template.md`), naming by path every baseline it introduces and every env file it loosens;
- a section in its topic file, from `rule-section.md`, and its line in the right `AGENTS.md`: `- <statement> → docs/<topic>.md#<rule-id>`;
- `.agents/rules/<rule-id>.env` with the fields of `contracts/rule-env.md`, inferential rules included, and `ENFORCEMENT_LEVEL` where the user chose mandatory;
- a sensor, or `inferential` in the env file;
- a baseline that came from `KEEL_MEASURE=1` (or the native tool's own baseline command);
- a plan from `contracts/plan.md`, checked by `keel verify plan`, for every non-empty baseline.

## Discipline

**keel proposes, the human decides.** `${CLAUDE_PLUGIN_ROOT}/scripts/keel` enforces the order in code:
no write before `keel apply rules` exits 0.

| The excuse | Why it is wrong |
| --- | --- |
| "The team obviously wants hexagonal, I'll write the rule" | Norms are proposed with a justification and written only after the user approves them. Facts are discovered; norms are decided by the human. |
| "There is no data for this limit, I'll use a typical one and call it theirs" | Never present an invented rule as the project's. Say nothing can be inferred, give your recommendation and why, label opinion as opinion, and ask. |
| "While I'm here I'll fix the files that break the new rule" | This skill never migrates production code. An approved breaking change becomes a rule, a baseline, an ADR and a plan under `.agents/plans/`. |
| "The gate is red, so I'll raise the baseline a little" | keel never raises a baseline. `guard` accepts a new or grown baseline only when an ADR added in the same change names it, and `security` sensors never get one. |
| "The request said do not pause, so I'll skip plan and approve" | Acceptance given up front still goes through `keel plan`, `approve` and `apply`; the reply says the acceptance came from the request. |
| "Editing the accepted ADR is simpler than a new one" | Never edit an accepted ADR: supersede it. |
| "Plans are useful to the whole team, put them in `docs/`" | Plans never go under `docs/`: they live in `.agents/plans/`, versioned but transient (removed when done). |

## Done when

Run `${CLAUDE_PLUGIN_ROOT}/scripts/keel verify rules` (after the `make gate-fast` of phase 7, step 8). Fix every `fail`
line and run it again until it exits 0. It cannot check one thing: each approved rule has its line in the
right `AGENTS.md` and a sensor or `inferential`, and each baseline came from `KEEL_MEASURE=1`.
