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
code: an approved breaking change becomes a rule, a baseline, an ADR and a local plan.

Reference files live next to this one: `references/catalog.md` (the entries and their sources),
`interview.md`, `adr-template.md`, `rule-section.md`, `rule-env.md`, `plan-template.md`,
`nested-agents-md-template.md` and `topics/`. Read the catalog entry before proposing its rule.

## 0. Precondition

Rule sensors run inside the gates, so this skill needs `scripts/gate.sh`, `scripts/lib/baseline.sh`,
`scripts/lib/envparse.sh`, `scripts/sensors/guard.sh` and the Makefile targets `gate-fast` and `gate-slow`. If any is missing, offer to run
`/keel-harness:build` first (in greenfield, build installs the runner even when no tool sensor can
run yet; a gate with zero sensors is valid). Continue only when the user agrees or they exist.

## 1. Context interview

One round before any measurement, in at most 4 questions, from `references/interview.md`. Record the
answers in `docs/decisions/0001-agent-harness-context.md` (the first ADR, `adr-template.md`) and let
them steer every proposal.

## 2. Mode

Classify the repository: **greenfield** (no tracked source files in the stack's source roots) or
**brownfield**. State the evidence and ask the user to confirm; store it as `mode:` in
`.agents/state.yml`. Greenfield skips step 4, proposes from the catalog and the interview, and
starts every baseline empty.

## 3. Inventory

Read every instruction file the target agents load: `AGENTS.md` (root and nested), `CLAUDE.md`,
`.claude/CLAUDE.md`, `.claude/rules/`, `.github/copilot-instructions.md`, `.github/instructions/`,
`.devin/rules/`, `.cursor/rules/`; plus `docs/`, lint and architecture tool configs, test layout and
existing ADRs. Existing rules are respected, not duplicated.

## 4. Reverse engineering (brownfield)

For each catalog entry, measure the as-is state and report it before proposing anything. The
measurements are read-only and run from the plugin:

```bash
bash "${CLAUDE_SKILL_DIR}/assets/measure.sh" file-size src    # pathspecs keep lockfiles and vendored files out
bash "${CLAUDE_SKILL_DIR}/assets/measure.sh" tree 2
bash "${CLAUDE_SKILL_DIR}/assets/measure.sh" imports java com.acme      # also kotlin, python, ts <src_root>
bash "${CLAUDE_SKILL_DIR}/assets/measure.sh" framework-imports src/main/java/com/acme/domain
bash "${CLAUDE_SKILL_DIR}/assets/measure.sh" tests
bash "${CLAUDE_SKILL_DIR}/assets/measure.sh" language pt.txt
```

## 5. Proposals

For each entry, propose a rule with two kinds of justification: **repository data** ("p90 = 240
lines; 12 files over 500") and an **external source** from the catalog. Label opinion as opinion,
flag breaking proposals and state their blast radius (files affected). You may propose a tool
(ArchUnit, dependency-cruiser, import-linter, PIT, Stryker, mutmut); install it only with approval.
When nothing can be inferred, say so, give your recommendation and why, and ask. Never present an
invented rule as the project's.

## 6. Rounds

Approve, amend or reject proposals in rounds of at most 4 questions each, the recommended option
first, each option with its trade-off. Use `AskUserQuestion` when it is available. When it is not,
ask in plain text; when the user's own request pre-authorised proceeding, take the recommended
option of each question and say so. Group by topic: architecture, then testing, then conventions.

## 7. Write

Write only what was approved, in this order:

1. The ADR in `docs/decisions/`, when the round had a real trade-off, the rule is breaking, or the
   user overrode your recommendation (`adr-template.md`). Never edit an accepted ADR: supersede it.
   The ADR names, by path, every baseline it introduces and every env file it loosens: `guard` accepts
   a new or grown baseline, or a relaxed limit, only when an ADR added in the same change names it.
2. The rule's section in its **topic file**, from `rule-section.md`: `docs/architecture.md` holds
   `architecture` and `folder-layout`; `docs/conventions.md` holds `file-size`, `code-language`,
   `adopted-patterns` and other code conventions; `docs/testing.md` holds `testing-strategy`. Create
   a missing topic file from `references/topics/`. A topic file stays at or under 300 lines; past
   that, propose splitting it by subtopic.
3. The rule's line in the right `AGENTS.md` (`nested-agents-md-template.md` for directory rules):
   `- <statement> → docs/<topic>.md#<rule-id>`. Files stay at 100 lines or fewer.
4. `.agents/rules/<rule-id>.env` from `rule-env.md`: the metadata (`origin:` discovered | proposed |
   user is `ORIGIN=`; `decision:` is `DECISION=`; also `RULE_ID KIND APPROVED_AT ENFORCEMENT DOC
   PLAN`) and the parameters. Every rule has one, inferential ones included.
5. The sensors and generated tool config. Copy sensors from `${CLAUDE_SKILL_DIR}/assets/sensors/`
   to `scripts/sensors/<id>.sh`; the slow ones (`slow/mutation.sh`, `slow/diff-coverage.sh`) to
   `scripts/sensors/slow/`; the stop-list to `scripts/sensors/stoplists/`. Edit only inside the
   `keel:repo-specific` markers. Render native architecture config with
   `bash "${CLAUDE_SKILL_DIR}/assets/architecture/render.sh" <archunit-java|archunit-kotlin|archunit-properties|depcruise|importlinter> .agents/rules/architecture.env`
   and write it where the user approved (e.g. `src/test/java/.../ArchitectureTest.java`,
   `src/test/resources/archunit.properties`, `.dependency-cruiser.cjs`, `.importlinter`). In
   brownfield the rendered ArchUnit rules are wrapped in `FreezingArchRule` (`FREEZE=1`), which keeps
   its store under `.agents/baselines/archunit/`. If the native architecture tool does not fit the
   fast budget together with the other fast sensors, move it to `scripts/sensors/slow/` and install
   `architecture-grep.sh` for the fast signal.
6. The baseline, written only with approval; `security` sensors never get one, keel never raises one.
   TSV sensors: `KEEL_MEASURE=1 bash scripts/sensors/<id>.sh > .agents/baselines/<id>.tsv`.
   Native architecture baselines, in brownfield:
   - ArchUnit: run the `ArchitectureTest` once; `FreezingArchRule` writes `.agents/baselines/archunit/`.
   - dependency-cruiser: `node_modules/.bin/depcruise-baseline src --config .dependency-cruiser.cjs --output-to .agents/baselines/depcruise-known-violations.json`.
   - import-linter: run `lint-imports`, copy each offending `importer -> imported` edge into
     `IGNORE_IMPORTS` in `architecture.env`, and re-render `.importlinter`.
7. `.agents/plans/` in `.gitignore` (with the other generated state files).
8. Run `make gate-fast` and read it. A new rule must leave the gate green.

The slow gate (`make gate-slow`: mutation and diff coverage) is never run by the Stop hook and never
wired to CI; `AGENTS.md` tells agents to run it before opening a pull request. Integration and e2e
suites stay the project's own targets, cited in `AGENTS.md`.

## 8. Plan

For each approved rule whose baseline is non-empty, write a local migration plan
`.agents/plans/YYYY-MM-DD-<rule-id>.md` from `plan-template.md`, with acceptance criteria in the
sensor's numbers, and record it as `PLAN=` in the rule's env file. Plans never go under `docs/`
(they are gitignored) and this skill never migrates anything itself.

## Done when

- [ ] Every approved rule has its section (with `<a id>` anchor), env file, `AGENTS.md` line and sensor or `inferential`.
- [ ] Every number in a section matches its env file; `make harness-check` reports no warning.
- [ ] `make gate-fast` was run and read; baselines came from `KEEL_MEASURE=1`.
- [ ] Nothing was written that the user did not approve.
