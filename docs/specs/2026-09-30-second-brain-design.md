# second-brain — Design Spec (v0.1)

**Date:** 2026-09-30
**Status:** implemented in v0.1.0; see plan `2026-10-01-second-brain-plan.md`
**Repository:** `aether-labs-org/plugins` (monorepo; marketplace `aether-labs`)
**Source material:** the *Second Brain (Obsidian + Claude Code)* implementation spec from the prior
conversation (claude.ai artifact `KVJcHg5U7tn4C8qUChFuxh`). This document supersedes it where the two
differ; every difference is listed in §12.

---

## 1. What this is

A Claude Code plugin that operates a **local-first Second Brain**: a folder of plain markdown notes
that the agent can capture into, organise, query, relate and update, with deterministic tooling
doing the mechanical work and git as the safety net.

**The rule that defines v0.1: deterministic first.** Search is `ripgrep` + frontmatter + wikilinks.
There are no embeddings, no vector index and no MCP server. Each of those is a later phase with a
stated trigger (§11). Everything the plugin persists lives in the user's vault; nothing leaves the
machine except the model calls Claude Code itself makes.

## 2. Requirements and decisions

| # | Decision | Status |
| --- | --- | --- |
| D1 | v0.1 is skills + a deterministic Python CLI + hooks. No semantic search, no MCP | decided |
| D2 | Vault is plain markdown with YAML frontmatter and `[[wikilinks]]`. Obsidian-compatible, not Obsidian-dependent | decided |
| D3 | Vault root = repository root = the directory where `claude` runs | decided (prior spec) |
| D4 | `wiki/` holds curated knowledge; everything outside it is system. `_` prefix marks agent-operated paths | decided (prior spec) |
| D5 | `_raw/` is immutable to the agent | decided (prior spec) |
| D6 | Skills hold procedures, never knowledge | decided (prior spec) |
| D7 | Auto-commit is **on by default**, only when the vault has a `.git`, local commits only, opt-out via `userConfig` | decided (this session) |
| D8 | CLI is Python 3.9+, standard library only. Frontmatter is a restricted YAML subset (§4) | proposed |

Non-goals for v0.1: semantic search, GraphRAG, MCP, an Obsidian plugin, web clipping, multi-user
sync, encryption, a GUI.

## 3. Plugin layout

```
plugins/second-brain/
├── .claude-plugin/plugin.json     # name, version 0.1.0, userConfig.auto_commit
├── skills/
│   ├── init/SKILL.md              # user-invoked only
│   ├── capture/SKILL.md
│   ├── ingest/SKILL.md
│   ├── find/SKILL.md
│   ├── link/SKILL.md
│   ├── update/SKILL.md
│   └── lint/SKILL.md
├── bin/sb                         # CLI entry point (on the Bash tool's PATH while enabled)
├── lib/sb/                        # CLI implementation (importable, unit-tested)
├── hooks/
│   ├── hooks.json
│   ├── guard.py                   # PreToolUse
│   ├── validate_note.py           # PostToolUse
│   └── autocommit.py              # SessionEnd
├── templates/                     # vault CLAUDE.md, .second-brain.json, .gitignore lines
├── evals/                         # skill trigger / behaviour evals
└── README.md
```

Registered in `.claude-plugin/marketplace.json`, the root `README.md`, `Makefile`
(`claude plugin validate ./plugins/second-brain --strict`) and `tests/`.

Facts from the current plugin documentation that shape this layout:

- A plugin's `settings.json` only honours `agent` and `subagentStatusLine`, so the prior spec's
  permission denies cannot ship in the plugin. The `PreToolUse` guard replaces them.
- A `CLAUDE.md` at the plugin root is not loaded as context. The vault's own `CLAUDE.md` (created
  by `init`) carries the rules, and skills carry the procedures.
- `bin/` executables are on the Bash tool's `PATH` while the plugin is enabled. Plugins with
  `bin/` are not installed on claude.ai or Cowork; the target here is Claude Code only.
- Hooks of an enabled plugin fire in **every** session, so each hook must be a no-op outside a
  vault (§6).
- Every skill's name and description is in context on every turn. Descriptions stay short.

## 4. Vault contract

### 4.1 Layout created by `init`

