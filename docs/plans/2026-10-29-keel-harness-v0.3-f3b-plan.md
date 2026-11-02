# keel-harness v0.3 — F3b Versioned plans and progress: Implementation Plan

> **For agentic workers:** read `docs/plans/2026-10-29-keel-harness-v0.3-agent-rules.md` first. Phase id: `f3b`. Free; no eval. Starts after F2c is merged. F2d and F3c-1 run in parallel with you. Add your `harness-check` checks as new functions placed just before `# --- review-due`, and their calls just before `check_review_due`.

**Goal:** spec D6 (revised), D40, D46; components C5 and C6. A plan another session or reviewer can see and verify:
- plans in `.agents/plans/` are **committed**, carry a lifecycle and a required **Acceptance** section, and are removed when done;
- `.agents/progress.md` carries what survives between sessions;
- specs are read, never written, and their acceptance criteria must name tests.

## Tasks

- [x] **Task 1 — the plan contract** (`contracts/plan.md`, today's plan template).
  - **Header lines:** `Status: active | done | abandoned`, `Created: YYYY-MM-DD`, `Rule: <rule-id>` (optional), `Spec: <path>` (optional).
  - **`## Acceptance`, required:** at least one bullet, each in a sensor's numbers or naming a test (e.g. `` `file-size` reports 0 files over 300 lines``, `` test: `src/foo.test.ts` passes``).
  - **`## Steps`.**
  - Keep it small: the plan carries the how; specs carry the what and why (D46).
  - Commit `docs(keel-harness): plan contract with lifecycle and Acceptance`.
- [x] **Task 2 — `scripts/keel` gains two commands** (tests first in `tests/keel_cli_test.sh`):

| Command | Behaviour | Exit |
| --- | --- | --- |
| `keel verify plan <file>` | Has a `Status:` line with a valid value, and an `## Acceptance` section with at least one `- ` bullet | 0 / 1, naming what is missing |
| `keel plan-close <file> <done\|abandoned> <ref>` | `<ref>` must exist: a commit (`git rev-parse --verify <ref>^{commit}`) or a path under `adr_dir`. Appends `YYYY-MM-DD <done\|abandoned> <plan basename> <ref>` to `.agents/progress.md` (created if absent), then removes the plan (`git rm -q` if tracked, else `rm`) | 0; 1 if `<ref>` does not resolve or the plan fails `verify plan` |

  Commit `feat(keel-harness): keel verify plan and keel plan-close (D40)`.
- [x] **Task 3 — plans stop being ignored.**
  - `build` §7 and `rules` §7 no longer add `.agents/plans/` to `.gitignore`.
  - `build`'s upgrade phase proposes removing an existing `.agents/plans/` line, as an accept-or-drop item.
  - `rules` writes migration plans from `contracts/plan.md`, runs `keel verify plan` on each, and records `PLAN=` as today. Drop "plans are gitignored" wherever it is written: skills, `assets/core/README.agents.md`, README.
  - The AGENTS.md template (`skills/build/references/agents-md-template.md`) gets one pointer line, `Progress across sessions → .agents/progress.md`. The template's line budget holds.
  - Update the tests that asserted the ignore line (`grep -rn "agents/plans" tests`).
  - Commit `feat(keel-harness): plans and progress are versioned (D6 revised)`.
- [x] **Task 4 — three `harness-check` checks.** Thresholds are read from `.agents/gate.env` with the existing parser style (never sourced): `PLAN_STALE_DAYS=30`, `PROGRESS_MAX_LINES=200`. Add both keys with comments to `assets/core/gate.env`.
  - **`plan-stale`:** a plan with `Status: active` whose last commit (`git log -1 --format=%cs -- <file>`; an uncommitted file counts as fresh) is older than `PLAN_STALE_DAYS`, measured from `KEEL_TODAY` or today. Fix: `close it with keel plan-close or update it`.
  - **`progress-size`:** `.agents/progress.md` over `PROGRESS_MAX_LINES` lines. Fix: `summarise older entries into an ADR or delete them; git history keeps them`.
  - **`acceptance-untested` (D46):**
    - Specs are read from `docs/specs/*.md` and, when present, Spec Kit's `specs/*/spec.md`.
    - In each spec, the bullets under a heading whose text contains `Acceptance` (any level) are checked. A bullet passes if it contains a backticked path that exists and whose name contains `test` or `spec`, or a `test:` marker followed by such a path.
    - One warning per spec file, with the count of untested bullets. Fix: `name the test that proves each criterion`.
    - Silent when there are no specs.
  - Add the three to the checks table (`skills/assess/references/checks.md`) and update the count wherever it is written.
  - Tests in `tests/keel_harness_check_test.sh` for each check, warn and clean, with `KEEL_TODAY` fixed.
  - Commit `feat(keel-harness): harness-check warns plan-stale, progress-size, acceptance-untested`.
- [x] **Task 5 — master plan:** tick F3b, mark the status row ✅. Commit `docs(keel-harness): F3b done`.

## Acceptance

- `keel verify plan` rejects a plan without Acceptance; `keel plan-close` removes a `done` plan and logs it, and refuses an unknown ref.
- No skill, asset or doc tells a repository to ignore `.agents/plans/`.
- The three checks have warn and clean tests, and the thresholds come from `gate.env`.
- `./tests/run.sh` exits 0; `validate --strict` passes; `shellcheck` is clean; the size limits hold.
