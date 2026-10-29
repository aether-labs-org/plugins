---
type: regex
pattern: 'reviewer\s+\[heuristic\s*\]\s+\d+ rule violation'
target: { source: file, path: gate-output.txt }
weight: 2
---
