# Local migration plan

`.agents/plans/YYYY-MM-DD-<rule-id>.md`. Gitignored (D6): execution plans never go under `docs/`.
Written for each approved rule whose baseline is non-empty, and recorded as `PLAN=` in the rule's env
file. keel never executes it; any agent or person can pick it up later.

```markdown
# Migration plan: {{rule-id}}
Written: {{YYYY-MM-DD}} · review_by: {{YYYY-MM-DD, six months out}}
Rule: {{docs/<topic>.md#<rule-id>}} · Decision: {{docs/decisions/NNNN-slug.md}}
Goal: {{baseline today, e.g. "file-size baseline: 12 files"}} -> {{target, e.g. 0 files}}

## Steps
1. {{Small step, e.g. split src/billing/ledger.ts (612 lines) by responsibility.}}
   Done when: {{acceptance criterion in the sensor's numbers, e.g. "file-size baseline: 12 -> 11 files"}}.
2. ...

## After each step
- Run `make gate-fast`; it must pass.
- Shrink the baseline: `KEEL_MEASURE=1 bash scripts/sensors/<id>.sh > .agents/baselines/<id>.tsv`
  and review the diff. A baseline only ever shrinks.
```
