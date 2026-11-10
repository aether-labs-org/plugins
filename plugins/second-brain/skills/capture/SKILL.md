---
name: capture
description: >
  Saves raw text, a link or a thought into the vault's _inbox/ exactly as given, with no
  organising or linking. Use when the user says "capture", "save this for later" or pastes
  something to keep. Processing happens later with ingest.
argument-hint: "[text to capture]"
allowed-tools: Write Bash(date *)
---

# Capture to the inbox

Capturing is deliberately dumb: no summarising, tagging, linking or judging. `/second-brain:ingest`
does that later.

1. The text is `$ARGUMENTS`; if empty, the user's last message, or ask for it.
2. `date +%Y-%m-%d-%H%M` gives the file timestamp, `date +%Y-%m-%dT%H:%M` the header.
3. Slug: 3-5 lowercase ASCII words joined by hyphens, from the content.
4. Write `_inbox/<timestamp>-<slug>.md` (add `-2`, `-3` if it exists):

   ```
   ---
   captured: <ISO datetime>
   from: user
   ---
   <the text, verbatim>
   ```

5. Reply with the path only. Never write outside `_inbox/`.
