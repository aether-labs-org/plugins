# One harness for three agents

Claude Code, GitHub Copilot CLI and Devin CLI, latest versions. The harness lives in the repository and works without this plugin.

## Instructions

`AGENTS.md` is the only content file: an index of at most 100 lines that carries only what the agent cannot discover (setup, the
commands it cannot guess, working rules, boundaries, "before you finish", pointers). `CLAUDE.md` contains exactly `@AGENTS.md`
and nothing else, so Devin, which reads both, gets no duplicate. Copilot CLI and Devin read `AGENTS.md` natively. No
`.github/copilot-instructions.md`, no `.devin/rules`. If a `CLAUDE.md` or a Copilot instructions file already exists with
content, show the difference and ask; never delete it. Generated context files can lower success and raise cost (Gloaguen et al.,
https://arxiv.org/abs/2602.11988): every line of `AGENTS.md` is confirmed by the human, and the default for a line is to leave
it out. A nested `AGENTS.md` (`templates/nested-AGENTS.md`) holds rules for one directory, also at most 100 lines.

## Hooks: one file for all three

Only `.claude/settings.json` carries the hooks (`templates/settings.json`):

- `PreToolUse` with the matcher `Write|Edit|MultiEdit|NotebookEdit|Bash` runs the wrapper `.agents/bin/bmax hook pre-tool-use`
  (timeout 10); `Stop` runs `... hook stop` (timeout 120). Copy the commands of the template exactly. They locate the wrapper with
  `${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}`: the Bash working directory of a session persists between calls and can
  end up in another repository (a nested one, a worktree), where `git rev-parse` would name the wrong root. When the wrapper file
  does not exist the command answers `ask` (PreToolUse) or a `systemMessage` (Stop) and exits 0; a hook that exits 2 blocks every
  Bash, Write and Edit call of the session and the session cannot recover by itself.
- The wrapper exports `BMAX_ROOT` (its repository), so `bmax` works on that repository whatever the working directory is. Git hook
  templates keep `$(git rev-parse --show-toplevel)`: git runs them at the top-level.

Copilot CLI reads `.claude/settings.json` in the repository and runs all hook entries from all sources, switching to Claude's
payload shape for PascalCase events; Devin CLI imports hooks, commands and subagents from `.claude/` by default. A separate
`.github/hooks/` file would therefore run every hook twice in Copilot, so Baymax writes none. The output is one JSON valid for both:
`hookSpecificOutput.{hookEventName, permissionDecision, permissionDecisionReason}` for Claude and the same two fields at top
level for Copilot; Stop answers `{"decision": "block", "reason": ...}`.

State plainly what is assumed, not tested: the Copilot cross-read and the Devin import are trusted from the documentation, and the
payloads in the contract tests are built from documented shapes, not recorded from the agents. The owner validates the live
behaviour; if a cross-read fails, the fallback is a Copilot-specific file with deduplication.

## The Stop hook

At the end of a turn it runs the `fast` gate when the tree changed since the last green result. A failure forces **one** more
turn with the reduced gate result; the same failure relayed again (`stop_hook_active`) lets the agent stop and shows the failure to
the human. A config that is invalid, or a gate that cannot run, never blocks.

## When `bmax` is unavailable

Hooks fail safe (see [protection](protection.md)). Tell the human to run `sh .agents/bin/bmax setup`; the first line of `AGENTS.md` is
that command.

## The setup session

This skill registers its own PreToolUse hook (`bmax hook pre-tool-use --setup`) so that the harness paths are protected before any
repository hook exists. With no `bmax.yml` it protects the defaults plus the files setup writes. The plugin carries the wrapper and
the lock of the `bmax` version it installs; copy both exactly, and never raise the pin on your own.

## After setup

Tell the human to review and commit, to run `sh .agents/bin/bmax setup`, and to open a **new session** in any of the three agents:
guides load at session start and the setup conversation is noise, so a fresh session is the clean test.
