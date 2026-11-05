# The Git cycle

Local authority only: the git hooks and the agent hooks. There is no generated CI and no server-side gate; a team that wants one can
wire `bmax gate` into its own CI, unsupported by Baymax.

## Hooks

| Hook | Runs | Needs |
| --- | --- | --- |
| pre-commit | `bmax gate commit` on the staged files (`guard`, secrets, `memory`, lint) | `githooks.pre-commit: commit` |
| commit-msg | `bmax hook commit-msg <file>` runs the `commit-message` script: exit 1 with the pattern when the first line does not match | `githooks.commit-msg: <script id>` |
| pre-push | `bmax gate slow` on the branch (tests, `merge-check`) | `githooks.pre-push: slow` |

`githooks.mode`:

- `native`: the scripts are in `.agents/githooks/` (`templates/githooks/`), and `sh .agents/bin/bmax setup` points `core.hooksPath` at
  that directory and makes them executable. `core.hooksPath` is local git configuration, so every clone runs `bmax setup` once; until
  then `bmax check` reports `githooks-inactive`.
- `external`: the project's own manager (husky, lefthook, pre-commit) calls the same wrapper commands; `bmax check` verifies that a
  manager config contains `.agents/bin/bmax`. `bmax setup` only prints which command goes where.

Every entry point invokes the wrapper through `sh`, so no file depends on an exec bit surviving a Write.

## Conventions to propose, after reading the history

- **Commit messages**: `scripts/discover.sh` reports `commit-convention` (Conventional Commits share of the last 100 subjects) and
  `scripts/measure.sh commits` the shape of the last 200. Propose the convention the history shows; if none, say that Conventional
  Commits is a choice. Enforce it with the `commit-message` builtin (`with.pattern` is a Go regular expression matched against
  the first non-comment line; merge and revert messages need a pattern that allows them).
- **Branch names**: `discover.sh` prints the prefixes in use. The `branch-name` builtin (slow gate) checks the current branch; it
  skips on a detached HEAD.
- **PR template**: `templates/pull_request_template.md` (Acceptance and the pasted gate verdict lines). Opt-in.
- **Scope**: the `scope` builtin (fast gate) checks changed files against the active plan's `Scope`; no active plan means a skip.
- **Conflicts**: the `merge-check` builtin (slow gate) uses `git merge-tree --write-tree` (git 2.38 or newer; it skips on older
  git) and says how many commits behind the upstream the branch is.

## Rules for the agent

Never `--no-verify`, never change `core.hooksPath`, never rewrite the history of a shared branch, never commit without being asked.
The skill itself never commits: it tells the human to review and commit, and to run `sh .agents/bin/bmax setup`.
