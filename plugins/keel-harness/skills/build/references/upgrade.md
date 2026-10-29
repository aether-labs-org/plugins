# Upgrading an earlier install

A `schema_version: 2` state (v0.2) gets one round, each item accept-or-drop: delete `.agents/last-*` and
`.agents/.gate-lock/`, replace their seven `.gitignore` lines with `.agents/run/`, install `scripts/lib/envparse.sh`,
`scripts/sensors/guard.sh` and current copies of every asset (outside the repo-specific markers), set
`schema_version: 3`; then `make harness-check` reports no `run-state` or `guard-missing`. A state without
`schema_version`, or a `PostToolUse` entry running `make gate-fast` (v0.1), gets that round plus:

1. The Stop hook of the hook phase replaces the v0.1 PostToolUse entry (remove that entry, keep other keys).
2. The sensor list in the old state is dropped: each entry already has its file; the gate
   discovers files now.
3. A v0.1 `snapshot` entry becomes a TSV baseline, re-measured with `KEEL_MEASURE=1`, never copied, and named in one upgrade ADR so `guard` accepts it.
4. The v0.1 model-baseline key is replaced by `harness_review_by` (today + 6 months); state becomes the
   `schema_version: 3` shape in `SKILL.md` (output contract).
5. The `.gitignore` entries of the hook phase are added.

Every earlier install gets one more accept-or-drop item (D6 revised): a `.agents/plans/` line in `.gitignore`
is removed, because plans are versioned now, and `.agents/progress.md` is created with the `Progress across
sessions → .agents/progress.md` line in `AGENTS.md` (see `contracts/plan.md`).
