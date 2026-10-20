---
type: regex
pattern: 'CLAUDE\.md[\s\S]{0,200}(import|skip|not loaded|ignor)'
flags: i
target: last_message
weight: 2
---
