# The context interview

One round, before any measurement, in **at most 4 questions**. Use `AskUserQuestion` when it is
available: recommended option first, each option with its trade-off, plus a free answer. In a
non-interactive run, ask in plain text; when the user's request pre-authorised proceeding, take the
recommended option of each question and say so.

The answers are recorded in `<adr_dir>/0001-agent-harness-context.md` (the first ADR, from
`adr-template.md`) and steer every later proposal. Do not interrogate: if the repository already
answers a question, state what you found and ask only for confirmation.

| # | Question | Options (recommended first) |
| --- | --- | --- |
| 1 | What do you want agents to do here, and what do they get wrong today? | Fix the recurring mistakes you name; keep agents inside the current structure; free answer |
| 2 | Which constraints bind this repository (deadlines, compliance, legacy, team size)? | None that limit tooling; a hard deadline (prefer baselines over refactors); compliance or audit needs (prefer sensors that never pass silently); free answer |
| 3 | Which agents does the team use? | Claude Code only (Stop hook active); Claude Code plus Copilot or Devin (they get `AGENTS.md` only); free answer |
| 4 | How much appetite is there for breaking changes? | Propose improvements, and baseline what exists, with a local migration plan (recommended); only record what the code does today; propose breaking changes freely |

After the answers, restate in two lines what will steer the proposals, and ask the user to correct it.
