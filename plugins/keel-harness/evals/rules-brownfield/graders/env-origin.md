---
type: regex
pattern: 'ORIGIN=proposed[\s\S]*DOC=docs/conventions\.md#file-size|DOC=docs/conventions\.md#file-size[\s\S]*ORIGIN=proposed'
target: { source: file, path: .agents/rules/file-size.env }
weight: 2
---
