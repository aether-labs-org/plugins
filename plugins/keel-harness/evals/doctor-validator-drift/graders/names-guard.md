---
type: regex
pattern: 'guard[\s\S]{0,200}(missing|absent|not installed|install|no )'
flags: i
target: last_message
weight: 2
---
