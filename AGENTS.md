# AGENTS.md - aether-labs plugins

Monorepo of Claude Code plugins: `plugins/keel-harness`, `plugins/second-brain` (with an Obsidian plugin in TypeScript under
`obsidian/`) and `plugins/solutions-architect`. Bash test suite in `tests/`, Python helpers, npm for the Obsidian plugin only.

## Setup

Once per clone: `sh .agents/bin/kh setup` (fetches the pinned `kh`, activates the git hooks, reports drift).

## Commands

| Purpose | Command |
| --- | --- |
| A declared script | `sh .agents/bin/kh run <script>` (the scripts are in `.agents/keel.yml`) |
| Fast gate, before you stop | `sh .agents/bin/kh gate fast` |
| Slow gate, before a push | `sh .agents/bin/kh gate slow` |
| An undeclared command, with evidence | `sh .agents/bin/kh run -- <command>` |
| Whole test suite (about 220s, exit code only) | `make check` |
| Validate the three plugin manifests (needs the `claude` CLI) | `make validate` |

Do not pipe the output of `kh`: it is already reduced. The rest of any run: `sh .agents/bin/kh show <id> [--failures | --full]`.
A declared tool called directly (for example `make check` when `suite` is a script) is denied with the `kh run` to use.
Do not run `make check` after every edit: it belongs to the slow gate.

## Working

- A task with several steps gets a plan in `.agents/plans/<slug>.md`: `# <title>`, `Status: active`,
  `Scope: <globs>`, and a `## Acceptance` checklist. Change files outside its `Scope` only after updating it.
- Fix the cause of a failing check. Never edit a test expectation, a baseline or a threshold to make a gate pass.
- Notes for yourself between sessions go in `.agents/run/handoff.md` (local, never committed).
- Commits are conventional (`feat|fix|docs|refactor|test|chore|perf|build|ci|style|revert`, optional scope); branches are
  `feat/*`, `docs/*` or `claude/*`, merged through pull requests.
- A plugin never references another plugin (`docs/architecture.md`); each one must work installed on its own.

## Boundaries

- Protected files (`.agents/keel.yml`, `.agents/keel.lock`, `.agents/bin/`, `.agents/baselines/`, `.agents/githooks/`, agent
  settings, the guides listed in `keel.yml`, `docs/review.md`, ADRs) are changed only when the human confirms the edit:
  explain the change you want and why, and let them confirm or make it. Do not edit them through the shell.
- Never use `git commit --no-verify`, change `core.hooksPath`, or set `KH_BINARY` or `KH_RELEASE_URL` yourself.
- This protection is friction with evidence, not a security boundary.

## Before you finish

1. Run `sh .agents/bin/kh gate fast`; read every failure and fix it. Run the slow gate before a push.
2. Ask the human whether to run the independent review (`docs/review.md`).
3. Close the plan: delete `.agents/plans/<slug>.md` and add one line to `.agents/progress.md`:
   `- YYYY-MM-DD <slug>: done|partial|abandoned — <one line>`.
4. Propose lessons worth keeping to the human; the triaged ones go in `.agents/lessons.md`.

## Pointers

- Plugin isolation rule -> `docs/architecture.md`
- Review checklist -> `docs/review.md`
- Decisions -> `docs/adr/`
- Plans and specs -> `docs/plans/`, `docs/specs/`
