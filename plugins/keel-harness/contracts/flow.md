# Flow contract

How each skill's phases run and how each rule in a skill is verified. Skills reach this file as
`${CLAUDE_PLUGIN_ROOT}/contracts/flow.md`.

## Phases

Filled in F2c-2: each phase of a skill, with its goal, the `scripts/keel` command that runs it, its
output and the question put to the human.

## Traceability

Filled in F2c-3: every `never` / `always` in a skill mapped to a test, a `keel verify` item or an eval
grader, classified by form (recipe / slot / discipline).
