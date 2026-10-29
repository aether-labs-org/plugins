# Topic file: docs/architecture.md

Copy this skeleton to `docs/architecture.md` when the file does not exist, then fill it with real,
approved content only. The shape follows matklad's ARCHITECTURE.md
(https://matklad.github.io/2021/02/06/ARCHITECTURE.md.html): short, stable, a map and not a manual.

```markdown
# Architecture

## Code map

{{Bird's-eye paragraph: at most five lines on what the system does and how the code is shaped.}}

- `{{path/}}` — {{what lives here, one line}}
- `{{path/}}` — {{one bullet per important module, not per directory}}

{{Invariants of the map: what each module may rely on, and what it must never reach into. Rules that a
sensor enforces live as anchored sections under Invariants below; this paragraph only names them.}}

## Layer boundaries
{{Style (hexagonal | layered | clean | modular) and which layer may depend on which. The machine
form is `.agents/rules/architecture.env`.}}

## Invariants
Rules that hold now. Each is one anchored section (see `rule-section.md`).

<a id="architecture"></a>
### Dependencies point inward

**Rule.** {{Domain code imports no framework and no adapter; adapters depend on the application layer.}}
**Why.** {{The domain stays testable without the framework.}}
**✓ / ✗.** {{✓ `domain/` imports only `domain/`. ✗ `domain/Order` imports `org.springframework`.}}
**When it fails.** {{Move the dependency behind a port owned by the inner layer.}}
**Decision.** [ADR 0002](decisions/0002-architecture-style.md)
```

The `## Code map` is curated, not generated: `rules` drafts it from `measure.sh tree 2`, the user
confirms or corrects every bullet, and each backticked path in the section must exist
(`harness-check` warns `codemap-stale` for one that does not). Keep the bullets few: a repository
overview that lists everything helps the agent no more than none.

Also holds `folder-layout`. Past 300 lines, propose splitting by subtopic.
