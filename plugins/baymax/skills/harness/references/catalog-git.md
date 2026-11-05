# Catalog - Git cycle

Commit and branch conventions, the pull request template, the scope of a change and conflicts with the upstream. These are builtins and templates, proposed after reading the history.

Each topic is a section with the same six labels: **Questions** (what to ask), **Measure** (how to read the as-is state), **Default** (how the proposal is derived), **Why** (the reason and its source), **Class and gate** (what enforces it and where), **Opinion** (where the default is judgement). Brownfield: derive the default from the measured distribution (the next round number at or above p90 and not below p75) and say so; greenfield: use the catalog default and say so. The tools per stack are in `stack-typescript.md`, `stack-python.md` and `stack-jvm.md`, one row per topic id. After setup the project's `.agents/bmax.yml` is the truth, not this catalog.

## commit-convention

**Questions**: Do commit messages follow a convention today? Which one?
**Measure**: `scripts/discover.sh` prints `commit-convention` from the last 100 subjects; `scripts/measure.sh commits` gives the shape of the last 200.
**Default**: Adopt the convention the history already shows (usually Conventional Commits) and enforce it with the `commit-message` builtin from the commit-msg git hook. If the history shows none, propose Conventional Commits and say it is a choice.
**Why**: Conventional Commits give messages a machine-readable shape (https://www.conventionalcommits.org/en/v1.0.0/). The hook rejects a non-matching message before the commit exists.
**Class and gate**: correctness; commit-msg hook (builtin commit-message)
**Opinion**: Whether to enforce a convention, and which.

## branch-naming

**Questions**: Do branches follow a naming pattern today?
**Measure**: `scripts/discover.sh` prints `branch-pattern` with the prefixes seen and their counts.
**Default**: The prefixes the repository already uses (`feat/`, `fix/`, `chore/`), checked by the `branch-name` builtin in the slow gate.
**Why**: A predictable branch name routes work and tooling; checking it at push time costs nothing. It is a convention, not a measured benefit.
**Class and gate**: heuristic; slow gate (builtin branch-name)
**Opinion**: Whether to enforce it; trunk-based teams may not use prefixes.

## pr-template

**Questions**: Is there a pull request template? Do reviewers ask for the same things each time?
**Measure**: Look for `.github/pull_request_template.md` and the review comments that repeat.
**Default**: A template with the plan's Acceptance checklist and the pasted gate verdict lines (`templates/pull_request_template.md`). Opt-in.
**Why**: A template puts the checks the author owns where the reviewer reads them (https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/creating-a-pull-request-template-for-your-repository).
**Class and gate**: none; the file is protected and listed in `guides:` through `docs/review.md`
**Opinion**: Whether the team wants a template at all.

## scope

**Questions**: Do agents change files outside the task? Are plans written for multi-step work?
**Measure**: `git diff --stat` against the plan's `Scope`; the builtin reports the files outside it.
**Default**: The `scope` builtin in the fast gate: changed files must match the `Scope:` of an active plan; with no active plan it skips.
**Why**: A change that spreads beyond its task is harder to review and revert; the plan's `Scope` states the intent so a script can check it. It is a heuristic: a legitimate change can touch a file nobody listed.
**Class and gate**: heuristic; fast gate (builtin scope)
**Opinion**: How tightly `Scope` is drawn.

## merge-check

**Questions**: How often does a branch conflict with the upstream when it is finally pushed?
**Measure**: The builtin reports conflicting files and "N commits behind <upstream>".
**Default**: The `merge-check` builtin in the slow gate (needs git 2.38 or newer; it skips on older git).
**Why**: `git merge-tree --write-tree` computes a merge without touching the work tree (https://git-scm.com/docs/git-merge-tree), so a conflict is found before the push.
**Class and gate**: correctness; slow gate (builtin merge-check)
**Opinion**: Whether to rebase or merge, which is the team's workflow.
