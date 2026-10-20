---
type: regex
pattern: 'not_installed:[\s\S]*(compile|fast_gate)[\s\S]*[0-9]+\s*s'
target: { source: file, path: .agents/state.yml }
weight: 1
---
