# The twenty-three checks

`harness-check.sh` is the only implementation of these checks. `assess` runs the plugin's latest copy
and adds what a script cannot: the explanation of each warning and the proposed fix.

**One broken condition produces exactly one warning**, never two and never zero. The report never
manufactures a warning for a check that found nothing; a clean harness is a valid answer.

| Check id | Condition | Fix goes through |
| --- | --- | --- |
| `agents-size` | a tracked `AGENTS.md` is over 100 lines | `build` (guides): move prose into `docs/` |
| `stale-command` | a command cited in `AGENTS.md` no longer resolves | `build` (guides) |
| `agents-not-loaded` | `CLAUDE.md` or `.claude/CLAUDE.md` exists without `@AGENTS.md` | `build` (it proposes the import line) |
| `dangling-pointer` | a `→ path#anchor` target, file or anchor, is missing or still a TODO stub | `rules` |
| `hook-missing` | no Stop hook pointing at an executable `scripts/hooks/claude-stop.sh` | `build` (hook) |
| `run-state` | v0.2 run state outside `.agents/run/`, or `.agents/run/` not ignored | `build` (upgrade, `references/upgrade.md`) |
| `guard-missing` | no `scripts/sensors/guard.sh` or no `scripts/lib/envparse.sh` | `build` (gates) |
| `enforcement-drift` | the `ci` or `precommit` layer is installed but no workflow or hook runs `make gate-fast` | `build` (`references/enforcement.md`) |
| `sensor-malformed` | a sensor whose `id=` differs from its file name, whose `class=` is invalid, or that is not executable | edit the file, or `build` |
| `sensor-unavailable` | a fast sensor exits 2 for a tracked file it covers (tool missing) | `build` (gates) |
| `rule-inconsistent` | a rule env file is incomplete, points at a missing doc, anchor, sensor or ADR, or its numbers differ from the section | `rules` |
| `topic-size` | `docs/architecture.md`, `docs/conventions.md` or `docs/testing.md` is over 300 lines | `rules` (split by subtopic) |
| `baseline-malformed` | a TSV baseline without its header or with a row that is not `path<TAB>integer` | re-measure with `KEEL_MEASURE=1` |
| `baseline-stale` | a baseline past its `review_by` whose current total is not below the stored total | fix violations, then re-measure downward |
| `plan-stale` | a plan in `.agents/plans/` with `Status: active` whose last commit is older than `PLAN_STALE_DAYS` (`.agents/gate.env`, default 30); an uncommitted plan counts as fresh | close it with `keel plan-close <file> done\|abandoned <ref>`, or update it |
| `progress-size` | `.agents/progress.md` is over `PROGRESS_MAX_LINES` lines (default 200) | summarise older entries into an ADR (`rules`) or delete them; git history keeps them |
| `acceptance-untested` | a spec in `docs/specs/*.md` or `specs/*/spec.md` has acceptance criteria (bullets under an `Acceptance` heading) that name no existing test or spec file; one warning per spec, with the count | name the test that proves each criterion (D46: keel reads specs, never writes them) |
| `codemap-stale` | a backticked path in the `## Code map` of `docs/architecture.md` no longer exists (silent when the file or the section is absent) | `rules` (update the Code map in `docs/architecture.md`) |
| `protect-missing` | the `authority` layer is installed but `.agents/consequence.yml`, the executable `scripts/hooks/claude-protect.sh` or its `PreToolUse` entry in `.claude/settings.json` is gone | `build` (`references/authority.md`) |
| `exemplar-missing` | a rule's `EXEMPLAR=` in `.agents/rules/<id>.env` names a file that does not exist | `rules` (point it at today's canonical file, or remove it and the nested `AGENTS.md` line) |
| `mandatory-unsensored` | a rule with `ENFORCEMENT_LEVEL=mandatory` whose `ENFORCEMENT` is `inferential`, names no `sensor:<id>`, or names a sensor with no file in `scripts/sensors/` or `scripts/sensors/slow/`; also an `ENFORCEMENT_LEVEL` other than `mandatory` or `ratchet`, which every tool would treat as ratchet | `rules` (write the sensor, or make the rule ratchet through a superseding ADR) |
| `exception-expired` | a line of a mandatory rule's `EXCEPTIONS` (`<path> <YYYY-MM-DD>`) whose date has passed, or that is not `<path> <YYYY-MM-DD>`; one warning per line | fix the file now (the sensor already fails it); deadlines only shrink, so never move the date |
| `review-due` | `harness_review_by` has passed | `build` (re-read, then move the date six months on) |
