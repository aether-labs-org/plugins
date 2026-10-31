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
  **Read-only for the agent.** `_raw/.converted/` holds sanitised Markdown copies that
  `sb source save` generates during ingest: generated, read-only, never edit.
- `_index.md` — generated catalogue, one line per note. Never edit by hand; a hook rewrites it
  whenever a note changes (`sb index --write` does the same by hand).
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
   index. Trust fields (`reviewed`, `reviewed_hash`, `protected`, `origin`) are set by the human
   only; the agent never writes them on an existing note. Notes the agent creates carry
   `origin: agent`. Additions to human or reviewed notes go in blocks at the end of the note:
   `> [!agent] <YYYY-MM-DD> · <source_id>`, every line prefixed `> `.
5. Search before answering from memory: `sb search "<terms>"`. A `<second-brain-recall>` block
   lists candidate notes; open them before answering. Mark unreviewed notes in answers. Open
   `_raw/` only to verify a source.
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
source: _raw/x.pdf    # path under _raw/ or _inbox/, a URL, or [[Note]]
source_id: sha256:0123456789abcdef   # set by ingest; or url:<canonical url>
protected: true       # optional, human only: every agent change asks first
reviewed:             # optional ISO date, set by the human
tags: [a, b]          # optional, few, lowercase
aliases: [Other name] # optional list of alternative names; search uses them
---
```

Frontmatter is a restricted subset: `key: value` scalars, inline `[a, b]` lists and block lists
(`- item`).
Notes are atomic. Prefer links and frontmatter to tag taxonomies.

## Workflow

- `/second-brain:capture` — drop raw text into `_inbox/`.
- `/second-brain:ingest` — turn a source (inbox clip, `_raw/` file, pdf, docx, pptx, xlsx, URL)
  into atomic notes or `[!agent]` blocks, with provenance.
- `/second-brain:find` — answer from the vault with `sb search`, citing notes.
- `/second-brain:link` — propose links between notes.
- `/second-brain:update` — revise an existing note.
- `/second-brain:lint` — check the vault; proposes fixes, applies none without approval.
- `sb search`, `sb lint`, `sb index --check`, `sb links <note> --suggest` run directly in a terminal.

Changes are committed locally by the plugin when this directory has a `.git` (setting
`auto_commit`). Review with `git diff`; revert with `git`.
