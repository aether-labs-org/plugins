# The lessons inbox in a health check

Spec D41 and C9. The format, the writers and the rule that only the user promotes are in
`${CLAUDE_PLUGIN_ROOT}/contracts/learnings.md`. This page is how `assess` reads the inbox and what it
proposes. `assess` only reads and reports: it creates, edits, promotes and deletes no lesson.

## Reading

List `.agents/run/learnings/*.md` with `ls` and read each file with `cat` or `head`. Say nothing when the
folder is absent or empty: an empty inbox is a valid answer.

For each file take the three headers from its first three lines (`Source:`, `Seen:`, `Proposed:`) and the
date from the file name. A file without the three headers, or whose `Proposed:` is none of `rule`,
`sensor`, `adr`, `discard`, is **malformed**: list it with that reason and propose that the user fix or
delete it. Do not guess its meaning.

## Proposing a route

One row per lesson, the route being a proposal the user approves or rejects. The writer's `Proposed:` is a
starting point, not an instruction.

| The lesson | Propose |
| --- | --- |
| It names a convention an agent can follow, and `Seen:` is 2 or more (or `Proposed: rule`) | `/keel-harness:rules`: an `AGENTS.md` line, a `docs/` section and, where the rule is checkable, a sensor |
| It names something a script can check (`Proposed: sensor`) | `/keel-harness:rules`, which proposes the sensor with its baseline and a rule env file |
| It records a trade-off or a reason someone will ask about later (`Proposed: adr`) | an ADR in `adr_dir`, written by hand or through `/keel-harness:rules` |
| It is a sensor that keeps failing (`<date>-sensor-<id>-fails-every-session.md`) and a rule names that sensor | `/keel-harness:rules`: sharpen that rule's `AGENTS.md` line and `docs/` section, or add an exemplar; no new rule |
| `Seen: 1`, the date is more than 30 days old and nothing else points at it, or `Proposed: discard` | discard: the user deletes the file |

State how many lessons were read and how many are malformed. Never apply a route: the user runs
`/keel-harness:rules` or writes the ADR, and deletes the lesson afterwards.
