# Second Brain

Local-first Second Brain: plain markdown notes, operated by Claude Code through the `second-brain`
plugin. Run `claude` from this directory. Notes are written in **{{language}}**.

## Map

- `wiki/<folder>/` — notes. File them by each folder's `_about.md` (`sb tree` prints them).
- `_inbox/` — raw captures; processed items go to `_inbox/_done/`.
- `_raw/` — originals the human wants versioned. Read-only for the agent.
- `_assets/` — images and attachments that notes embed; flat.
- `_views/` — Obsidian Bases (`unreviewed.base`, `notes.base`).
- `.agents/second-brain/` — `config.json`, `converted/` (sanitised copies of ingested sources,
  read-only) and `cache/`.

## Rules

1. Never invent. Write only what this vault or the source being ingested says; cite `[[Note]]`.
   Never fill a gap: a missing date, reason or name stays missing; ask.
2. Search before answering: `sb search "<terms>"`. Open the candidates and answer from them first;
   anything you add that they do not say goes after it, marked "(conhecimento geral)". Say when a
   note is unreviewed.
3. `_raw/` and `.agents/second-brain/converted/` are read-only. Delete nothing without asking.
4. Notes you create carry `origin: agent`. Set `reviewed` only when the user asks for that note.
5. An addition to a human or reviewed note goes at its end as
   `> [!agent] <YYYY-MM-DD> · <source>`, every line prefixed `> `.
6. Keep `created` and `source`. Do not rename notes. Run `sb tree` before creating one. Link only
   to notes that exist, inline on the term.
7. `CLAUDE.md` and `.claude/` are edited by the human.

## What deserves a note

Something **useful**, **new or surprising**, with the author's interpretation, that **will be
reused**. Skip the ephemeral, the mastered and what is trivially found on the web.

## Frontmatter

```yaml
---
summary: One line. Required; search and recall show it.
origin: agent          # agent | human. Required.
created: 2026-11-10    # ISO date. Required.
source: ~/a.pdf        # optional: vault path, ~/ or absolute path, or URL
reviewed: 2026-11-12   # optional, set by the human
tags: [a, b]           # optional
aliases: [Other name]  # optional; search uses them
title: Other title     # optional; default is the file name
---
```

Only `key: value` scalars, inline `[a, b]` lists and block lists (`- item`).

## Body

- Start with the content: no preamble, no closing recap, no comment on the source or on how the
  note was made, no repeat of `summary`.
- Length follows the content; no minimum, no padding. Lists, tables and headings only where the
  content has that shape.
- No fixed section template: follow the folder's `_about.md` conventions.
- No adjective, hedge or emphasis the source does not carry; no emoji.
- No "Related" section of weak links.

## Skills

`/second-brain:capture`, `ingest`, `find`, `lint`. In a terminal: `sb search`, `sb lint`,
`sb tree`, `sb links <note> --suggest`. The plugin commits each session to git; review with
`git log -p`.
