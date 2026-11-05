---
name: harness
description: Create, review, update or assess the AI-agent harness of a repository, and make it agent-ready for Claude Code, GitHub Copilot CLI and Devin CLI. Diagnoses the repository, measures it, asks in rounds, and writes only what the human confirms, file by file - the pinned bmax engine and lock, .agents/bmax.yml (scripts and gates), AGENTS.md, rules and ADRs, git and agent hooks, memory and an independent review. Use when someone asks to set up or build a harness, assess agent readiness, add guardrails or quality gates, or define architecture, testing, conventions or Git rules for coding agents.
hooks:
  PreToolUse:
    - matcher: "Write|Edit|MultiEdit|NotebookEdit|Bash"
      hooks:
        - type: command
          command: 'sh "${CLAUDE_PLUGIN_ROOT}/bmax/bin/bmax" hook pre-tool-use --setup'
          timeout: 10
---

# harness

You help a team build, review and keep a harness: the guides, scripts, gates, hooks and memory that let coding agents work in a
repository without a person watching every step. The engine is `bmax`, pinned per repository; this skill only **authors**. Nothing
you do here runs at gate time, and the harness works without this plugin afterwards. Invoke it as `/baymax:harness`.

## Invariants (stated once; they apply to every phase)

1. **Nothing is written before the decisions.** Diagnose, measure and ask first. Then show one proposal block, then write.
2. **Rounds of at most 4 questions**, the recommended option first, each proposal with measured evidence and a cited source.
   Low confidence becomes a narrow question; no confidence means the layer is not installed, and you say why.
3. **What can be measured is measured by a script** (`bmax measure`, `scripts/measure.sh`), never estimated. "Not measured" is a
   valid answer; a guess is not.
4. **No inferential flow becomes a script.** A script never calls a model. Judgement lives in a guide or the review checklist.
5. **Every write is confirmed** by the human, one file at a time, through Write/Edit. Never write through the shell: the setup
   hook of this skill denies it, by design.
6. **Never commit, push or tag.** Never bump the `bmax` pin silently: copy the lock this plugin carries exactly.
7. **The agent never changes the harness alone.** Protected files change only with the human's confirmation.
   Protection is friction with evidence, not a security boundary; say so.
8. **The user chooses the tool.** Offer the recommended one and its alternatives; any tool that emits a supported format, or only
   an exit code, is accepted.

## First action

Before anything else run `sh "${CLAUDE_PLUGIN_ROOT}/bmax/bin/bmax" version`. It downloads and verifies the pinned `bmax` into the
per-user cache (once). Until `bmax` is cached, this skill's setup hook cannot decide anything and asks the human to confirm every
Write, Edit and Bash call, so run it first, and tell the human why if it asks about this call.

Read templates and references with the Read tool or `cat "<absolute path>"`; never `cd` into the plugin directory (or any other
directory outside the repository). The Bash working directory persists between calls, so a `cd` moves the whole session into
whatever repository that directory belongs to, and the repository hooks then see the wrong one.

## Pick the mode

Then run `bash "${CLAUDE_SKILL_DIR}/scripts/discover.sh"`; its `bmax` line decides.

- `bmax absent` (no `.agents/bmax.yml`): **create**.
- `bmax installed <version>`: **review or update**; also run `sh .agents/bin/bmax validate` and `sh .agents/bin/bmax check`, and
  explain their output. Propose a pin upgrade only when asked, from this plugin's `bmax/bmax.lock`.
- The user only wants a diagnosis: do phase 1 and stop. It writes nothing.

## Phases

1. **Diagnose (read-only).** Score each axis of the [rubric](references/rubric.md) with the file that proves it, or `not measured`,
   with estimated setup minutes and measured seconds added to the gate. No total score.
2. **Discover.** [Discovery](references/discovery.md): `discover.sh`, `bmax measure` for any metric that is also a gate, and
   `measure.sh` for proposal-only metrics (dependency matrix, directory shape, framework imports, test ratios, commit statistics).
3. **Rounds.** [Rounds](references/rounds.md): at most 4 questions each, over these areas, each with its catalog:
   tests ([catalog](references/catalog-tests.md)), code ([catalog](references/catalog-code.md)), architecture
   ([catalog](references/catalog-architecture.md)), security ([catalog](references/catalog-security.md)), observability
   ([catalog](references/catalog-observability.md)), the Git cycle ([catalog](references/catalog-git.md) and
   [git](references/git.md)), documentation and decisions ([catalog](references/catalog-docs.md)), the agents in use
   ([agents](references/agents.md)), review ([review](references/review.md)) and memory ([memory](references/memory.md)). The tools
   per stack are in [typescript](references/stack-typescript.md), [python](references/stack-python.md) and
   [jvm](references/stack-jvm.md): one row per topic with the command, the format, the pitfall and the recorded fixture (or
   `unverified`, which you must say when you propose it).
4. **Proposal block.** Every file to write or change, one line of reason each, in the write order. Wait for the answer.
5. **Writes, in this order, each confirmed:** the wrapper and the lock; `.agents/bmax.yml` ([gates](references/gates.md));
   native tool configs; baselines (`bmax measure` output); guides (`AGENTS.md`, `CLAUDE.md`, topic files); ADRs; the review files
   and `docs/review.md`; the PR template if adopted; the git hooks; `.gitignore`; and `.claude/settings.json` **last**.
   Details and the template for each file are in [rounds](references/rounds.md); what is protected, and what to say when a write is
   asked or denied, is in [protection](references/protection.md).
6. **Verify.** [Verify](references/verify.md): `bmax validate`, `bmax check`, `bmax gate fast --all`, optionally `bmax gate slow --all`.
   Report every result as measured.
7. **Hand off.** Tell the human to review and commit, to run `sh .agents/bin/bmax setup` once per clone (it makes the git hooks
   executable and sets `core.hooksPath`: never chmod them yourself), and to open a new session.

## Stop conditions

- The repository is not a git repository: say so and stop; the harness needs one.
- `bmax validate` fails after your writes: fix the file you wrote, do not weaken the validation.
- A gate fails on the first run: report it as a finding of the repository; do not edit a threshold, a baseline or a test to
  make it green (that is a loosening and needs an ADR).
- The human declines a layer: record it as declined and move on. Nothing is installed against a "no".
- Something would need a network, a paid service or a secret you do not have: say so and ask.

## Files this skill ships

- Templates for everything it writes: `${CLAUDE_SKILL_DIR}/templates/` (listed in [rounds](references/rounds.md)).
- Read-only scripts: `${CLAUDE_SKILL_DIR}/scripts/discover.sh`, `${CLAUDE_SKILL_DIR}/scripts/measure.sh`.
- The wrapper and lock to install: `${CLAUDE_PLUGIN_ROOT}/bmax/bin/bmax` and `${CLAUDE_PLUGIN_ROOT}/bmax/bmax.lock`.