```
<vault>/
├── CLAUDE.md               # rules, < 200 lines (from template)
├── .second-brain.json      # marker + config: schema_version, language, areas
├── _inbox/                 # raw captures (human writes, agent processes)
│   └── _done/              # processed captures
├── _raw/                   # immutable sources (human places files here)
├── _index.md               # generated catalogue
├── _log.md                 # append-only event log
├── wiki/{Projects,Areas,Resources,Archive}/
└── .gitignore              # .obsidian/workspace*, .smart-env/
```

### 4.2 Frontmatter (every note in `wiki/`)

```yaml
---
title: Note title
summary: One line. Required. This is what triage reads.
type: nota            # nota | fonte | projeto | conceito
status: seed          # seed | draft | evergreen
origin: agent         # agent | human | mixed
created: 2026-09-30   # ISO date
source: _raw/x.pdf    # path under _raw/ or _inbox/, or [[Note]]; provenance
reviewed:             # optional ISO date; set by the human when an agent note is checked
tags: [a, b]          # optional; few, lowercase
---
```

The parser accepts only `key: value` scalars and inline `[a, b]` lists. Anything else (nested maps,
block lists, multi-line scalars) is a `SB108` lint error rather than a silent misparse. This is the
price of having no YAML dependency (D8).

### 4.3 Conventions

- Notes are atomic; file basenames are unique across `wiki/` so `[[Name]]` survives moves.
- Wikilinks: `[[Name]]`, `[[Name|alias]]`, `[[Name#Heading]]`. A link resolves by basename
  (case-sensitive, without `.md`). Links inside fenced code and inline code are ignored.
- Only link to notes that exist. Never invent links.
- `_index.md` is fully generated: one line per note, `- [[Name]]: summary`, sorted by
  casefolded basename. Manual edits are overwritten.
- `_log.md` is append-only, one parseable line per event: `## [2026-09-30] ingest | Title`.
  Events: `init`, `capture`, `ingest`, `update`, `link`, `lint`.
- Persistence criteria (what earns a place in `wiki/`): useful, new or surprising, carries the
  author's interpretation, will be reused. Ephemeral, already-mastered or trivially re-findable
  material stays in `_inbox/` or is dropped.

## 5. CLI: `sb`

Every command accepts `--vault PATH` (default: walk up from the working directory until
`.second-brain.json` is found) and `--json`. Exit codes: `0` ok, `1` findings, `2` usage error or
not inside a vault.

| Command | Behaviour |
| --- | --- |
| `sb index --write` / `--check` | Rebuild `_index.md` deterministically from note summaries; `--check` exits `1` on drift and prints the diff |
| `sb lint` | Runs the rule set below; `--json` emits `{code, path, line, message}` records |
| `sb links NOTE [--suggest]` | Outgoing links, backlinks, unresolved links; `--suggest` lists unlinked exact mentions of other notes' titles |
| `sb validate FILE...` | Frontmatter and naming checks for the given notes (subset of lint, fast) |
| `sb log EVENT TITLE` | Atomic append to `_log.md` with today's date |
| `sb init [--language L] [--areas a,b] [--git]` | Scaffold a vault; writes `.second-brain.json` last; idempotent |

### Lint rules

| Code | Finding |
| --- | --- |
| SB101 | Broken wikilink |
| SB102 | `summary` missing or empty |
| SB103 | Orphan note (no backlinks from other notes; `_index.md` does not count) |
| SB104 | Duplicate basename or title |
| SB105 | `_index.md` out of sync with `wiki/` |
| SB106 | `origin: agent` note without `reviewed` |
| SB107 | `schema_version` in `.second-brain.json` older than the CLI's |
| SB108 | Frontmatter unparseable, unknown enum value, bad date, or missing required key |
| SB109 | `source` path does not exist |

Contradictions between notes are **not** deterministic. The `lint` skill looks for them with the
model and labels the result "suggestion, not verified".

### Error handling

- Malformed frontmatter or an unreadable file becomes a per-file finding; it never aborts the run.
- `_index.md` and `_log.md` are written to a temporary file and renamed into place.
- Missing vault → exit `2` with a message naming the search start directory and suggesting
  `/second-brain:init`.
- Nothing in the CLI deletes or rewrites notes. It only reads them and writes `_index.md` and
  `_log.md`.

## 6. Hooks

All hooks are no-ops when no `.second-brain.json` is found upward from the working directory.

