---
type: regex
pattern: '"discovery"\s*:\s*\{[^}]*"status"\s*:\s*"skipped"'
target: { source: file, path: architecture/manifest.json }
weight: 2
---
