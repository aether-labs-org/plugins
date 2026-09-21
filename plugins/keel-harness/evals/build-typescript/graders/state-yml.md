---
type: regex
pattern: 'model_baseline:[\s\S]*layers:[\s\S]*(bootstrap|guides)'
target: { source: file, path: .agents/state.yml }
weight: 2
---