| Event | Script | Behaviour |
| --- | --- | --- |
| `PreToolUse` on `Write`, `Edit`, `MultiEdit`, `NotebookEdit`, `Bash` | `guard.py` | **Deny** writes to `_raw/**`, `.claude/**`, `CLAUDE.md`, `.second-brain.json`, with a message telling the human to edit those directly. **Ask** before deleting anything under `wiki/` (including `rm` via Bash). Best-effort match of `rm`/`mv`/`>` targeting protected paths in Bash. The guard's own crash allows the call |
| `PostToolUse` on `Write`, `Edit`, `MultiEdit` | `validate_note.py` | Runs `sb validate` on a touched `wiki/` note and returns findings to the agent |
| `SessionEnd` | `autocommit.py` | If enabled, `.git` exists, there are changes and no merge/rebase is in progress: `git add -A` and commit `sb: session YYYY-MM-DD (N files)`. Never pushes. Always exits `0`; failures go to stderr. Commits are per session: `Stop` fires after every response, so it was not used |

`userConfig`:

```json
{
  "auto_commit": {
    "type": "boolean",
    "title": "Auto-commit vault changes",
    "description": "At the end of each session, commit changes locally when the vault has a .git directory. Never pushes.",
    "default": true
  }
}
```

The SessionEnd hook reads `CLAUDE_PLUGIN_OPTION_AUTO_COMMIT`. Shell-form hooks may not reference
`${user_config.*}`, so the script reads the environment variable itself.

**Known limit.** Bash cannot be fully fenced by a hook: a determined command can write to `_raw/`
in ways a pattern match will not see. The guard stops the ordinary mistakes; git is the real
safety net, and the README says so.

## 7. Skills

Skill text states procedure and points at the vault's `CLAUDE.md` for rules. The anti-hallucination
rule appears in every skill that synthesises: *use only what is written in the vault or the source;
never invent facts or connections; cite the source note.*

- **`init`** (user-invoked only). Idempotent. Asks at most three questions: note language, whether
  to `git init` (skipped if `.git` exists), initial areas. Creates the layout in §4.1, never
  overwrites an existing `CLAUDE.md`, appends missing lines to `.gitignore`, writes
  `.second-brain.json` **last** (the guard treats that file as the vault marker, so writing it
  earlier would block `CLAUDE.md` creation). If the marker already exists it reports and changes
  nothing. Logs `init`.
- **`capture [text]`**. Writes the text verbatim to `_inbox/YYYY-MM-DD-HHMM-slug.md` with a
  two-key header (`captured`, `from`). No organising, no linking. Logs `capture`.
- **`ingest [item]`**. Reads an item from `_inbox/` (or a named file in `_raw/`). Applies the
  persistence criteria. Searches for an existing note by `source` (written as `_inbox/_done/<file>`, the path after the move) and by title; if found,
  **updates** it, otherwise creates one atomic note in the right `wiki/` folder with complete
  frontmatter (`origin: agent`). Links only to existing notes. Runs `sb index --write` and
  `sb log ingest`, moves the processed item to `_inbox/_done/`, and shows a summary for review via
  `git diff`. Re-running on the same item is a no-op update, never a duplicate.
- **`find [topic]`**. Reads `_index.md`, then `rg` over `summary:` and titles in `wiki/`, opens at
  most three notes, and answers citing `[[Note]]`. If nothing matches it says the vault does not
  cover the topic. `_raw/` is opened only to verify a source.
- **`link [note]`**. Runs `sb links --suggest`, presents candidate links and orphans, and applies
  only the ones the user approves. Links to existing notes only. Logs `link`.
- **`update [note] [change]`**. Applies a change the user requested to an existing note. Keeps
  `created` and `source`; turns `origin: human` into `mixed`; clears `reviewed` because the
  content changed; refreshes the index line; logs `update`.
- **`lint`**. Runs `sb lint --json`, groups findings, proposes fixes, applies none without
  approval. Adds a clearly labelled, unverified pass for contradictions between notes.

## 8. Data flow

```
human ──capture──▶ _inbox/  ──ingest──▶ wiki/  ──▶ sb index --write ─▶ _index.md
                      │                   ▲                              │
                      └─▶ _inbox/_done/   │                              ▼
_raw/ (human-placed, read-only) ──────────┘        find ◀── _index.md + rg summaries
                                                    link / update / lint operate on wiki/
every mutating skill ─▶ sb log ; SessionEnd hook ─▶ local git commit
```

## 9. Testing

Follows the repo's `tests/*_test.sh` + `tests/python` convention; `make check` runs everything.

