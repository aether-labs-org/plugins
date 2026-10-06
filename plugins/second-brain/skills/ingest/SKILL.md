---
name: ingest
description: >
  Turns an _inbox/ capture or a named _raw/ source into one atomic wiki/ note with complete
  frontmatter, links to existing notes only, then updates _index.md and _log.md. Updates an
  existing note instead of duplicating. Use for "ingest", "process my inbox", "add this to my notes".
argument-hint: "[_inbox/file.md | _raw/file]"
allowed-tools: Read Write Edit Grep Glob Bash(sb *) Bash(rg *) Bash(mv *) Bash(date *)
---

# Ingest an item

Read `CLAUDE.md` first: it holds the vault rules and the note format. Use **only** what is
written in the item and in existing notes. Never invent facts or connections.

## Procedure

1. **Pick the item.** `$ARGUMENTS`, else list `_inbox/*.md` (not `_inbox/_done/`) and ask which.
   If there is none, say so and stop.
2. **Read it.** Apply the persistence criteria from `CLAUDE.md` (useful, new or surprising,
   carries the author's interpretation, will be reused). If it fails, say why and ask whether to
   drop it or ingest anyway. Do not delete.
3. **Move an inbox item first.** `mv _inbox/<file> _inbox/_done/<file>` (skip if it is already in
   `_done/`). The item's path from now on is `_inbox/_done/<file>`; a `_raw/` source keeps its path.
   Never write to `_raw/`.
4. **Look for an existing note** (idempotency):
   - `rg -l -F "source: <item path>" wiki/` — a hit means this item was already ingested;
   - `rg -i -l "<key terms>" wiki/` and `_index.md` for the same topic.
   If a note exists, **update it** (go to step 6); never create a second note for the same item.
5. **Create the note** at `wiki/<Projects|Areas|Resources>/<Name>.md` (never `Archive`):
   - `Name` is unique: check `rg --files wiki | rg "/<Name>\.md$"` first; atomic, one idea;
   - frontmatter complete: `title`, one-line `summary` (in the vault language), `type`,
     `status: seed`, `origin: agent`, `created: <today>`, `source: <item path>`;
   - body: the idea in the author's terms. Keep their interpretation; add nothing they did not say.
   - no `tags` unless the item itself names them; never invent tags.
6. **Update** (existing note): merge only what is new, keep `created` and the original `source`,
   mention the extra item under a `Sources` line, set `origin: mixed` if it was `human`, and clear
   `reviewed`.
7. **Link.** Run `sb links "<Name>" --suggest`. Add `[[wikilinks]]` only to notes that exist and
   that the text genuinely relates to; suggestions are candidates, not orders.
8. **Close.** `sb validate wiki/.../<Name>.md`, `sb index --write`, `sb log ingest "<Title>"`.
9. **Report** the note path, whether it was created or updated, the links added, and say the
   user can review with `git diff`.

Running this twice on the same item must end with the same single note.
