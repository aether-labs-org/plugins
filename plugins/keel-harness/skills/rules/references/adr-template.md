# ADR template (MADR)

ADRs live in `<adr_dir>/NNNN-<slug>.md` (`adr_dir` in `.agents/state.yml`, default `docs/adr/`), numbered `NNNN` from `0001`. Write one when a round had
a real trade-off (more than one viable option), when a rule is breaking, or when the user overrides
your recommendation. **Never edit an accepted ADR; supersede it** with a new one that links back,
and set the old one's status to `superseded by NNNN`.

```markdown
# {{NNNN}}. {{Short title of the decision}}

Status: proposed | accepted | superseded by {{NNNN}}
Date: {{YYYY-MM-DD}}

## Context and Problem Statement
{{The situation and the question, in this project's terms.}}

## Decision Drivers
- {{Driver, e.g. "p90 file size is 240 lines"}}
- {{Driver, e.g. "team uses three agents"}}

## Considered Options
### {{Option A (recommended)}}
- Good: {{pro}}
- Bad: {{con}}
### {{Option B}}
- Good: {{pro}}
- Bad: {{con}}

## Decision Outcome
Chosen: {{option}}, because {{reason}}. Approved by {{who}} on {{date}}.

## Consequences
- {{What changes, what becomes harder, what the sensor now enforces.}}

## Evidence
- Measured: {{`measure.sh` output, e.g. "files 212, p90 240, over:500 12"}}
- Source: {{URL of the doc, tool default or study}}
```

The rule's section in its topic file links the ADR in its **Decision.** field and in `DECISION=` of
its env file.

## Superseding ADR for a mandatory rule

A rule with `ENFORCEMENT_LEVEL=mandatory` (`contracts/rule-env.md`) is not loosened by an ADR that only names
its files. Loosening one takes a **superseding** ADR, added in the same change: it names each file it loosens
by path, says why, and carries one extra line pointing at an existing ADR in `adr_dir` (the one that
introduced the rule, or the last one that changed it):

```markdown
Supersedes: docs/adr/0003-file-size-limit.md
```

Set the old ADR's status to `superseded by NNNN`. `guard` checks the line and that the target exists at the
base commit; the approval is a human's, through CODEOWNERS and the required `keel` check, which keel cannot
verify locally.
