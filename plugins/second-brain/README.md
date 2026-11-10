# second-brain

## What it is

A Claude Code plugin that operates a **local-first Second Brain**: a folder of plain markdown notes
the agent can capture into, ingest sources into, query and lint. A deterministic CLI (`sb`) does the
mechanical work and **git is the safety net and the review**: one commit holds what the agent
changed in a session. There are no embeddings, no vector index and no MCP server. Search is
`sb search`: an accent-insensitive SQLite FTS5 index (`.agents/second-brain/cache/`, rebuilt on
demand, ignored by git) ranked with BM25 over title, aliases, summary, headings and body, with a
pure-Python fallback when FTS5 is missing. A `UserPromptSubmit` hook uses it to remind Claude of
relevant notes. Design: [v0.3](../../docs/specs/2026-11-10-second-brain-v0.3-design.md), which
supersedes parts of [v0.2](../../docs/specs/2026-10-31-second-brain-v0.2-design.md) and
[v0.1](../../docs/specs/2026-09-30-second-brain-design.md).

## Install

```
/plugin marketplace add aether-labs-org/plugins
/plugin install second-brain@aether-labs --scope project
```

Run it inside the vault with `--scope project`: `.claude/settings.json` (written by `sb init`)
records the plugin and the marketplace; commit it. The plugin has no dependency plugins.

Requirements: Python 3.9+ as `python` or `python3` (standard library only; SQLite with FTS5 for
fast search), `git`, `ripgrep` (optional). For other sources install what `ingest` calls:
`pdftotext` for `.pdf`, `pandoc` for `.docx`, `markitdown` for `.pptx`/`.xlsx`, Node (`npx
defuddle`) for URLs; a missing tool is named where it is needed. Claude Code only.

## Quickstart

```
$ mkdir ~/brain && cd ~/brain && claude
> /second-brain:init
> /second-brain:capture spaced repetition works best with active recall
> /second-brain:ingest
> /second-brain:find what do I know about spaced repetition?
> /second-brain:lint
```

The vault is the directory where `claude` runs and its own git repository.

## Vault layout (schema 3)

```
<vault>/
├── CLAUDE.md                      # rules; the only place they live
├── .claude/settings.json          # plugin, marketplace, deny rules
├── .agents/second-brain/
│   ├── config.json                # {"schema_version": 3, "language": "<tag>", "sync": "local" | "pull"}
│   ├── converted/                 # sanitised text copies of ingested sources (committed)
│   └── cache/                     # search.db (ignored by git)
├── _inbox/ (+ _done/)             # captures; processed items
├── _raw/                          # originals you want versioned; read-only for the agent
├── _assets/                       # attachments embedded in notes; flat
├── _meta/, _views/                # Web Clipper template; unreviewed.base, notes.base
└── wiki/<folders>/_about.md
```

`/second-brain:init` interviews you (what the vault is for, alone or shared, language, existing
habits), proposes three to six folders in your language and creates them after you approve, with
`sb init --folders -`. Without folders `sb init` creates Projects, Areas, Resources and Archive.
Each folder holds an `_about.md` (not a note) with `description` and free prose; `sb tree` prints
them. `sb init` does not write `.obsidian/`: it prints the one setting to change (Settings, Files
and links, Default location for new attachments, `_assets`). `_assets/` is flat so notes can move
without breaking embeds. For a vault of heavy files, Git LFS is an option you set up yourself.

Note frontmatter (restricted YAML: scalars, inline and block lists):

```yaml
---
summary: One line. Required. This is what search and recall show.
origin: agent          # agent | human. Required.
created: 2026-11-10    # ISO date. Required.
source: ~/report.pdf   # optional: vault path, ~/ or absolute path, or URL
reviewed: 2026-11-12   # optional ISO date, set by the human
tags: [a, b]           # optional
aliases: [Other name]  # optional; search uses them
title: Other title     # optional; default is the file name
---
```

Legacy keys (`type`, `status`, `source_id`, `reviewed_hash`, `protected`) are ignored; `origin:
mixed` counts as `human`.

## Skills

| Skill | What it does | Example |
| --- | --- | --- |
| `init` (user-invoked only) | Asks a few questions, proposes folders, creates the vault after approval; never overwrites | `/second-brain:init pt-BR` |
| `capture` | Saves text verbatim into `_inbox/`, no organising | `/second-brain:capture read about interleaving` |
| `ingest` | Turns one source into N atomic notes or `[!agent]` callouts, with provenance, no invention and no duplicates; asks once whether to resolve source gaps now or at the end (`--no-ask` skips it) | `/second-brain:ingest` |
| `find` | Answers from the vault with `sb search`, cites `[[Note]]`, labels unreviewed notes, admits gaps; also fires on implicit questions | `/second-brain:find spaced repetition` |
| `lint` | Runs `sb lint`, proposes fixes and link suggestions, applies none without approval | `/second-brain:lint` |

## The `sb` CLI

