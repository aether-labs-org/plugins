# Second Brain

This directory is a **local-first Second Brain**: plain markdown notes, operated by Claude Code
through the `second-brain` plugin. Run `claude` from this directory.

Notes are written in **{{language}}**.

## Map

- `wiki/` — curated knowledge. The human reads it. `Projects/` (active, with a deadline),
  `Areas/` (ongoing responsibilities), `Resources/` (concepts, entities, references),
  `Archive/` (inactive).
- `_inbox/` — raw captures. The human writes, the agent processes. Processed items go to
  `_inbox/_done/`.
- `_raw/` — immutable source files (PDFs, articles, transcripts). The human places them here.
  **Read-only for the agent.**
- `_index.md` — generated catalogue, one line per note. Never edit by hand; run `sb index --write`.
- `_log.md` — append-only event log. Use `sb log`.
- `.second-brain.json` — vault marker and configuration (`schema_version`, language, areas).

Everything outside `wiki/` is system. The `_` prefix marks paths the agent operates.

## Rules

1. Knowledge lives in `wiki/`. Never write outside it unless asked, except `_inbox/`,
   `_index.md` and `_log.md` through the skills.
2. **Never invent.** Synthesise only what is written in this vault or in the source being
   ingested. Never invent facts, links or connections. Cite the source note as `[[Note]]`.
3. `_raw/` is read-only. Never delete anything without asking first.
4. The human owns the interpretation. The agent does the clerical work: formatting, links,
   index. Notes the agent writes carry `origin: agent`; the human sets `reviewed:` after checking.
5. Search `wiki/` first (`_index.md`, then `rg "^summary:"`). Open `_raw/` only to verify a source.
6. Link only to notes that exist. Note names are unique, so `[[Name]]` survives folder moves.
7. `CLAUDE.md`, `.claude/` and `.second-brain.json` are edited by the human, not the agent.

## What deserves a note

Persist something only if it is **useful**, **new or surprising**, **carries the author's
interpretation**, and **will be reused**. Skip what is ephemeral, already mastered, or trivially
found on the web. Raw captures stay in `_inbox/` unorganised.

## Note format

```yaml
---
title: Note title
summary: One line. Required. This is what triage reads.
type: nota            # nota | fonte | projeto | conceito
status: seed          # seed | draft | evergreen
origin: agent         # agent | human | mixed
created: 2026-01-31   # ISO date
source: _raw/x.pdf    # path under _raw/ or _inbox/, or [[Note]]
reviewed:             # optional ISO date, set by the human
tags: [a, b]          # optional, few, lowercase
---
```

Frontmatter is a restricted subset: `key: value` scalars and inline `[a, b]` lists only.
Notes are atomic. Prefer links and frontmatter to tag taxonomies.

## Workflow

- `/second-brain:capture` — drop raw text into `_inbox/`.
- `/second-brain:ingest` — turn an inbox item into an atomic note, update index and log.
- `/second-brain:find` — answer from the vault, citing notes.
- `/second-brain:link` — propose links between notes.
- `/second-brain:update` — revise an existing note.
- `/second-brain:lint` — check the vault; proposes fixes, applies none without approval.
- `sb lint`, `sb index --check`, `sb links <note> --suggest` run directly in a terminal.

Changes are committed locally by the plugin when this directory has a `.git` (setting
`auto_commit`). Review with `git diff`; revert with `git`.
