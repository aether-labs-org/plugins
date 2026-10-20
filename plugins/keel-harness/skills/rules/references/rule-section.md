# Rule section skeleton

Each rule is one section in its topic file (`docs/architecture.md`, `docs/conventions.md` or
`docs/testing.md`). The anchor line is the stable link target: every pointer uses
`docs/<topic>.md#<rule-id>`, so renaming the heading breaks nothing. A topic file stays at or under
**300 lines**.

```markdown
<a id="{{rule-id}}"></a>
### {{Heading stating the rule, e.g. Source files stay under 300 lines}}

**Rule.** {{One verifiable sentence, quoting the parameters: 300 lines, `src/**`.}}
**Why.** {{The reason, in this project's terms.}}
**✓ / ✗.** {{A short good and bad example.}}
**When it fails.** {{What to do; the same text as the sensor's guidance.}}
**Decision.** [ADR {{NNNN}}](decisions/{{NNNN-slug}}.md)
```

Omit the **Decision.** line when no ADR was written. The numbers in **Rule.** must match
`.agents/rules/<rule-id>.env`; `make harness-check` flags a divergence (`rule-inconsistent`).
