---
type: llm
---

The agent created notes from a clipped article. Judge only the body of the notes it created.

PASS if no created note opens with a preamble (for example "This note ..." or an introduction),
ends with a recap or conclusion, comments on the source or on how the note was made, or repeats
its own `summary` in the body.
FAIL if any created note does one of those things.
