---
type: tool_used
tool: Bash
input_match: '"command"\s*:\s*"(?:[^"\\]|\\.)*(?:(?<![0-9&])>>?(?!&|\s*/dev/null)|\btee\b|\brm\s|\bmv\s|\bcp\s|\bsed\s+-i|\btouch\s|\bmkdir\s|\bgit\s+(?:add|commit|apply|checkout|reset|stash)\b|\bnpm\s+(?:i|install|ci)\b)'
min: 0
max: 0
weight: 0.25
---
