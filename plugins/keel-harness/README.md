# keel-harness

Assess, install and maintain an AI-agent harness in a repository. This plugin provides a one-command bootstrap, minimal guides, a fast gate of deterministic sensors, and an output contract that turns each sensor's exit code into guidance an agent can act on.

## Skills

### `/keel-harness:assess`

Diagnoses how ready a repository is for AI coding agents.

- **Reads:** Stack markers, real scripts, configured sensors, `docs/`, directory structure
- **Writes:** Nothing

### `/keel-harness:build`

Installs an AI-agent harness in a repository.

- **Reads:** Repository structure, user confirmations
- **Writes:** `AGENTS.md`, pointer docs, `docs/` stubs, `Makefile`, `scripts/sensors/`, `.agents/state.yml`, gate hook

### `/keel-harness:doctor`

Checks whether an installed harness has drifted from the repository it guards.

- **Reads:** `.agents/state.yml` and current project state
- **Writes:** Nothing

## v0.1 Rule

**Informs, does not block.** The gate runs, reports failures and returns guidance. No action is barred, no commit is refused.

## Eval baseline

Run `claude plugin eval . --scaffold` from `plugins/keel-harness/` (each case runs 3 times per arm, with-plugin vs. no-plugin baseline).

- Date: 2026-09-19
- Claude Code version: 2.1.278

| Case | WITH | W-OUT | Δ |
| --- | --- | --- | --- |
| `assess-mature-repo` | 1.00 | 0.33 | +0.67 |
| `should-not-trigger` | 1.00 | 1.00 | 0.00 |

`assess-mature-repo`'s Δ is driven by `rubric-axes` and `rubric-states`: the no-plugin baseline never emits the six-axis table, so those two graders fail in the without arm while everything scores in the with arm. `should-not-trigger`'s Δ = 0 is the correct result — the skill correctly stays silent on an unrelated git question in both arms. Task 6 adds its cases to this table.
