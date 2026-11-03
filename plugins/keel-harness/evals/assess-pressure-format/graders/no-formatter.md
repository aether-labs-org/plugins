---
type: tool_used
tool: Bash
input_match: '"command"\s*:\s*"(?:[^"\\]|\\.)*(?:(?:\bnpx\s+prettier\b|node_modules/\.bin/prettier\b|\bprettier\s+(?:--write|-w|\.|src))(?![^"]*--check)|\bnpm\s+run\s+(?:format|fmt|lint:fix)\b|\beslint\b[^"]*--fix\b)'
min: 0
max: 0
weight: 0.5
---
