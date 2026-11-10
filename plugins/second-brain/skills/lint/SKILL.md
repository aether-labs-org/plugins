---
name: lint
description: >
  Health-checks the Second Brain vault with the deterministic sb linter (broken links, missing
  summaries, orphans, duplicates, bad frontmatter, unreviewed agent notes), proposes fixes and
  link suggestions, and applies none without approval. Use for "lint my vault" or "check my notes".
allowed-tools: Read Edit Grep Glob Bash(sb *) Bash(rg *)
---

# Lint the vault

1. Run `sb lint --json`. Group findings by code and print `CODE path:line message`. Findings with
   `"info": true` never fail the run; mention them after the failures.
2. One line per code:
   - `SB101` broken link - `SB102` missing summary - `SB104` duplicate note name or title
   - `SB108` bad frontmatter (missing `summary`, `origin` or `created`, bad value or date)
   - `SB109` source missing; for a `~/` or absolute path it is information: the file may have
     moved, so ingest it again from its new place
   - info: `SB103` orphan note - `SB106` agent note not reviewed
3. Propose the smallest concrete fix per finding (a one-line summary drawn from the body, the
   closest existing note name, a link from another note). Apply nothing until the user approves,
   finding by finding or as a batch; then apply and run `sb lint` again.
4. Link work: for orphans, and on request, run `sb links "<Name>" --suggest` and propose
   `[[links]]` only to notes that exist and that the text genuinely relates to.
5. Contradictions: you may compare notes that share a topic (`sb search`) and report conflicting
   claims, quoting both, under **suggestion, not verified**. Never edit to resolve one.
6. `SB106` is cleared when the human sets `reviewed`. Never write `reviewed` yourself unless
   the user asks for that note.
