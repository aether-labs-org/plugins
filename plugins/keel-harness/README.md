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
