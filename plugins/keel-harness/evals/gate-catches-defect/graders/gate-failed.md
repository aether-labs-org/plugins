---
type: regex
pattern: '(✗|FAILED)'
target: { source: file, path: gate-output.txt }
weight: 2
---
