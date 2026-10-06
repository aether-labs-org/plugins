---
name: lint
description: >
  Health-checks the Second Brain vault with the deterministic sb linter (broken links, missing
  summaries, orphans, duplicates, index drift, unreviewed agent notes, bad frontmatter), then
  proposes fixes and applies none without approval. Use for "lint my vault" or "check my notes".
allowed-tools: Read Edit Grep Glob Bash(sb *) Bash(rg *)
---

# Lint the vault

## Procedure

1. Run `sb lint --json`. Group the findings by code and print each as
   `CODE path:line message` so the user sees the codes.
2. Explain each group in one line:
   - `SB101` broken link · `SB102` missing summary · `SB103` orphan · `SB104` duplicate name/title
   - `SB105` index out of sync · `SB106` agent note not reviewed · `SB107` old schema
   - `SB108` bad frontmatter · `SB109` source file missing
3. Propose a concrete fix per finding, smallest first. Examples: for `SB105` run
   `sb index --write`; for `SB102` draft a one-line summary from the note body; for `SB101` suggest
   the closest existing note name or removing the link.
4. **Apply nothing** until the user approves, finding by finding or as a batch. Then apply, run
   `sb lint` again, and `sb log lint "<n> fixes"`.
5. Contradictions: after the deterministic pass, you may compare notes that share topics (use
   summaries from `_index.md`) and report conflicting claims. Label that section **suggestion, not
   verified** and quote both notes. Never edit notes to resolve a contradiction yourself.
6. `SB106` is cleared only by the human adding `reviewed: <date>`; offer to do it when they confirm
   they reviewed the note.