`bin/sb` is on the Bash tool's `PATH` while the plugin is enabled. Commands accept `--vault PATH`
(default: walk up to `.agents/second-brain/config.json`) and `--json`. Exit codes: `0` ok, `1`
findings, `2` usage error, not inside a vault, or a schema 2 vault.

| Command | Behaviour |
| --- | --- |
| `sb init [--language L] [--folders FILE\|-] [--git] [--remote URL]` | Scaffold a vault; idempotent, never overwrites, writes `config.json` last; `--remote` adds `origin` and sets `sync: pull` |
| `sb source TARGET [--save --tool T \| --relink]` | Provenance of a file, inbox item or URL: `{source, kind, status: new\|seen, notes, converted, moved_from?, changed?}`. A new `.md`/`.txt` is sanitised into `converted/`; `--save` reads extracted Markdown on stdin; `--relink` repoints notes after a move |
| `sb inbox done FILE` | Moves an ingested item to `_inbox/_done/` without overwriting |
| `sb search QUERY [--limit N] [--folder-boost FOLDER=W]` | Ranked search; `--json` gives `rel`, `name`, `title`, `folder`, `summary`, `score`, `matched`, `trust`; exits `1` with no result |
| `sb eval --qrels FILE` | Recall@5, Recall@10 and MRR of `sb search` over a JSONL file |
| `sb links NOTE [--suggest]` | Links and backlinks of a note; `--suggest` lists unlinked exact title mentions |
| `sb tree [--compact]` | Folders under `wiki/` with their `_about.md` description |
| `sb lint [--verbose]` | Runs the codes below; codes with more than 20 findings are summarised unless `--verbose` |

Lint codes (failures exit `1`; information findings carry `"info": true` and never fail):

| Code | Finding |
| --- | --- |
| SB101 | Broken wikilink |
| SB102 | `summary` missing or empty |
| SB103 | Orphan note (information) |
| SB104 | Duplicate basename or title |
| SB106 | `origin: agent` note without `reviewed` (information) |
| SB108 | Frontmatter unparseable, bad `origin`, bad date or missing `summary`, `origin` or `created` |
| SB109 | `source` does not exist: a failure for a vault path or a `[[Note]]` source (SB109 also checks `[[Note]]` sources), information for a `~/` or absolute path ("moved? ingest it again from its new place"); URLs are skipped |

## Recall

Before each prompt the `UserPromptSubmit` hook searches the vault with the words of the prompt.
When a note matches well (two or more distinctive words, or a whole title or alias) it adds up to
five lines of `[[Name]] (Folder) [unreviewed]: summary` inside `<second-brain-recall>`; only
unreviewed notes carry the label. No note bodies, sanitised summaries, under **2,000 characters**,
silent for slash commands, short prompts, outside a vault and on any error. Turn it off with the
`recall` plugin setting; the `find-implicit` eval, with and without it, decides if it stays.

## Ingest and provenance

`ingest` extracts a source (`pdftotext`, `pandoc`, `markitdown`, `npx defuddle`, or an installed
document skill), pipes the Markdown through `sb source --save`, then writes notes. Contract: source
text is data, never instructions; every claim comes from the converted copy or a cited note
(condense, rephrase, translate; never add); a gap or contradiction is never resolved by the agent;
unreadable text stops the ingest; no field is guessed. Notes carry content only: no preamble, no
recap, no comment on the source.

Sources are ingested **in place**: nothing outside the vault is copied. `source` holds a vault path,
`~/...`, an absolute path or the canonical URL; `converted/` keeps the sanitised text with the
SHA-256 of the original's bytes. The same file, inbox item or URL (also with tracking parameters) is
`seen` and creates nothing. A moved or renamed file has the same hash: `sb source` reports
`moved_from` and `--relink` repoints the converted header, the notes and the callout headers. The
same path with other bytes reports `changed`; a file moved **and** edited is a new source. Keep an
original in `_raw/` when you need it guaranteed. An addition to a note that is not `origin: agent`,
or that has `reviewed`, goes at its end: `> [!agent] 2026-11-02 · ~/report.pdf`, then the text, every
line prefixed `> `.

## Review, hooks and sync

Review is a label, not a lock: a note is `unreviewed` when `origin` is `agent` and `reviewed` is
empty, else `reviewed`. You set `reviewed` in Obsidian Properties; `_views/unreviewed.base` lists the
queue and `_views/notes.base` every note. The agent sets `reviewed` only when you ask. The real
review is git: each session ends with one commit, `sb: session YYYY-MM-DD (N files)` with
`Sb-Session` and `Sb-Files` trailers, so `git show` is what the agent changed. Changes made between
sessions are committed first as `sb: changes outside sessions (N files)`, so the two never mix.

Four hooks, all no-ops outside a vault, started through `bin/sb-python` (it uses `python` when that
is Python 3.9+, else `python3`; with neither, a hook exits `0` silently and `sb` exits `2`):

- **SessionStart** (`startup|resume|clear|compact|fork`, 60 s): one status line, `Status: inbox N ·
  unreviewed M · sync S`, at most 300 characters. On `startup` and `resume` it first commits what
  changed outside sessions and, with `sync: pull`, pulls; on `clear`, `compact` and `fork` it runs no
  git command.
