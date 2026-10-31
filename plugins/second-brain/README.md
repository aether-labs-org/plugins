# second-brain

## What it is

A Claude Code plugin that operates a **local-first Second Brain**: a folder of plain markdown notes
that the agent can capture into, organise, query, relate and update. Deterministic tooling (the
`sb` CLI) does the mechanical work, and git is the safety net. The rule that defines v0.1 is
**deterministic first**: search is `ripgrep` + frontmatter + wikilinks, with no embeddings, no vector
index and no MCP server. Since v0.2 search is `sb search`: an accent-insensitive SQLite FTS5 index
(`.sb/search.db`, rebuilt on demand, ignored by git) ranked with BM25 over title, aliases, summary,
headings and body, with a pure-Python fallback when FTS5 is missing. A `UserPromptSubmit` hook uses
it to remind Claude of relevant notes. Design:
[`docs/specs/2026-09-30-second-brain-design.md`](../../docs/specs/2026-09-30-second-brain-design.md) (v0.1) and
[`docs/specs/2026-10-31-second-brain-v0.2-design.md`](../../docs/specs/2026-10-31-second-brain-v0.2-design.md) (v0.2).

## Install

```
/plugin marketplace add aether-labs-org/plugins
/plugin install second-brain@aether-labs
```

Requirements: Python 3.9+ (standard library only; SQLite with FTS5 for fast search, otherwise a slower
fallback is used), `ripgrep` (`rg`) for the `ingest`, `link`, `update` and `lint` skills, `git` for
auto-commit. The plugin targets Claude Code only (plugins with `bin/` are not installed on
claude.ai or Cowork).

## Quickstart

```
$ mkdir ~/brain && cd ~/brain && claude
> /second-brain:init
> /second-brain:capture spaced repetition works best with active recall
> /second-brain:ingest
> /second-brain:find what do I know about spaced repetition?
> /second-brain:lint
```

The vault is the directory where `claude` runs.

## Skills

| Skill | What it does | Example |
| --- | --- | --- |
| `init` (user-invoked only) | Creates the vault layout, `CLAUDE.md`, marker; idempotent | `/second-brain:init pt-BR` |
| `capture` | Saves text verbatim into `_inbox/`, no organising | `/second-brain:capture read about interleaving` |
| `ingest` | Turns an inbox item or `_raw/` source into one atomic note; updates instead of duplicating | `/second-brain:ingest` |
| `find` | Answers from the vault with `sb search`, cites `[[Note]]`, labels unreviewed notes, admits gaps; also fires on implicit questions ("how did I do X again?") | `/second-brain:find spaced repetition` |
| `link` | Proposes wikilinks and surfaces orphans; applies only approved ones | `/second-brain:link Zettelkasten` |
| `update` | Applies a requested change keeping provenance (`created`, `source`, `origin`, `reviewed`) | `/second-brain:update Active Recall add an example` |
| `lint` | Runs `sb lint`, proposes fixes, applies none without approval | `/second-brain:lint` |

## The `sb` CLI

`bin/sb` is on the Bash tool's `PATH` while the plugin is enabled. Every command accepts
`--vault PATH` (default: walk up from the working directory to `.second-brain.json`) and `--json`.

| Command | Behaviour |
| --- | --- |
| `sb index --write` / `--check` | Rebuild `_index.md` deterministically; `--check` exits `1` on drift and prints the diff |
| `sb search QUERY [--limit N] [--folder-boost FOLDER=W]` | Ranked, accent-insensitive search; `--json` gives `rel`, `name`, `title`, `folder`, `summary`, `score`, `matched`, `trust`; exits `1` with no result |
| `sb eval --qrels FILE` | Recall@5, Recall@10 and MRR of `sb search` over a JSONL file of queries and expected notes |
| `sb lint [--verbose]` | Run SB101–SB109; codes with more than 20 findings are summarised unless `--verbose` |
| `sb links NOTE [--suggest]` | Outgoing links, backlinks, unresolved links; `--suggest` lists unlinked exact title mentions |
| `sb validate FILE...` | Fast frontmatter checks for notes under `wiki/` |
| `sb log EVENT TITLE` | Append `## [date] EVENT \| TITLE` to `_log.md` (`init capture ingest update link lint`) |
| `sb init [--language L] [--areas a,b] [--git]` | Scaffold a vault; writes `.second-brain.json` last; idempotent |

Exit codes: `0` ok, `1` findings, `2` usage error or not inside a vault.

| Code | Finding |
| --- | --- |
| SB101 | Broken wikilink |
| SB102 | `summary` missing or empty |
| SB103 | Orphan note (no backlinks from other notes) |
| SB104 | Duplicate basename or title |
| SB105 | `_index.md` out of sync with `wiki/` |
| SB106 | `origin: agent` note without `reviewed` |
| SB107 | `schema_version` older than the CLI's |
| SB108 | Frontmatter unparseable, unknown enum, bad date or missing key |
| SB109 | `source` path does not exist |

