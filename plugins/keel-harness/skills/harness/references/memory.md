# Memory

What persists between sessions, who writes it, and how `kh` checks it. `kh` never writes memory; the agent writes, `kh` checks
(the `memory` builtin in the `commit` gate, and `kh check`). `sh .agents/bin/kh schema memory` prints the fields.

| Artifact | Where | Versioned | Written by | Lifecycle | Checked by |
| --- | --- | --- | --- | --- | --- |
| ADRs | `adr_dir` | yes, protected | agent proposes, human confirms | accepted is immutable; changed only by a superseding ADR | `guard` |
| Active plans | `.agents/plans/<slug>.md` | yes | agent | created for multi-step tasks; **deleted at close** | `memory`, `kh check` (`plan-stale` after 14 days) |
| Task history | `.agents/progress.md` | yes | agent, at close | one line per closed task | `memory`, `kh check` (`progress-size` over 200 lines) |
| Triaged lessons | `.agents/lessons.md` | yes | agent proposes at close, human confirms | Problem, Solution, Destination | `memory` |
| Raw lessons inbox | `.agents/run/lessons-inbox.md` | no | agent | emptied when triaged | none |
| Handoff notes | `.agents/run/handoff.md` | no | agent | per session | none |
| Evidence, gate history | `.agents/run/runs/` | no | `kh` | 50 runs or 200 MB | none |

## Exact formats

**Plan** (`templates/plan.md`): line 1 `# <title>`; a line `Status: active`; a line `Scope: <glob>[, <glob>...]` (not empty); a heading
`## Acceptance` followed by at least one `- [ ]` or `- [x]` item; optional `## Notes`. The `scope` builtin reports changed files
outside every active plan's `Scope` (ignoring `.agents/plans/`, `progress.md`, `lessons.md`).

**Progress** (`templates/progress.md`): an optional `# Progress` heading, then lines
`- YYYY-MM-DD <slug>: done|partial|abandoned — <one line>` (an em dash; an ADR may be cited at the end as `[ADR NNNN]`).

**Lessons** (`templates/lessons.md`): entries that start `## YYYY-MM-DD <title>` and contain the lines `Problem: ...`,
`Solution: ...` and `Destination: rule <id> | ADR NNNN | guide <path> | none`.

## Never in versioned memory

Absolute user paths (`/home/<user>`, `/Users/<user>`), references to `.agents/run/` or to run ids (`YYYYMMDD-HHMMSS-xxxx`), and
anything that looks like a secret (the redaction set: tokens, keys, private-key headers). The `memory` builtin fails on them.
Commit only what another person needs; when unsure whether something is shareable, ask the human.

## At the close of a task

1. Gates green. 2. Ask the human whether to run the independent review ([review](review.md)). 3. Delete the plan and append one
progress line. 4. Propose lessons worth keeping (Problem, Solution, Destination) and write the ones the human confirms into
`.agents/lessons.md`; the rest stay in the local inbox. 5. When measured counts fell below a baseline (`kh check` says
`baseline-stale`), propose the `kh measure` output as the new baseline; it is a protected write.
