# Independent review

A fresh-context reviewer, always offered, never run silently, never a script that calls a model.

## The pieces

- `docs/review.md` (`templates/review.md`): who reviews (the `keel-reviewer` subagent, a named person, or another CLI the team
  names), when (before finishing a task, before the PR), and the checklist. It is the **single copy** of the checklist.
- Two thin definitions with the same text: `.claude/agents/keel-reviewer.md` (Claude Code; Devin imports `.claude/` subagents)
  and `.github/agents/keel-reviewer.agent.md` (Copilot CLI loads agent profiles from `.github/agents`). Each says: fresh context,
  read-only use of the shell (git diff, log, show, status), apply `docs/review.md` to the diff, report findings, change
  nothing. They do not repeat the checklist.
- `AGENTS.md` "Before you finish": always ask the human whether to run the independent review.

All three files are protected (reviewer definitions as agent configuration, `docs/review.md` as a guide), so a change to the
checklist is a confirmed edit.

## Writing `docs/review.md` with the human

Start from the template checklist and keep the items that apply. Add the project's own items that no tool checks: a domain rule,
a security expectation, a convention that lives only in people's heads. Ask in a round; low confidence becomes a narrow
question. Delete items nobody will check.

## Limits to say out loud

- The read-only guarantee of the reviewer is textual (its instructions and, in Claude Code, its tool list), not an enforced
  sandbox: the Bash tool is available to it so that it can read the diff.
- The review is only as good as the checklist. It complements `guard` and the gates, it does not replace them.
- No effect evaluation was run: whether a reviewer improves outcomes in this repository is unmeasured.
