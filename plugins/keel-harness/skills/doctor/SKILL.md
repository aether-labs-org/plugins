---
name: doctor
description: >
  Checks whether an installed harness has drifted from the repository it guards, by running the
  same portable validator the repository carries: AGENTS.md over 100 lines, commands cited there
  that no longer resolve, a CLAUDE.md that hides AGENTS.md, dangling rule pointers, a missing Stop
  hook, misplaced or unignored run state, a missing guard sensor, malformed or unavailable sensors, rules that disagree with their env files, oversize topic
  files, malformed or stale baselines, and an overdue harness review. Explains each warning and
  proposes the fix; writes nothing. Use when someone asks whether their harness is out of date,
  stale or still valid, or wants a harness health check.
---

# Doctor

Reports and proposes, never writes. There is one implementation of the checks, the validator
`harness-check.sh`; `doctor` runs the plugin's latest copy and adds what a script cannot: the
explanation of each warning and the proposed fix.

## 1. Run the validator

From the repository root:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/assets/core/harness-check.sh"
```

It is read-only. It prints one line per warning, `warn<TAB><check-id><TAB><file><TAB><message><TAB><fix>`,
then `harness-check: N warning(s)` or `harness-check: harness is clean`. Exit 0 clean, 1 warnings,
2 no harness: with no `.agents/state.yml`, say so and point at `/keel-harness:build`; that is a
precondition, not a warning.

## 2. The fourteen checks

| Check id | Condition | Fix goes through |
| --- | --- | --- |
| `agents-size` | a tracked `AGENTS.md` is over 100 lines | `build` (guides): move prose into `docs/` |
| `stale-command` | a command cited in `AGENTS.md` no longer resolves | `build` (guides) |
| `agents-not-loaded` | `CLAUDE.md` or `.claude/CLAUDE.md` exists without `@AGENTS.md` | `build` (it proposes the import line) |
| `dangling-pointer` | a `→ path#anchor` target, file or anchor, is missing or still a TODO stub | `rules` |
| `hook-missing` | no Stop hook pointing at an executable `scripts/hooks/claude-stop.sh` | `build` (hook) |
| `run-state` | v0.2 run state outside `.agents/run/`, or `.agents/run/` not ignored | `build` (upgrade, section 7b) |
| `guard-missing` | no `scripts/sensors/guard.sh` or no `scripts/lib/envparse.sh` | `build` (gates) |
| `sensor-malformed` | a sensor whose `id=` differs from its file name, whose `class=` is invalid, or that is not executable | edit the file, or `build` |
| `sensor-unavailable` | a fast sensor exits 2 for a tracked file it covers (tool missing) | `build` (gates) |
| `rule-inconsistent` | a rule env file is incomplete, points at a missing doc, anchor, sensor or ADR, or its numbers differ from the section | `rules` |
| `topic-size` | `docs/architecture.md`, `docs/conventions.md` or `docs/testing.md` is over 300 lines | `rules` (split by subtopic) |
| `baseline-malformed` | a TSV baseline without its header or with a row that is not `path<TAB>integer` | re-measure with `KEEL_MEASURE=1` |
| `baseline-stale` | a baseline past its `review_by` whose current total is not below the stored total | fix violations, then re-measure downward |
| `review-due` | `harness_review_by` has passed | `build` (re-read, then move the date six months on) |

## 3. Report

**One broken condition produces exactly one warning**, never two and never zero. For each warning
the validator prints, say in plain words what is wrong, name the file, and propose the fix through
`/keel-harness:build` or `/keel-harness:rules` as in the table. Stay silent about checks that found
nothing; a clean harness is a valid answer. `doctor` never manufactures a warning.

Two more things to do every time:

- **Validator drift.** Compare the repository's copy with the plugin's:
  `cmp scripts/harness-check.sh "${CLAUDE_PLUGIN_ROOT}/assets/core/harness-check.sh"`. When they
  differ, propose updating the installed copy through `build` (the plugin's copy is the latest).
- **Contradictions between instruction files.** The validator does not read prose. Point the user
  at Claude Code's `/doctor prompt-audit` for contradictions across `AGENTS.md`, `CLAUDE.md` and
  the rest.

`doctor` writes nothing: it reports, proposes and stops. It also looks once, not across time:
checks that need run history (how often a sensor's failures are real) are not part of it.
