# Protection: what is protected, what to say

The agent never changes the harness alone. `kh hook pre-tool-use` enforces it; `guard` and the git hooks are the second line. It is
friction with evidence, not a security boundary: a human can still bypass it, by design. Say so whenever you describe it.

## The protected set (fixed by kh, not configurable)

| Class | Paths |
| --- | --- |
| engine | `.agents/keel.yml`, `.agents/keel.lock`, `.agents/bin/**`, `.agents/baselines/**`, `.agents/githooks/**` |
| config | every file a script names in `config:` (linter, architecture tool, mutation threshold) |
| agent-hooks | `.claude/settings.json`, `.claude/settings.local.json`, `.claude/agents/keel-reviewer.md`, `.github/hooks/**`, `.github/copilot/settings*.json`, `.github/agents/keel-reviewer.agent.md`, `.devin/**`, `.git/hooks/**`, `.git/config`, and the user-level agent settings that can switch repository hooks off (`~/.claude/settings*.json`, `~/.copilot/settings.json`, `~/.copilot/hooks/**`, Devin's user configuration) |
| guides | every path in `guides:`, `docs/review.md`, `.github/pull_request_template.md` |
| adr | everything under `adr_dir` |

Not protected, because the agent writes them: `.agents/plans/`, `.agents/progress.md`, `.agents/lessons.md`, `.agents/run/`. Anything
else under `.agents/` (for example `.agents/skills/`) belongs to other tools: never read, write or protect it.

## What the hook decides

- A Write/Edit/MultiEdit/NotebookEdit on a protected path **asks** the human; under `bypassPermissions` or `dontAsk`, where asking
  is not guaranteed to prompt, it **denies** and says to switch mode.
- A shell command that writes a protected path is **denied** (redirections, `tee`, `sed -i`, `perl -i`, `cp`, `mv`, `rm`, `ln`,
  `truncate`, `touch`, `chmod`, `git checkout/restore/reset/apply`, interpreters whose code names the path, `bash -c`, `eval`).
- Denied whatever the path: `git commit --no-verify`, `git push --no-verify`, `git config core.hooksPath`, `git -c
  core.hooksPath=...`, `git update-index --assume-unchanged/--skip-worktree`, an inline `KH_BINARY=` or `KH_RELEASE_URL=`.
- A shell command that invokes the same executable as a declared script is denied with the `kh run <script>` to use, and "do not
  pipe its output". `kh run -- <command>` runs an undeclared command with evidence. Commands the tokenizer cannot split are allowed.

## Which repository decides

Each write target is checked against the protected set of the git repository that **contains the target**, not the one the session
happens to be in: a nested repository, or a `git worktree` of the project, is another repository, and writing a protected file of
the project from there asks all the same. A repository without `.agents/keel.yml` has no protected set (in the setup session the
setup defaults apply to it); one whose `keel.yml` is invalid is treated as protected. The wrapper of the project exports `KH_ROOT`,
so `kh` and the hooks stay on the project when the working directory moves. Declared scripts are intercepted only in a repository
that has a harness, and an invocation that only asks for `--version` or `--help` is not intercepted. The reason to never `cd` out
of the repository during setup is in [SKILL.md](../SKILL.md).

## What to tell the human

- When a write is **asked**: say which file, its class, what you want to change and why, and that nothing changes until they
  confirm. When a write is **denied**: do not look for another route (a different tool, a symlink, the shell); explain the change
  and ask the human to make it or to confirm the edit through the file tools.
- When a rule blocks legitimate work: explain, propose the change, and, if it loosens a rule, the ADR that releases it. Never
  edit a baseline, a threshold or a test expectation to turn a gate green.
- If the setup-session hook and the repository hook both prompt for one write, that is expected (the repository hook becomes active
  once `.claude/settings.json` is written, which is why it is written last).

## `guard`

`guard` is in every required gate. It compares the working tree with the base (`KEEL_GUARD_BASE`, else the merge-base with
`origin/HEAD`, else `HEAD`) and reports: a script removed from a gate; `timeout`, `ceiling` or `retries` raised; `class` changed
from `security`; `files` narrowed; `format` removed; `run` or `with` changed on a script with `decision`; a baseline row grown or
added; a `config:` file changed, or a `config:` entry removed (which would stop protecting that file); an exception added or extended; a `kh hook` entry removed or changed in `.claude/settings.json`;
a guide deleted; an accepted ADR edited or deleted (only the status line may change to `Superseded by NNNN`); type strictness
lowered (`tsconfig` strict, mypy, pyright). A loosening passes only when an ADR added since the base names the script
(`.agents/keel.yml#<id>`) or the file. Tightening needs no ADR; `kh check` warns `baseline-stale` and the agent proposes the new
`kh measure` output, written with the human's confirmation. `kh` never writes baselines, guides or memory.

## When kh cannot run

A fresh clone before `kh setup`, an offline machine, a cached binary that fails verification: the wrapper, in hook mode, never
downloads. It answers `ask` for every Write/Edit/Bash call (`deny` under bypass) with "kh unavailable: run sh .agents/bin/kh
setup" (or the real cause: no lock, a checksum mismatch), and a non-blocking notice for Stop. Tell the human to run
`sh .agents/bin/kh setup`. The commands in `.claude/settings.json` do the same when the wrapper file itself is missing (a worktree
that has no `.agents/bin/kh`): `ask`/notice and exit 0, never exit 2, which would block every tool call.
