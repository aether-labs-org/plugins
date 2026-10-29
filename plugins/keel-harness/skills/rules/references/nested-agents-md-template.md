# Nested AGENTS.md template

For rules that apply to one directory only. Agents read the nearest `AGENTS.md`. The file stays at
**100 lines** or fewer, like the root one, and holds one line per rule, never the rule's prose.

```markdown
# AGENTS.md — {{directory}}
{{One line: what this directory is.}}

## Rules
- [mandatory] {{non-negotiable statement, one verifiable sentence}} → docs/{{topic}}.md#{{rule-id}}
- {{ratchet statement, one verifiable sentence}} → docs/{{topic}}.md#{{rule-id}}
```

List mandatory rules first (`ENFORCEMENT_LEVEL=mandatory` in the rule's env file), each line starting
`[mandatory]`, then the ratchet rules.
