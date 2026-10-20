# Topic file: docs/conventions.md

Copy this skeleton to `docs/conventions.md` when it does not exist. It holds `file-size`,
`code-language`, `adopted-patterns` and any other code convention, one anchored section each.

```markdown
# Conventions

{{One or two lines: what is conventional here that an agent cannot guess.}}

<a id="file-size"></a>
### Source files stay under 300 lines

**Rule.** {{Source files under `src/` have at most 300 lines.}}
**Why.** {{Large files hide several responsibilities and are expensive for agents to read.}}
**✓ / ✗.** {{✓ `ledger/posting.ts` (140 lines). ✗ `ledger/everything.ts` (612 lines).}}
**When it fails.** {{Split the file by responsibility; never raise the limit or the baseline.}}
**Decision.** [ADR 0003](decisions/0003-file-size-limit.md)
```

Past 300 lines, propose splitting by subtopic (e.g. `docs/conventions-naming.md`).
