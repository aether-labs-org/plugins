# State contract — `.agents/state.yml`

`.agents/state.yml` is committed and holds **metadata only**. It does not configure the gate: budgets
are in `.agents/gate.env`, the sensors are the files in `scripts/sensors/`, the rules are the files in
`.agents/rules/`. Skills reach this file as `${CLAUDE_PLUGIN_ROOT}/contracts/state.md`; the installed
scripts never do (they only read the repository's own `state.yml`).

```yaml
schema_version: 3
installed_at: 2026-10-20          # ISO date, today
harness_review_by: 2027-04-20     # installed_at + 6 months
mode: brownfield                  # greenfield | brownfield, confirmed by the user
adr_dir: docs/adr                 # the folder the ADRs live in
layers: { bootstrap: installed, guides: installed, fast_gate: installed, slow_gate: not_installed, hook: installed, ci: installed, precommit: not_installed, rules: not_installed }
not_installed:                    # layer or sensor -> the reason, in keel's words
  slow_gate: "no mutation or coverage tool configured"
```

## Keys

| Key | Type | Written by | Read by |
| --- | --- | --- | --- |
| `schema_version` | integer, `3` | `build` (output contract; the v0.2 upgrade round in `references/upgrade.md` sets it from `2`) | `build` (decides whether the upgrade round applies) |
| `installed_at` | ISO date | `build` | people; `build` on re-runs |
| `harness_review_by` | ISO date, `installed_at` plus six months | `build` (a re-read moves it six months on) | `harness-check` (`review-due` once the date has passed; `KEEL_TODAY` overrides today in tests) |
| `mode` | `greenfield` or `brownfield` | `build`; `rules` records its own confirmation (section 2) | `rules` (greenfield skips reverse engineering); `assess` reports it as an inference |
| `adr_dir` | repository-relative folder | `rules` (section 1: an existing ADR folder, else `docs/adr/`) | `guard` (an ADR added in the same change justifies a loosening), the `tests` sensors' guidance, `build` (the `Decisions` pointer in `AGENTS.md`) |
| `layers` | map of the layers below to `installed` or `not_installed` | `build` | `harness-check`; `build` (a layer already `installed` is not re-proposed, so each phase is resumable) |
| `not_installed` | map: layer or sensor to the reason | `build` | people; `build` (the reason of a skipped layer, or of a sensor that blew the budget, with its seconds) |

Use the real reason for each `not_installed` entry, never a generic one. `guard` reads only the
presence of the file at the commit the branch started from, plus `adr_dir`.

## Layers

All values are `installed` or `not_installed`. A key missing from `layers` means the layer was never
proposed; an absent key never raises a warning.

| Layer | What it is | Written by | Read by |
| --- | --- | --- | --- |
| `bootstrap` | the repository can be built and tested from a clean checkout | `build` phase 1 | people |
| `guides` | `AGENTS.md`, the `CLAUDE.md` import, `.agents/README.md` | `build` phase 2 | people |
| `fast_gate` | `scripts/gate.sh`, the stack sensors, `make gate-fast` | `build` phase 3 | people |
| `slow_gate` | `make gate-slow` and the slow sensors | `build` phase 3 | people |
| `hook` | the Stop hook (`scripts/hooks/claude-stop.sh` and its `.claude/settings.json` entry) | `build` phase 4 (the Stop hook) | `harness-check` (`hook-missing` is skipped when `hook: not_installed`) |
| `ci` | optional (since F3a): `.github/workflows/keel.yml` runs `make gate-fast` | `build` (`references/enforcement.md`) | `harness-check` (`enforcement-drift` when `ci: installed` and no workflow runs `make gate-fast`) |
| `precommit` | optional (since F3a): a pre-commit hook runs `make gate-fast` | `build` (`references/enforcement.md`) | `harness-check` (`enforcement-drift` when `precommit: installed` and no hook runs it) |
| `rules` | the repository's own rules (`.agents/rules/*.env`, topic files, rule sensors) | `build` writes `not_installed`; no skill flips it to `installed` yet | people |

`harness-check` matches `hook: not_installed`, `ci: installed` and `precommit: installed` as literal
text in the file, so keep `layers` on one line in flow style, as above.

## Rules for editing

- Never edit `state.yml`, a baseline or a test to make the gate pass; `guard` and the Stop hook say so.
- `.agents/state.yml`, `.agents/gate.env` and `.agents/baselines/` are committed; `.agents/run/` and
  `.agents/plans/` are git-ignored.
- A state without `schema_version`, or with `schema_version: 2`, is an earlier install: `build`
  upgrades it (`skills/build/references/upgrade.md`).
