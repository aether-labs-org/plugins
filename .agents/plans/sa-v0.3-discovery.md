# solutions-architect v0.3 - discovery

Status: active
Scope: plugins/solutions-architect/**, tests/sa_*.sh, tests/fixtures/sa/**, README.md, .claude-plugin/marketplace.json, docs/plans/2026-*-solutions-architect-*.md, .agents/plans/sa-v0.3-discovery.md

Spec: `docs/plans/2026-11-05-solutions-architect-v0.3-discovery.md` (phases 0-4 here; phase 5 belongs to the main session).

## Acceptance

- [ ] New cases of section 11 pass the comparison criterion (Phase 5).
- [ ] No regression in `design-discussion`, `should-not-trigger`, `diagram-trigger`, `greenfield-web-3tier` and `wa-review-qualitative` (Phase 5).
- [ ] A ready-made solution never becomes an `accepted` ADR without a discussion round, or without a `Not held` that records the scored contrary alternative and `Source: user` for the preference.
- [ ] Every market reference in the artifacts is marked `consulted` or `not consulted`, and `not consulted` ones carry no weight.
- [ ] The catalog only has entries with a verified link: 2 per class and 3 anti-cases at least.
- [ ] A v0.2 workspace validates and continues in `architect` without going back to `discovery`.
- [ ] `discovery` description between 150 and 400 characters; `SKILL.md` <= 250 lines.
- [ ] Fast and slow gates green; `make validate` green.
