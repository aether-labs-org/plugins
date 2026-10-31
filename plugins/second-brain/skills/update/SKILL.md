---
name: update
description: >
  Applies a change the user asked for to an existing Second Brain note while preserving its
  provenance: keeps created, source and every trust field, and offers an agent block or an
  approved in-place edit on human or reviewed notes. Use for "update my note on X", "correct this".
argument-hint: "[note name] [change]"
allowed-tools: Read Edit Grep Glob Bash(sb *) Bash(rg *) Bash(date *)
---

# Update a note

The change comes from the user. Do not "improve" a note beyond what was asked.

## Procedure

1. Resolve the note: `$ARGUMENTS`, then `rg --files wiki | rg "/<name>\.md$"`. If zero or
   several match, ask.
2. Read it and `CLAUDE.md`. Edit only what the request touches.
3. Preserve `created` and `source`. Never change `origin`, `reviewed`, `reviewed_hash` or
   `protected`: only the human sets them and the guard blocks the write.
   - Note by the agent, not yet reviewed: edit freely.
   - Human or reviewed note: offer the user two ways. **Append an agent block**
     (`> [!agent] <YYYY-MM-DD> · <source_id or "user">` at the end, lines prefixed `> `), which
     needs no approval; or **edit in place**, where the guard asks the user to approve.
   - Protected or evergreen note: the guard asks for every change.
4. If the `summary` no longer matches the body, update it to one accurate line.
5. Do not rename the note. A rename breaks `[[links]]`; if the user wants one, say so and propose
   the edits to every note that links to it (`sb links "<note>"`).
6. Run `sb validate <path>` and `sb log update "<Title>"`. The index updates itself.
7. Show what changed in two or three lines and mention `git diff`.
