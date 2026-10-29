# Learnings contract — `.agents/run/learnings/`

The lessons inbox (spec D41, C9). When a review comment or a repeated failure teaches something the
harness should have told the agent, it is written down here. It is a staging area: nothing here is a
rule, a sensor or a decision until the user approves a promotion. Skills reach this file as
`${CLAUDE_PLUGIN_ROOT}/contracts/learnings.md`; the installed scripts never do.

## Where and what

One Markdown file per lesson: `.agents/run/learnings/YYYY-MM-DD-<slug>.md`. `<slug>` is lowercase
letters, digits and hyphens. The folder is under `.agents/run/`, so it is git-ignored and local to one
machine, like the rest of the run state. Delete the folder to reset.

```
Source: review comment on PR 42 - "use the repository's Money type"
Seen: 2
Proposed: rule

Free text: what happened, and what would have prevented it.
```

| Header | Value |
| --- | --- |
| `Source:` | Where the lesson came from: a session, a review comment (quote it) or a gate failure (sensor id) |
| `Seen:` | How many times it came up, an integer of at least 1. Whoever sees it again raises the number instead of writing a second file |
| `Proposed:` | The route the writer thinks fits: `rule` (an `AGENTS.md` line and a `docs/` section, possibly with a sensor), `sensor`, `adr` (a decision to record) or `discard` |

The three headers are the first three lines. Everything after the blank line is free text.

## Who writes

- **Any agent**, by hand, when a review comment or a repeated failure teaches something
  (`.agents/README.md` tells it to).
- **The Stop hook** (`scripts/hooks/claude-stop.sh`), automatically, when the same sensor fails in
  three sessions in a row. It writes `<date>-sensor-<id>-fails-every-session.md` with `Proposed: rule`, the
  sensor's guidance in the body, and raises `Seen:` when a later session fails again. The hook counts
  sessions by the `session_id` Claude Code passes it; a sensor that passes at any gate run starts over.
  Writing a lesson is best effort: it never changes what the hook says or its exit code.

## Who promotes

Only the user. `/keel-harness:assess` lists the items and proposes, per item, the route:
`/keel-harness:rules` for a rule or a sensor, an ADR in `adr_dir`, or discard. It writes nothing: no
lesson is created, edited, promoted or deleted by `assess`. After the user approves, `rules` makes the
change through its own proposal and approval, and the user deletes the lesson.
