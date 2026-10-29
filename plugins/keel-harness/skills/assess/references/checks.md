# The fifteen checks

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
| `review-due` | `harness_review_by` has passed | `build` (re-read, then move the date six months on) |