```
sb lint
sb index --check
sb links "Spaced Repetition" --suggest
```

## Recall

Before each prompt, the `UserPromptSubmit` hook searches the vault with the words of the prompt.
When at least one note matches well (two or more distinct query words, or a whole title or alias
mentioned in the prompt) it adds up to five lines of `[[Name]] (Folder) [reviewed|unreviewed|
has-agent-blocks]: summary` to the context, wrapped in `<second-brain-recall>`. It never includes
note bodies, sanitises summaries, and stays under **2,000 characters**. It stays silent for slash
commands, prompts with fewer than three content words, outside a vault, and on any error.

Turn it off with the `recall` plugin setting (`/plugin` → configure `recall`, or the
`recall` user option set to `false`).

## Protection and auto-commit

Four hooks, all no-ops in a directory without `.second-brain.json`:

- **PreToolUse guard** denies writes to `_raw/**`, `.claude/**`, the top-level `CLAUDE.md` and
  `.second-brain.json` (and `rm`/`mv`/`>` style Bash commands that target them), and asks before
  deleting anything under `wiki/`. Edit the protected files yourself.
- **UserPromptSubmit recall** adds candidate notes to the context (see [Recall](#recall)).
- **PostToolUse check** runs the frontmatter checks on a note the agent just wrote and reports
  problems back to it.
- **SessionEnd auto-commit**: when the vault has a `.git`, `auto_commit` is on and there are
  changes, runs `git add -A` and commits `sb: session YYYY-MM-DD (N files)`. **One commit per
  session, local only, never pushed.** It is skipped during a merge or rebase. Turn it off in the
  plugin's settings (`/plugin` → configure `auto_commit`) or set the `auto_commit` user option to
  `false`.

## Limits

- Bash cannot be fully fenced: the guard is a best-effort pattern match and a determined command
  can write to `_raw/` in ways it will not see. Git is the real safety net.
- Frontmatter is a restricted YAML subset (`key: value`, inline `[a, b]` and block `- item` lists);
  anything else is `SB108`.
- Search is lexical (stemming only by 5+ character prefixes): it will not find a pure paraphrase.
- The hooks run Python on every matching tool call or prompt in every session (they exit
  immediately outside a vault). Disable the plugin if the cost matters.

## Roadmap

| Phase | What | Trigger |
| --- | --- | --- |
| F1 | Per-area `_index.md` files | Root index passes roughly 200–300 notes |
| F2 | Local lexical index (SQLite FTS5) | Done in v0.2 (`sb search`) |
| F3 | Optional local semantic index, hybrid with grep, off by default | Thousands of notes **and** conceptual queries failing on lexical search |
| F4 | Local MCP server | Live Obsidian state is required and beats direct filesystem access |

## Acceptance traceability

| AC | Criterion | Covered by |
| --- | --- | --- |
| AC1 | `init` layout, idempotent, never overwrites `CLAUDE.md`, template < 200 lines | `tests/python/test_sb_init.py`, `tests/sb_structure_test.sh` |
| AC2 | `ingest` yields a valid note, updates index and log, no duplicate | `evals/ingest-twice`, `tests/python/test_sb_cli.py` |
| AC3 | `find` cites notes and admits gaps | `evals/find-trigger`, `evals/find-empty` |
| AC4 | `lint` reports the planted broken link and missing summary | `tests/python/test_sb_fixtures.py`, `tests/python/test_sb_lint.py`, `evals/lint-planted` |
| AC5 | A write to `_raw/` is blocked | `tests/python/test_sb_guard.py` |
| AC6 | SessionEnd hook commits only when `.git` exists and `auto_commit` is on | `tests/python/test_sb_hooks.py` (`AutoCommitTests`) |
| AC7 | `ripgrep` finds every note, including under `_` folders | `tests/python/test_sb_cli.py::test_ripgrep_finds_notes_under_underscore_folders` (skipped when `rg` is not on `PATH`) |
| AC8 | `claude plugin validate --strict` passes | `make validate` (run in CI after installing Claude Code) |
| AC9 | No embeddings, MCP server or Obsidian plugins | `tests/sb_structure_test.sh` |
| AC10 | Hooks are no-ops without `.second-brain.json` | `tests/python/test_sb_guard.py`, `tests/python/test_sb_hooks.py` |

Run the unit tests with `bash tests/sb_cli_test.sh` (this includes the retrieval gate: Recall@10 ≥ 0.85 and MRR ≥ 0.6 on `tests/fixtures/sb-eval`) and the skill evals from the plugin root with
`claude plugin eval . --scaffold --allow-tools Bash Write Edit` (scaffolds seed fixture vaults;
without `--scaffold` the cases run against an empty workspace).
