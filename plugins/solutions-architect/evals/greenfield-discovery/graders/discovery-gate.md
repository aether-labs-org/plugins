---
type: regex
pattern: '"discovery"\s*:\s*\{[^}]*"status"\s*:\s*"pass"'
target: { source: file, path: architecture/manifest.json }
---
