---
type: regex
pattern: 'NFR-001[\s\S]*NFR-002[\s\S]*NFR-003[\s\S]*NFR-004[\s\S]*NFR-005'
target: { source: file, path: architecture/manifest.json }
weight: 2
---
