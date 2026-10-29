# Enforcement: the same gate in pre-commit and CI

The Stop hook reaches only Claude Code. Pre-commit and CI run the **same** `make gate-fast` for every
author, human or agent, and CI is the one a local `--no-verify` cannot skip. Each is its own layer in
the proposal (`ci`, `precommit` in `.agents/state.yml`), accepted or declined on its own.

## CI (`ci` layer)

- Copy `${CLAUDE_PLUGIN_ROOT}/assets/core/ci/keel.yml` to `.github/workflows/keel.yml`. Edit only its
  repo-specific block: the toolchain setup steps, copied from the repository's existing workflows
  (`actions/setup-node`, `actions/setup-python`, `actions/setup-java` with the versions they pin).
  No existing workflow and a toolchain to set up → confidence `low`: ask which versions.
- Never edit the gate step, the `KEEL_GUARD_BASE` line or `fetch-depth: 0`: without them `guard`
  compares the pull request with itself and passes every loosening.
- `make harness-check` stays advisory in CI (its `review-due` warning is date-driven).
- CI checks the whole repository (a clean checkout has no `SCOPE`), so it runs every test the local
  gate would skip as unaffected. The slow gate stays local: `make gate-slow` before a pull request.
- Not GitHub (`.gitlab-ci.yml`, `Jenkinsfile`, ...): propose one job with the same three commands
  (`make bootstrap`, `KEEL_GUARD_BASE=<target branch> make gate-fast`, `make harness-check || true`)
  in that system's file, and say it is untested by keel.
- Tell the user to make the `keel` check required in the branch protection; keel cannot set it.
  When any rule is mandatory (`ENFORCEMENT_LEVEL=mandatory`, `contracts/rule-env.md`) say so as a requirement
  and not as advice: a superseding ADR is approved through CODEOWNERS plus that required check, and without
  both the approval is only a convention. keel cannot check either locally.

## Pre-commit (`precommit` layer)

Propose the hook manager the repository already uses, never a new one:

| Found | Asset | Merge |
| --- | --- | --- |
| `lefthook.yml` / `.lefthook.yml` | `assets/core/precommit/lefthook.yml` | add the `keel-gate` command under `pre-commit.commands` |
| `.pre-commit-config.yaml` | `assets/core/precommit/pre-commit-config.yaml` | append the `local` repo entry to `repos` |
| `.husky/` | `assets/core/precommit/husky-pre-commit` | append `make gate-fast` to `.husky/pre-commit` |
| none | — | declined: `not_installed: { precommit: "no hook manager in this repository" }` |

Keep every existing entry. The fast gate's budget (`CEILING_SECONDS`) is what a commit waits for; a
budget over 30 s is a reason to decline this layer, and the user decides.

## Verify

- `make harness-check` reports no `enforcement-drift`.
- `.github/workflows/keel.yml` parses as YAML; its gate step is unchanged from the asset.
