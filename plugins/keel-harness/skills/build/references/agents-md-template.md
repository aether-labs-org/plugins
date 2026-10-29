# AGENTS.md template v2 (100 lines)

Fill the template below with **real, confirmed** values from repository discovery. Omit any section
for which nothing was found. Use `→ docs/X.md` for anything needing more than one sentence. The
whole file, and every nested `AGENTS.md`, stays at **100 lines** or fewer.

What stays out, on purpose: file maps, docs indexes, architecture overviews, metrics and schema
lists. Repository overviews do not help an agent; commands it cannot guess and non-standard
conventions do (`context-engineering.md`, evidence section).

Sections, in this order. Each is omitted when empty:

1. the header and a one-line identity;
2. `## Commands`: purpose, command, pass signal;
3. `## Before you finish`: the exact copy below, unchanged;
4. `## Rules`: one line per rule, each pointing at `docs/<topic>.md#<id>` (filled by the `rules` skill);
5. `## Decisions`: a pointer to the ADR folder (`adr_dir` in `.agents/state.yml`) when ADRs exist, and
   always the progress pointer (`build` creates `.agents/progress.md`);
6. `## Reading tool output`: at most 4 bullets.

---

```markdown
# AGENTS.md — {{project}}
{{One line: what this is, stack, package manager.}} Last updated: {{YYYY-MM-DD}}.

## Commands
| Purpose | Command | Pass signal |
| --- | --- | --- |
| Install and build | `make bootstrap` | {{exit 0}} |
| Fast gate | `make gate-fast` | `gate: fast - PASSED` |
| Slow gate | `make gate-slow` | `gate: slow - PASSED` |
| {{Tests / run / other real command}} | `{{command}}` | {{signal}} |

## Before you finish
Run `make gate-fast` and read it before you say you are done:
- Line 1 of each sensor is `id  class  status  summary`; fix every `fail`, top to bottom.
- Follow the `guidance:` block under a failure; it says what to do here and what not to do.
- Never edit a test, `.agents/baselines/` or `.agents/state.yml` to make the gate pass.
Before opening a pull request, also run `make gate-slow`.

## Rules
- {{rule statement, one verifiable sentence}} → docs/{{topic}}.md#{{id}}

## Decisions
Why things are the way they are → {{adr_dir}}/
Progress across sessions → .agents/progress.md

## Reading tool output
- The first error in a chain is the root cause; the rest cascade. Fix top-down.
- {{One stack-specific tip, e.g. the log format or where test output lands.}}
```

## CLAUDE.md bridge

Claude Code reads `AGENTS.md` only when no `CLAUDE.md`, `.claude/CLAUDE.md` or `CLAUDE.local.md`
exists; a `CLAUDE.md` that imports it is the documented bridge. `build` therefore always ensures it:

- Neither `CLAUDE.md` nor `.claude/CLAUDE.md` exists: create `CLAUDE.md` containing exactly `@AGENTS.md`.
- One exists without that line: propose inserting `@AGENTS.md` as its first line, as its own
  question in a round. Do not touch the rest of the file.
