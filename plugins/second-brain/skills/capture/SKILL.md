---
name: capture
description: >
  Saves raw text, a link or a thought into the vault's _inbox/ exactly as given, with no
  organising or linking. Use when the user says "capture", "save this for later" or pastes
  something to keep. Processing happens later with ingest.
argument-hint: "[text to capture]"
allowed-tools: Write Bash(date *) Bash(sb log *)
---

# Capture to the inbox

Capturing is deliberately dumb: no summarising, no tagging, no links, no decisions about what
matters. That is what `/second-brain:ingest` is for.

## Procedure

1. The text to capture is `$ARGUMENTS`; if empty, use the user's last message or ask for it.
2. Run `date +%Y-%m-%d-%H%M` for the timestamp and `date +%Y-%m-%dT%H:%M` for the header.
3. Pick a short lowercase slug (3–5 words, ASCII, hyphens) from the content.
4. Write `_inbox/<timestamp>-<slug>.md`:

   ```
   ---
   captured: <ISO datetime>
   from: user
   ---
   <the text, verbatim>
   ```

5. Run `sb log capture "<slug>"`.
6. Reply with the file path only. Do not process it unless the user asks.

Never write outside `_inbox/`. If the target file exists, add `-2`, `-3`... to the slug.
