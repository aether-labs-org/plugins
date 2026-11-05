# Baymax harness

Create, review and keep the AI-agent harness of a repository. One skill diagnoses the repository, measures it, asks in rounds and
writes only what you confirm, file by file. The harness it leaves behind lives in your repository and works without this plugin, in
Claude Code, GitHub Copilot CLI and Devin CLI.

## What you get

| In the repository | What it is |
| --- | --- |
| `.agents/bin/bmax` + `.agents/bmax.lock` | A small `sh` wrapper and the pin of the `bmax` engine. It downloads the pinned binary once, verifies its sha256 and runs it. |
| `.agents/bmax.yml` | Your scripts (the commands that check things) and gates (`fast`, `commit`, `slow`), validated strictly. |
| `AGENTS.md` (+ `CLAUDE.md` = `@AGENTS.md`) | An index of at most 100 lines with only what an agent cannot discover. |
| `docs/` topic files, `docs/adr/` | Rules with their reasons; immutable decisions. |
| `.claude/settings.json` | The hooks. Copilot CLI and Devin CLI read them too, so one file serves the three agents. |
| `.agents/githooks/` | Pre-commit, commit-msg and pre-push hooks that run the same gates for humans and agents. |
| `.agents/plans/`, `progress.md`, `lessons.md` | Memory that is checked for format and for leaks. |
| `docs/review.md` + two reviewer definitions | An independent review the agent always offers. |

## How it works

`bmax` is the only engine and holds everything the project needs without the plugin: running scripts and gates with timeouts, retries and
evidence; parsing JUnit, SARIF, Checkstyle, ESLint JSON and `errorformat` output; baselines that only shrink; builtins (`guard`,
`file-size`, `folder-layout`, `pattern`, `architecture-grep`, `test-presence`, `dependencies`, `memory`, `scope`, `merge-check`,
`commit-message`, `branch-name`); the hooks; `bmax check` for drift; `bmax setup` per clone. The verdict always comes from an exit code,
a parser or a baseline, never from a model.

This plugin only **authors**. It holds one skill, its references, a catalog of rules and tools per stack (TypeScript, Python, JVM),
templates, and two read-only scripts. It writes nothing except through your confirmed Write/Edit.

## Use it

```
/plugin marketplace add aether-labs-org/plugins
/plugin install baymax@aether-labs
```

Ask for a harness (or run `/baymax:harness`). Then, in the repository: review and commit, run `sh .agents/bin/bmax setup` once per
clone, and open a new session in your agent.

The agent never changes the harness alone. A write to a protected file (config, baselines, guides, ADRs, hook settings) asks you; a
shell write to one is denied; an ADR that names what it loosens is what lets a loosening pass `guard`. At the end of a turn the Stop
hook runs the fast gate and hands a failure back once.

## Declared limits

- **Protection is friction with evidence, not a security boundary.** The hook can be bypassed by a human, by design; `guard` and the
  git hooks are the second line.
- **The effect on agent success was not measured.** Generated context files can make agents worse (Gloaguen et al.,
  https://arxiv.org/abs/2602.11988). Baymax mitigates by design only: `AGENTS.md` carries what the agent cannot discover, and every line is
  confirmed by you. No with/without evaluation was run.
- **The Copilot CLI and Devin CLI cross-reads are assumed from their documentation** (Copilot reads `.claude/settings.json`; Devin
  imports `.claude/`). The hook contract tests use payloads built from the documented shapes, not recorded from the agents. Validate
  the live behaviour in each agent after setup.
- **Recorded outputs miss later changes.** The parsers are tested against real outputs of specific tool versions (named in the
  fixtures); a tool that changes its flags or format afterwards is not detected by those tests.
- `staged` gates read file content from disk, not from the index.
- The first run needs the release host; `BMAX_RELEASE_URL` (a mirror), `BMAX_BINARY` or a source build avoid it.
- Authority is local: git hooks and agent hooks. Baymax generates no CI.
- Windows only through WSL. Catalog stacks: TypeScript/JavaScript, Python, JVM.

## Versions

Plugin and `bmax` share one version (0.5.0). The plugin carries the wrapper and the lock of the `bmax` it installs; the skill copies the lock
exactly and never raises a pin on its own. Design: `docs/specs/2026-11-04-baymax-harness-v0.5-design.md` in the repository. The `bmax`
engine: `cli/bmax/README.md`.

## Not included

CI generation, headless setup, Codex or other agents, migration from the v0.1 to v0.3 plugin, effect evaluations, a task runner, a sandbox.
