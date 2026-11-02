# Plan

`.agents/plans/YYYY-MM-DD-<slug>.md` (for a migration, `<slug>` is the rule id). Plans are **committed**
(D6 revised): another session, agent or reviewer must be able to see the plan and check its
Acceptance. They are transient (D40): a plan is removed when it is done, and git history is the record.
Execution plans never go under `docs/`. keel never executes a plan; any agent or person can pick it up.

`rules` writes one for each approved rule whose baseline is non-empty and records it as `PLAN=` in the
rule's env file. Keep it small: the plan carries the how; a spec or an ADR carries the what and why.

```markdown
# Plan: {{title, e.g. migrate file-size}}
Status: active
Created: {{YYYY-MM-DD}}
Rule: {{docs/<topic>.md#<rule-id>}}
Spec: {{docs/specs/<file>.md}}

## Acceptance
- {{a criterion in a sensor's numbers, e.g. `file-size` reports 0 files over 300 lines}}
- {{or a test, e.g. test: `src/billing/ledger.test.ts` passes}}

## Steps
1. {{Small step, e.g. split src/billing/ledger.ts (612 lines) by responsibility.}}
   Done when: {{the number the step moves, e.g. "file-size baseline: 12 -> 11 files"}}.
2. ...

## After each step
- Run `make gate-fast`; it must pass.
- Shrink the baseline: `KEEL_MEASURE=1 bash scripts/sensors/<id>.sh > .agents/baselines/<id>.tsv`
  and review the diff. A baseline only ever shrinks.
```

## Header

| Line | Required | Value |
| --- | --- | --- |
| `Status:` | yes | `active`, `done` or `abandoned` |
| `Created:` | yes | `YYYY-MM-DD` |
| `Rule:` | no | the rule's `DOC` pointer, when the plan migrates a rule |
| `Spec:` | no | the spec the plan implements, read-only (D46) |

## Acceptance (required)

At least one `- ` bullet. Each is checkable without opinion: a sensor's numbers
(`` `file-size` reports 0 files over 300 lines ``) or a named test
(``test: `src/foo.test.ts` passes``). `keel verify plan <file>` rejects a plan without it.

## Lifecycle

- `active`: being worked on. `harness-check` warns `plan-stale` when it is untouched for
  `PLAN_STALE_DAYS` (`.agents/gate.env`, default 30): close it or update it.
- `done` or `abandoned`: `scripts/keel plan-close <file> <done|abandoned> <ref>` appends one line to
  `.agents/progress.md` and removes the plan. `<ref>` is the commit or the ADR that records the outcome
  and must exist.

## `.agents/progress.md`

What survives between sessions: one line per closed plan, `YYYY-MM-DD <done|abandoned> <plan file> <ref>`,
plus any short note a session leaves for the next. `AGENTS.md` points at it. `harness-check` warns
`progress-size` over `PROGRESS_MAX_LINES` (default 200): summarise older entries into an ADR or delete
them; git history keeps them.
