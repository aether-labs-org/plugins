---
name: update
description: >
  Applies a change the user asked for to an existing Second Brain note while preserving its
  provenance: keeps created and source, adjusts origin, clears reviewed, refreshes the index and
  logs it. Use for "update my note on X", "correct this", "add this to the note about Y".
argument-hint: "[note name] [change]"
allowed-tools: Read Edit Grep Glob Bash(sb *) Bash(rg *)
---

# Update a note

The change comes from the user. Do not "improve" a note beyond what was asked.

## Procedure

1. Resolve the note: `$ARGUMENTS`, then `rg --files wiki | rg "/<name>\.md$"`. If zero or
   several match, ask.
2. Read it and `CLAUDE.md`. Edit only what the request touches.
3. Preserve `created` and `source`. If `origin` was `human`, set it to `mixed`. If you changed the
   content, remove the `reviewed:` value (the human must review again).
4. If the `summary` no longer matches the body, update it to one accurate line.
5. Do not rename the note. A rename breaks `[[links]]`; if the user wants one, say so and propose
   the edits to every note that links to it (`sb links "<note>"`).
6. Run `sb validate <path>`, `sb index --write`, `sb log update "<Title>"`.
7. Show what changed in two or three lines and mention `git diff`.
