---
type: regex
pattern: 'schema_version: 3[\s\S]*layers:[\s\S]*(bootstrap|guides)'
target: { source: file, path: .agents/state.yml }
weight: 2
---