- **CLI unit tests** with fixture vaults: one valid, one with a planted broken link and a note
  without `summary`, plus a fixture per lint rule. Determinism test: `sb index --write` twice
  yields byte-identical output.
- **Frontmatter parser tests**: accepted subset, and each rejected construct producing `SB108`.
- **Hook tests**: guard blocks `_raw/`, `.claude/`, `CLAUDE.md`, `.second-brain.json`; allows
  `wiki/`; asks on deletion; is a no-op outside a vault; a guard crash allows. Autocommit tests in
  a temporary git repo: enabled and disabled, no changes, no `.git`, merge in progress, commit
  failure still exits `0`, never pushes.
- **Structure test**: `claude plugin validate ./plugins/second-brain --strict` is added to
  `make validate`.
- **Evals** (as in `solutions-architect`): trigger and should-not-trigger cases for each skill;
  `ingest` twice creates one note; `find` admits an empty result; `lint` reports the planted
  problems.

## 10. Acceptance criteria

| # | Criterion | Verified by |
| --- | --- | --- |
| AC1 | `init` creates the §4.1 layout, is idempotent, never overwrites `CLAUDE.md`, and the vault `CLAUDE.md` is under 200 lines | structure test, eval |
| AC2 | `ingest` turns an `_inbox/` item into a valid note, updates `_index.md` and `_log.md`, and does not duplicate on a second run | eval + CLI tests |
| AC3 | `find` answers citing notes and admits when nothing exists | eval |
| AC4 | `lint` reports the planted broken link and the note without `summary` | CLI test + eval |
| AC5 | A write to `_raw/` is blocked | hook test |
| AC6 | The SessionEnd hook commits when `.git` exists and `auto_commit` is on, and does nothing otherwise | hook test |
| AC7 | `ripgrep` finds every note, including under `_`-prefixed folders | CLI test |
| AC8 | `claude plugin validate --strict` passes | `make validate` |
| AC9 | Nothing beyond the minimum ships: no embeddings, no MCP server, no Obsidian plugins | structure test |
| AC10 | Hooks are no-ops in a directory without `.second-brain.json` | hook test |

## 11. Future phases (not in v0.1)

| Phase | What | Trigger |
| --- | --- | --- |
| F1 | Per-area `_index.md` files | Root index passes roughly 200–300 notes |
| F2 | Local lexical index (SQLite FTS5 through Python's `sqlite3`) | `rg` over `wiki/` becomes slow |
| F3 | Optional local semantic index (local embedding model, hybrid with grep, restricted to `wiki/`, off by default) | Thousands of notes **and** conceptual queries demonstrably failing on lexical search |
| F4 | Local MCP server | Live Obsidian state is required, and it beats direct filesystem access |

## 12. Differences from the prior spec

1. The plugin is built now instead of after weeks of use; the user asked for it. The prior spec's
   own requirements for `init` (idempotent, ≤3 questions, no personal data, rules in the vault)
   are kept.
2. Permission denies become a `PreToolUse` guard (plugins cannot ship permissions).
3. Processed inbox items move to `_inbox/_done/`, not "out of `_inbox/`", because the agent may not
   write to `_raw/`.
4. `.second-brain.json` holds `schema_version` and is the vault marker, instead of a line in
   `CLAUDE.md`.
5. New optional field `reviewed`, needed to implement the "agent notes never reviewed" check.
6. Auto-commit is on by default when `.git` exists (D7); the prior spec had a Stop-hook commit
   without a switch.
7. Added `capture`, `link` and `update` skills to cover the requested capture / relate / update
   operations.
8. `sb init` is a CLI subcommand (not only a skill) so scaffolding is testable.
9. Auto-commit runs on `SessionEnd`, not `Stop`: the documented `Stop` event fires after every
   response, which would produce one commit per response.

## 13. Risks

- **Auto-commit can commit half-finished notes.** Mitigated by local-only commits and one-line
  opt-out. Revert with git.
- **Restricted YAML subset** rejects frontmatter written by other tools. The error names the
  offending line so it can be fixed, and the subset can be widened later without a schema change.
- **Hook cost.** The guard runs Python on every matching tool call in every session. It exits
  before doing any work when no marker is found; the README documents the cost and how to disable
  the plugin.
- **Hook output semantics** (`ask` decisions, exec-form `args`) are to be confirmed against the
  hooks reference at implementation time and covered by the hook tests.
