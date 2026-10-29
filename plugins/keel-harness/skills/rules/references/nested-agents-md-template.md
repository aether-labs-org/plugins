# Nested AGENTS.md template

For rules that apply to one directory only. Agents read the nearest `AGENTS.md`. The file stays at
**100 lines** or fewer, like the root one, and holds one line per rule, never the rule's prose.

```markdown
# AGENTS.md — {{directory}}
{{One line: what this directory is.}}

## Rules
- {{statement, one verifiable sentence}} → docs/{{topic}}.md#{{rule-id}}
- Follow {{EXEMPLAR}}, not {{legacy path}} → docs/{{topic}}.md#{{rule-id}}
- Legacy zone: {{LEGACY pathspecs, comma-separated}}; migration in {{PLAN of the rule}}
```

The last two lines appear only when the rule's env file has `EXEMPLAR=` and `LEGACY=`
(`contracts/rule-env.md`). Put them in the `AGENTS.md` of the directory the legacy zone lives in, so
an agent editing old code sees the canonical file before it copies its neighbour. `Legacy zone:`
points at the rule's plan (`.agents/plans/…`); drop the pointer once the plan is closed, and drop the
line when the zone is gone.
