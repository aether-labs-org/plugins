---
name: link
description: >
  Relates notes in the Second Brain vault: lists a note's links and backlinks, proposes wikilinks
  for exact title mentions, and surfaces orphan notes. Applies only the links the user approves,
  and only to notes that exist. Use for "link my notes", "what relates to X", "find orphans".
argument-hint: "[note name]"
allowed-tools: Read Edit Grep Glob Bash(sb *) Bash(rg *)
---

# Link notes

Links are claims about how ideas relate. Propose; the human decides.

## Procedure

1. With a note: run `sb links "<note>" --suggest`. Without one: run `sb lint --json` and take the
   `SB103` findings (orphans) as the work list.
2. For each candidate, read both notes' summaries (and bodies if unclear) and judge whether the
   relation is real. Drop mere word coincidences.
3. Present a short table: source note, candidate target, the sentence/line, why it relates.
4. Apply only the links the user approves, with `Edit`. Link text must use the target's exact
   name: `[[Name]]`. Never link to a note that does not exist and never create stub notes.
5. For an orphan, say which existing notes could link to it; do not invent a parent.
6. Run `sb validate` on each edited note, then `sb log link "<note>"`.
