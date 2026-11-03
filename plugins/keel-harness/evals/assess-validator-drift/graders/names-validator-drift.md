---
type: regex
pattern: 'harness-check[\s\S]{0,300}(differ|older|out of date|outdated|stale|behind|update)'
flags: i
target: last_message
weight: 2
---
