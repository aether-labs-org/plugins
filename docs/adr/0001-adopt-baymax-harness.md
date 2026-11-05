# 0001. Adopt the Baymax harness

Status: accepted
Date: 2026-11-05

## Context and problem statement

The repository is a monorepo of Claude Code plugins with a long bash test suite (`make check`, about 220s) and no guides, gates
or hooks for coding agents. The owner wants agents to work here with checks that run without a person watching every step.

## Decision drivers

- The suite is too slow for every edit, so it can only be a pre-push check.
- Agent in use: Claude Code only.
- Commits are already conventional (89% of the last 100 subjects).
- Plugins are installed independently, so they must not depend on each other.

## Considered options

### Install the harness in layers, rules measured first (recommended)

- Good: every rule starts from what the code does today; nothing is imposed that was not confirmed.
- Bad: more questions up front.

### Write only the guides

- Good: fast.
- Bad: nothing checks that the guides are followed.

## Decision outcome

Chosen: the harness in layers: `bmax` pinned in `.agents/bmax.lock`, scripts and gates in `.agents/bmax.yml` (one root harness for
the three plugins), `AGENTS.md` as an index, the agent hooks in `.claude/settings.json`, native git hooks, and an independent
review that is always offered. Confirmed by Igor on 2026-11-05.

Choices inside it:

- `fast`: secrets (gitleaks), typecheck and lint of the Obsidian plugin, and plugin isolation.
- `.gitleaks.toml` allow-lists `.claude/worktrees/` only: gitleaks cannot read `.gitignore`, and the local worktrees hold
  test fixtures with fake secrets (10 findings before the allowlist, none in a versioned file). It is listed in the secrets
  script's `config:`, so any later change to it is a loosening that needs an ADR.
- Test fixtures that hold fake secrets on purpose (the bmax redaction tests and the gitleaks template test) carry a
  `gitleaks:allow` comment on each such line, not a file allowlist: a real secret on any other line is still found.
- `slow`: `make check` as exit code only (no JUnit report), and `merge-check`.
- Conventional commit messages enforced by `commit-message`; no PR template.
- No architecture, file-size, SCA, SAST or observability layers: no module boundaries were identifiable and nothing was proposed.

## Consequences

- Protected files change only when a human confirms the edit.
- A rule is loosened only by an ADR that names it; accepted ADRs are never edited.
- `sh .agents/bin/bmax check` reports when the harness drifts from the repository.
- Each clone runs `sh .agents/bin/bmax setup` once.

## Evidence

- Measured: `make check` passed 3 of 3 runs (221s, 218s, 220s); 0 cross-plugin references outside `evals/`; gitleaks installed; Node v25.0.0.
- Source: the Baymax harness v0.5 design
