---
type: regex
pattern: 'onionArchitecture\(\)[\s\S]*FreezingArchRule\.freeze|FreezingArchRule\.freeze[\s\S]*onionArchitecture\(\)'
target: { source: file, path: "src/test/**/ArchitectureTest.*" }
weight: 2
---
