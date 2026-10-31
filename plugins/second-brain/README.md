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
/plugin marketplace add anthropics/skills
/plugin marketplace add kepano/obsidian-skills
/plugin marketplace add aether-labs-org/plugins
/plugin install second-brain@aether-labs --scope project
```

Install with `--scope project` (run it inside the vault): the vault's `.claude/settings.json`
records the plugin, its two dependencies and the three marketplaces (`extraKnownMarketplaces`), and
you commit it, so everyone who opens the vault is offered the same setup. `sb init` writes that file;
`sb doctor` checks it. Add the two dependency marketplaces first: installing fails with `Dependency "document-skills@anthropic-agent-skills" ... not found`
while they are missing. The plugin declares two dependencies, which Claude Code installs with it:
`document-skills` (the `pdf`, `docx`, `pptx` and `xlsx` skills) and `obsidian` (including `defuddle`
for web pages). They ship no extraction tools: for formats other than Markdown install what
`ingest` calls, `pdftotext` (poppler) for `.pdf`, `pandoc` for `.docx` and `markitdown` for
`.pptx`/`.xlsx`, and Node (`npx defuddle`) for URLs.

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

The vault is the directory where `claude` runs, and it is its own git repository: `sb init`
refuses a directory inside another repository, and `sb doctor` fails when the git top-level is not
the vault root.

## Profiles and folders

`/second-brain:init` asks for a profile (and the language, and for `squad` a git remote). Folder
names and their `_about.md` texts ship in English; you edit `_about.md` as you wish.

| Profile | `wiki/` folders | Sync |
| --- | --- | --- |
| `personal` | Projects, Areas, Resources, Archive | local |
| `work` | Projects, Areas, Resources, Decisions, Meetings, Archive | local |
| `project` | Context, Decisions, Meetings, References, Glossary, Archive | local |
| `squad` | as `project` | squad (git pull/push) |

Every folder may hold an `_about.md` (not a note: search, lint and the index skip it):

```
---
description: Concepts, references and entities reused across projects.
protected: false
---
## Conventions
## Examples
## Anti-examples
```

At the start of each session the `SessionStart` hook gives Claude the compact folder tree (at most
2,000 characters, from `description`) and one status line (`inbox N · unreviewed M · sync …`), so it
files notes where they belong. `protected: true` makes every agent write under that folder ask you
first (tier T2). A folder without `_about.md` is reported as `SB111` (information only; `sb lint`
still exits `0`). `sb tree [--compact] [--json]` prints the same tree.

`sb init` also writes `.claude/settings.json` (plugins, marketplaces and the deny rules
`Edit(/_raw/**)`, `git push --force`/`-f`, `git reset --hard`, `git clean`; never overwritten, `--upgrade` only adds what is missing),
`_meta/web-clipper-template.json`, `_views/unreviewed.base` and a `.gitignore` (`.sb/`,
`.obsidian/workspace*`, `.smart-env/`, and in squad vaults `_index.md` and `_log.md`).

### Upgrading a v0.1 vault

`sb init --upgrade` prints what it would add (missing `_about.md`, settings, templates, `.gitignore`
lines, `schema_version: 2`) and changes nothing; `sb init --upgrade --yes` applies it. It never
overwrites a file you have; it lists them as kept. An existing `.claude/settings.json` is merged
additively (missing plugins, marketplaces and deny rules are appended, nothing you have is changed
or removed); if it is not valid JSON it is left untouched and a warning is printed. `--profile squad` also turns a vault into a squad
vault and runs `git rm --cached` on `_index.md` and `_log.md`. Running it again reports no action.

### Squad vaults (2-5 people, one git remote)

1. One person runs `/second-brain:init`, chooses `squad`, gives the remote URL and pushes.
2. Everyone else clones the repository, installs the plugin with `--scope project` and runs `claude`
   in it.
3. **SessionStart** (squad vaults only) commits a dirty tree as `sb: local changes before sync`,
   then runs `git pull --rebase` (20 s limit). It never uses `--autostash`. If the rebase conflicts
   it runs `git rebase --abort`, keeps both commits, and the status line says
   `sync conflict: <files>`; resolve it yourself with git. A failed push from an earlier session is
   retried.
4. **SessionEnd** (60 s timeout) commits as the git-configured user with the message
   `sb: session YYYY-MM-DD (N files)` and the trailers `Sb-Session: <session id>` and
   `Sb-Files: <n>`, then runs `git push` (45 s). If the push fails (offline, rejected) it writes
   `.sb/push-pending` and the next SessionStart retries.
5. `_index.md` and `_log.md` stay local: each person regenerates them. There is no secret scanning
   before a push.

## Skills

| Skill | What it does | Example |
| --- | --- | --- |
| `init` (user-invoked only) | Creates a vault from a profile (folders with `_about.md`, settings, templates), upgrades v0.1 vaults, runs `sb doctor`; never overwrites | `/second-brain:init squad pt-BR` |
| `capture` | Saves text verbatim into `_inbox/`, no organising | `/second-brain:capture read about interleaving` |
| `ingest` | Turns one source (inbox clip, `_raw/` file, pdf, docx, pptx, xlsx, URL) into N atomic notes or `[!agent]` blocks, with provenance and no duplicates | `/second-brain:ingest` |
| `find` | Answers from the vault with `sb search`, cites `[[Note]]`, labels unreviewed notes, admits gaps; also fires on implicit questions ("how did I do X again?") | `/second-brain:find spaced repetition` |
| `link` | Proposes wikilinks and surfaces orphans; applies only approved ones | `/second-brain:link Zettelkasten` |
| `update` | Applies a requested change keeping provenance and every trust field; on human or reviewed notes it offers an agent block or an approved edit | `/second-brain:update Active Recall add an example` |
| `lint` | Runs `sb lint`, proposes fixes, applies none without approval | `/second-brain:lint` |

## The `sb` CLI

`bin/sb` is on the Bash tool's `PATH` while the plugin is enabled. Every command accepts
`--vault PATH` (default: walk up from the working directory to `.second-brain.json`) and `--json`.

| Command | Behaviour |
| --- | --- |
| `sb index --write` / `--check` | Rebuild `_index.md` deterministically; `--check` exits `1` on drift and prints the diff |
| `sb search QUERY [--limit N] [--folder-boost FOLDER=W]` | Ranked, accent-insensitive search; `--json` gives `rel`, `name`, `title`, `folder`, `summary`, `score`, `matched`, `trust`; exits `1` with no result |
| `sb eval --qrels FILE` | Recall@5, Recall@10 and MRR of `sb search` over a JSONL file of queries and expected notes |
| `sb lint [--verbose]` | Run SB101–SB112; codes with more than 20 findings are summarised unless `--verbose` |
| `sb links NOTE [--suggest]` | Outgoing links, backlinks, unresolved links; `--suggest` lists unlinked exact title mentions |
| `sb review NOTE` | Run by the human, never by the agent (the guard denies it): sets `reviewed: <today>` and `reviewed_hash` on a note, changing no other line |
| `sb validate FILE...` | Fast frontmatter checks for notes under `wiki/` |
| `sb source add TARGET` | Source id of a file, inbox note or URL (`sha256:<16 hex>` or `url:<canonical url>`) and the notes already made from it: `{source_id, kind, status: new\|seen, notes}` |
| `sb source save SOURCE_ID --tool T --origin O` | Reads extracted Markdown on stdin, strips invisible characters and HTML comments, flags lines that look like instructions to a model (`suspicious`), writes `_raw/.converted/<id>.md` |
| `sb inbox done FILE --title T` | Moves an item from `_inbox/` to `_inbox/_done/` without overwriting and logs `ingest`; the last step of `ingest` |
| `sb log EVENT TITLE` | Append `## [date] EVENT \| TITLE` to `_log.md` (`init capture ingest update link lint`) |
| `sb tree [--compact]` | Folders under `wiki/` with their `_about.md` description; `--compact` is the at-most-2,000-character form the hook injects |
| `sb doctor` | Five checks, each `ok`, `warn` or `fail` with a fix: Python and FTS5; `.claude/settings.json`; extraction tools (`pandoc`, `markitdown`, `pdftotext`, `npx`, `pypdf`); hooks heartbeat younger than 7 days; git (and, for squad, remote, upstream, no `push-pending`). Exits `1` on a `fail` and ends with the recommended Obsidian setup |
| `sb init [--profile P] [--language L] [--areas a,b] [--git] [--remote URL]` | Scaffold a vault (`personal` by default); writes `.second-brain.json` last; idempotent; refuses a directory inside another git repository (exit `2`) |
| `sb init --upgrade [--profile P] [--yes]` | Migrate a v0.1 vault: adds missing files only; dry run unless `--yes` |

Exit codes: `0` ok, `1` findings, `2` usage error or not inside a vault.

| Code | Finding |
| --- | --- |
| SB101 | Broken wikilink |
| SB102 | `summary` missing or empty |
| SB103 | Orphan note (no backlinks from other notes) |
| SB104 | Duplicate basename or title |
| SB105 | `_index.md` out of sync with `wiki/` |
| SB106 | `origin: agent` note without `reviewed` |
| SB107 | `schema_version` older than the CLI's (`run sb init --upgrade`) |
| SB108 | Frontmatter unparseable, unknown enum, bad date or missing key |
| SB109 | `source` path does not exist |
| SB110 | Reviewed text changed since `reviewed_hash` was recorded (fails `sb lint`; review again) |
| SB111 | Folder under `wiki/` has no `_about.md` (information; does not fail `sb lint`) |
| SB112 | Note has `> [!agent]` blocks waiting for review (information; does not fail `sb lint`) |

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

## Ingest and trust

`ingest` extracts a source with the dependency skills (or `pdftotext`, `pandoc`, `markitdown`,
`npx defuddle`), pipes the Markdown through `sb source save`, then writes N notes or additions. A
`source_id` on every note and `[!agent]` block means ingesting the same source twice (also the same
URL with tracking parameters or a trailing slash) reports `seen` and creates nothing. The inbox item
moves to `_inbox/_done/` only after the notes exist. Third-party text is data, never instructions.

Who may write what is decided by the note's **trust tier**:

| Tier | Which notes | Agent writes |
| --- | --- | --- |
| T0 | `origin: agent` and no `reviewed` | Free |
| T1 | `origin` human or mixed (or missing), or `reviewed` set | Appending a `> [!agent]` block or adding `[[links]]` passes; anything else asks you |
| T2 | `protected: true`, `status: evergreen`, or a note under a folder whose `_about.md` says `protected: true` | Every change (including a new note in that folder) asks you |

An addition to a T1 note is a callout at the end of the note, with exactly this header:

```
> [!agent] 2026-11-02 · sha256:ab12cd34ef56ab78
> The added text, every line prefixed with "> ".
```

**The agent never sets `reviewed`.** The trust fields `reviewed`, `reviewed_hash`, `protected` and
`origin` belong to you: the guard denies any agent write that changes them, requires `origin: agent`
on every new note, and denies running `sb review` through Bash. The same holds for the `protected`
key of a folder's `_about.md`; any other edit of an `_about.md` asks you, and Bash may not write one.
Mark a note reviewed yourself (see [Reviewing](#reviewing)); until you do, `SB106` and the
`unreviewed` label keep the note visible.

## Reviewing

A review is verifiable. `reviewed_hash` pins the text you reviewed: `sha256:` plus the first 16 hex
digits of the SHA-256 of the **review body**, which is the note body after the frontmatter, without
trailing `> [!agent]` blocks, with trailing spaces and tabs removed from each line, CRLF read as LF
and leading and trailing blank lines dropped. Reformatting the frontmatter (Obsidian does this), a
phone editor adding CRLF, or an agent block appended later does not change it; editing the reviewed
text does, and then `sb lint` reports `SB110` (it fails the lint) until you review again. A note
with trailing agent blocks waiting for you gets `SB112` (information).

1. Open `_views/unreviewed.base` in Obsidian (Bases) to see the queue.
2. Open a note, read it, and run **Mark as reviewed** (writes `reviewed` and `reviewed_hash`) or, if
   it has agent blocks you accept, **Accept agent blocks** (turns them into plain text, then marks
   the note reviewed). **Toggle protected** flips `protected: true`.
3. Without Obsidian, run `sb review <note>` yourself in a terminal (or with the `!` prefix inside
   Claude Code). The agent cannot run it.

The commands and a status-bar badge (`reviewed`, `unreviewed`, `changed since review`,
`agent blocks pending`) come from the **second-brain-companion** Obsidian plugin, which works on
desktop and mobile. Install it with [BRAT](https://github.com/TfTHacker/obsidian42-brat): add the
repository `aether-labs-org/second-brain-companion`. That repository is **not published yet**, so
BRAT cannot install it today; until it is, use `sb review`. Python and the plugin share one set of
hash test vectors (`tests/fixtures/review-hash/vectors.json`), so they always agree.

## Protection and auto-commit

Five hooks, all no-ops in a directory without `.second-brain.json`:

- **PreToolUse guard** denies writes to `_raw/**`, `.claude/**`, the top-level `CLAUDE.md` and
  `.second-brain.json` (and `rm`/`mv`/`>` style Bash commands that target them), asks before
  deleting anything under `wiki/`, and decides every `Write`/`Edit`/`MultiEdit` on a note by its
  trust tier (see [Ingest and trust](#ingest-and-trust)). It is **fail-closed**: inside a vault an
  internal error blocks the call (exit 2, hook `onFailure: "block"`); outside a vault it stays
  silent. Edit the protected files yourself.
- **UserPromptSubmit recall** adds candidate notes to the context (see [Recall](#recall)).
- **PostToolUse check** runs the frontmatter checks on a note the agent just wrote, reports
  problems back to it and rewrites `_index.md` when it drifted.
- **SessionStart** injects the folder tree and status, records `.sb/heartbeat.json` (for
  `sb doctor`), regenerates `_index.md` when it drifted and, in squad vaults, pulls (see
  [Squad vaults](#squad-vaults-2-5-people-one-git-remote)).
- **SessionEnd auto-commit**: when the vault has a `.git`, `auto_commit` is on and there are
  changes, runs `git add -A` and commits `sb: session YYYY-MM-DD (N files)` with the `Sb-Session`
  and `Sb-Files` trailers. **One commit per session; local only, except in squad vaults, where the
  commit is pushed.** It is skipped during a merge or rebase. Turn it off in the
  plugin's settings (`/plugin` → configure `auto_commit`) or set the `auto_commit` user option to
  `false`.

## Recommended Obsidian setup

`sb doctor` ends with this table.

| Need | Recommendation | Note |
| --- | --- | --- |
| Agent inside Obsidian | *Terminal* (polyipseity) | Runs the real `claude`, so the hooks apply. This is the only supported path; Claudian and Agent Client are not |
| Web capture | Obsidian Web Clipper + `_meta/web-clipper-template.json` | Saves to `_inbox/` with `title`, `url`, `captured`. Import it under Web Clipper settings, Templates, Import |
| Review queue | Bases (core, Obsidian 1.9+) + `_views/unreviewed.base` | Lists `origin: agent` notes without `reviewed` |
| Review actions | `second-brain-companion` (BRAT: `aether-labs-org/second-brain-companion`, not published yet) | Mark as reviewed, Accept agent blocks, Toggle protected, status badge; `sb review` meanwhile |
| Squad | Obsidian Git: pull on startup, rebase (not merge), auto commit-and-sync at an interval for human edits | The plugin commits and pushes agent edits at session end; Git on mobile is unstable |
| HTML | HTML Viewer with scripts **off** for third-party pages | |
| draw.io / Excalidraw | Drawio Preview; Excalidraw (zsviczian) | `*.excalidraw.md` is not treated as a note |
| Human search | Omnisearch, Smart Connections (optional) | The agent does not use them |
| Avoid | Linter | Rewrites frontmatter on save: breaks hashes and creates ghost diffs in squad vaults |

## Limits

- The trust tiers cover `Write`, `Edit` and `MultiEdit`. A Bash command that rewrites a note
  (`python -c`, `perl -pi`) is outside the guard; git is the net.
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
| AC2 | `ingest` yields valid notes, updates index and log, no duplicate | `evals/ingest-twice`, `evals/ingest-1ton`, `tests/python/test_sb_source.py`, `tests/python/test_sb_cli.py` |
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