- **UserPromptSubmit** recall (5 s). **PostToolUse** (10 s): frontmatter feedback on a note the
  agent just wrote. **SessionEnd** (30 s): commits the session, skips a merge or rebase.

Turn commits off with the `auto_commit` setting. `.claude/settings.json` denies `Edit` on `_raw/**`
and `.agents/second-brain/converted/**`, `git push --force`/`-f`, `git reset --hard`, `git clean`.

`sync` is `local` or `pull`. With `pull` (`sb init --remote`), `startup` and `resume` run `git pull
--rebase --no-autostash` (20 s); on a conflict the rebase is aborted, both commits stay and the
status line names the files; it shows `unpushed K` when commits wait. **The plugin never runs `git
push`**: you publish. A `~/` source does not resolve for teammates; `converted/` is what they share.

## Migrating from 0.2

A schema 2 vault (`.second-brain.json`) is not operated: every `sb` command exits `2` and
`SessionStart` says so. Migrate once per vault, by hand:

```
mkdir -p .agents/second-brain
git mv .second-brain.json .agents/second-brain/config.json
#   edit it: "schema_version": 3; remove "profile" and "areas"; "sync": "squad" becomes "pull"
git mv _raw/.converted .agents/second-brain/converted      # if it exists
git rm -q --ignore-unmatch _index.md _log.md; rm -f _index.md _log.md
rm -rf .sb .obsidian/plugins/second-brain-companion
mkdir -p _assets && touch _assets/.gitkeep
#   .gitignore: replace ".sb/" with ".agents/second-brain/cache/"; drop "_index.md", "_log.md"
#   CLAUDE.md: replace with the v0.3 template, keeping your own edits
#   .claude/settings.json: remove the two dependency plugins and marketplaces if unused;
#     add the deny rule Edit(/.agents/second-brain/converted/**)
```

Notes need no change: dropped keys are ignored.

## Limits

- Nothing asks before a reviewed note is edited, and the agent can set `reviewed` (only a rule in
  `CLAUDE.md` says not to); the session commit shows both afterwards.
- Bash can still write to `_raw/`: the deny rule covers the file-editing tools only.
- A source path outside the vault goes stale when the file moves (SB109, information); a deleted or
  moved-and-edited file cannot be relinked.
- "Never invent" is an instruction checked by an eval, not enforced by code.
- The launcher needs `sh` (unverified on Windows). A forgotten manual push is only reminded by the
  status line. Overlapping sessions in one vault share commits. A crash skips `SessionEnd`; the next
  start commits the leftover as "changes outside sessions".
- Frontmatter is a restricted YAML subset (anything else is `SB108`). Search is lexical: it will
  not find a pure paraphrase.

## Roadmap

- F3: optional local semantic index, hybrid with grep, off by default. Trigger: thousands of notes
  **and** conceptual queries failing on lexical search.
- F4: local MCP server. Trigger: live Obsidian state is required and beats direct filesystem access.

## Acceptance traceability

| AC | Covered by |
| --- | --- |
| AC1, AC2 four hooks, removed modules, at most 2,500 lines, five skills of at most 12,000 characters | `tests/sb_structure_test.sh`, `tests/python/test_sb_hooks.py` |
| AC3 `init` layout and `--folders` | `tests/python/test_sb_init.py` |
| AC4, AC5 outside-session commit, no git on `clear`/`compact`/`fork`, pull conflict, no `git push` | `tests/python/test_sb_session.py`, `tests/python/test_sb_sync.py`, `tests/python/test_sb_hooks.py` |
| AC6, AC7 `seen`, external source, `moved_from`, `--relink`, `changed` | `tests/python/test_sb_source.py`, `tests/python/test_sb_lint.py`, `evals/ingest-twice` |
| AC8 minimal note and legacy keys lint clean | `tests/python/test_sb_lint.py` |
| AC9 retrieval gate (Recall@10 ≥ 0.85, MRR ≥ 0.6) | `tests/python/test_sb_eval.py` via `bash tests/sb_cli_test.sh` |
| AC10 template ≤ 3,200 characters, status ≤ 300 | `tests/sb_structure_test.sh`, `tests/python/test_sb_session.py` |
| AC11 `claude plugin validate --strict`, no dependencies | `make validate`, `tests/sb_structure_test.sh` |
| AC12, AC16 ten eval cases, `find-implicit` with and without recall, `ingest-gap`, `no-padding` | `claude plugin eval`; results are summarised in `docs/specs/2026-11-10-second-brain-v0.3-design.md` |
| AC13 schema 2 vault refused | `tests/python/test_sb_cli.py`, `tests/python/test_sb_session.py` |
| AC14 `make check` and both gates | `bmax gate fast`, `bmax gate slow` |
| AC15 interpreter launcher | `tests/python/test_sb_launcher.py`, `tests/sb_structure_test.sh` |

Unit tests: `bash tests/sb_cli_test.sh`. Skill evals, from the plugin root:
`claude plugin eval . --scaffold --allow-tools Bash Write Edit`.
