# Review

The single copy of who reviews, when, and the checklist. The reviewer definition
(`.claude/agents/keel-reviewer.md`) points here and says nothing else.

## Who

- The `keel-reviewer` subagent (fresh context, read-only), or a named person.

## When

- Before finishing a task: the agent asks the human whether to run the review, every time.
- Before opening the pull request.

## Checklist

Apply each item to the diff. Report an item only when it fails; say what you did not check.

1. Does the change do what the plan's `## Acceptance` says, and nothing outside its `Scope`?
2. Is every behaviour change covered by a test that fails without the change (a regression test for a fix)?
3. Does it follow the rules in the guides (`docs/architecture.md`), including the rules no tool enforces?
4. Does it loosen the harness (config, baselines, thresholds, hooks, guides, ADRs)? That needs an ADR naming what it loosens.
5. Are there new dependencies, secrets, absolute paths, or local evidence references in anything committed?
6. Are errors handled the way the repository does it, with no swallowed exception and no stray console output?
7. Is anything left behind: dead code, a TODO without a reference, a debug statement, a commented-out block?
8. Does a changed plugin still work installed on its own, with no reference to another plugin and with `make validate` passing?
