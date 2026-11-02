---
type: regex
pattern: 'no-console|console\.log'
target: { source: file, path: gate-output.txt }
weight: 1
---
