---
type: regex
pattern: '"Stop"[\s\S]*claude-stop\.sh'
target: { source: file, path: .claude/settings.json }
weight: 2
---
