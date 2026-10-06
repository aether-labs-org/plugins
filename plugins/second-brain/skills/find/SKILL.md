---
name: find
description: >
  Answers a question from the user's Second Brain vault: reads _index.md, triages wiki/ notes by
  summary with ripgrep, opens at most three, and cites them as [[Note]]. States plainly when the
  vault does not cover the topic. Use for "what do I know about X" or "find my notes on Y".
argument-hint: "[topic or question]"
allowed-tools: Read Grep Glob Bash(rg *) Bash(sb *)
---

# Find in the vault

Answer only from the vault. If the vault does not say it, say so; never fill the gap from general
knowledge and attribute it to a note.

## Procedure

1. Read `_index.md` (one line per note: `[[Name]]: summary`).
2. Pick 2–5 search terms from `$ARGUMENTS` (include synonyms and the vault language).
   Run `rg -i -n "^(title|summary):.*(<term>)" wiki/` and `rg -i -l "<term>" wiki/`.
3. Rank by where the term hits: title > summary > body. Open **at most three** notes.
4. Answer in the user's language. Cite each claim with the note it came from, as `[[Note]]`.
   Distinguish what a note says from your own inference, and label the inference.
5. If nothing matches, reply: the vault has no notes on this topic, and suggest
   `/second-brain:capture` if they want to add something. Do not guess.
6. Open `_raw/` only to verify a source a note cites, never to answer from it directly.
7. If you notice the answer needs a link between notes that does not exist, mention it; do not
   edit anything (use `/second-brain:link`).
