---
type: regex
pattern: 'journey\s+\[correctness\s*\]\s+\d+ of \d+ journey\(s\) failed'
target: { source: file, path: gate-output.txt }
weight: 2
---
