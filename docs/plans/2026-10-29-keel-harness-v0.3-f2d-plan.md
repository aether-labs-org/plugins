# keel-harness v0.3 — F2d Assess signals and context: Implementation Plan

> **For agentic workers:** read `docs/plans/2026-10-29-keel-harness-v0.3-agent-rules.md` first. Phase id: `f2d`. Free; eval case files may be written, never run. Starts after F2c is merged. F3b and F3c-1 run in parallel with you. Each of you adds checks to `assets/core/harness-check.sh`; add yours as new functions placed just before `# --- review-due`, and their calls just before `check_review_due`, so the owner can merge the three without conflicts.

**Goal:** master plan §F2d; spec C0, C1, C8, D42.
1. `assess` reports four new signals, each with evidence and cost, and still no aggregate score.
2. `build` proposes the stack's official LSP plugin.
3. `rules` writes a curated codemap into `docs/architecture.md`, and `harness-check` warns when it goes stale.
4. Triggering evals for every skill.

## Tasks

- [ ] **Task 1 — four assess signals** in `skills/assess/references/rubric.md` and the assess phases. Add them as **new rubric axes**, after the seven existing ones, same states (`present | partial | absent`), same evidence rule (a repo-relative file proves it):

| Axis | present | partial | absent | Cost unit |
| --- | --- | --- | --- | --- |
| `Reproducible build` | a committed lockfile and a frozen install in `make bootstrap` (`npm ci`, `pnpm install --frozen-lockfile`, `uv sync --frozen`, `poetry install --sync`, Gradle/Maven wrapper committed) | lockfile without a frozen install, or no wrapper | no lockfile | setup minutes |
| `Headless setup` | `make bootstrap` runs with no prompt: no `read`, no interactive login in the target; `.env.example` when the code reads env vars; optional devcontainer | one blocker found | no bootstrap | setup minutes |
| `Flaky tests` | measured: N runs of the fast test command agree (N = 3; run only when the user agrees, and report the seconds spent) | some test changed result | — (never `absent`: unmeasured is `not measured`) | `+N.Ns per run` |
| `Observability` | structured logging library configured (`pino`, `winston` JSON, `structlog`, `logback` JSON encoder, …) **and** a log-format line in `AGENTS.md` or `docs/` | one of the two | neither | setup minutes |

  - Update the report contract: rows in fixed axis order.
  - Running the suite three times is a measurement, not a write. It is allowed only after the user agrees, and it follows the single rule (no persisted output).
  - Update `tests/assess_test.sh`.
  - Commit `feat(keel-harness): assess reports reproducibility, headless setup, flakiness and observability`.
- [ ] **Task 2 — LSP proposal in `build`** (D42).
  1. Find the official LSP plugins for TypeScript, Python, Java/Kotlin, Go and Rust in Claude Code's official plugin documentation: fetch `https://code.claude.com/docs/en/discover-plugins` and `https://code.claude.com/docs/en/plugins-reference`. Record the exact plugin names and the install command, citing the page and the date you read it.
  2. If the docs do not name an official plugin for a stack, write "no official LSP plugin found (date)" for that stack; never invent a name.
  3. Put the table in `skills/build/references/context-engineering.md`, and add one line to `build`'s guides phase: propose the stack's plugin, as a separate accept-or-decline item, and record it under `not_installed` if declined.

  Commit `feat(keel-harness): build proposes the stack's official LSP plugin (D42)`.
- [ ] **Task 3 — codemap.**
  - `skills/rules/references/topics/architecture.md` gets a `## Code map` section template, in the shape of matklad's ARCHITECTURE.md: a bird's-eye paragraph, then one bullet per important module, `` `path/` — what lives there``, then the invariants.
  - `rules` writes it, discovered from `measure.sh tree 2` and confirmed by the user, in its architecture phase.
  - New `harness-check` check **`codemap-stale`**: every backticked path in the `## Code map` section of `docs/architecture.md` must exist. One warning per missing path, with fix `update the Code map in docs/architecture.md (rules)`. It is silent when the file or the section is absent.
  - Add it to the checks table (`skills/assess/references/checks.md`); "sixteen checks" wherever the count is written.
  - Tests in `tests/keel_harness_check_test.sh`: a missing path warns; all present is clean; no section is clean.
  - Commit `feat(keel-harness): codemap in docs/architecture.md; harness-check warns codemap-stale (D42)`.
- [ ] **Task 4 — triggering evals** (files only). For each of `assess`, `build` and `rules`: two should-trigger cases phrased as a user would, without naming the skill, and one near-miss should-not-trigger case. Example near miss for `rules`: "what does this regex do?".
  - Names: `trigger-<skill>-<n>` and `trigger-<skill>-not`.
  - Tags: `[trigger, readonly]`.
  - `allowed_tools: [Read, Glob, Grep, Skill]`, `max_turns: 3`.
  - Graders: should-trigger cases use `skill-fired`, a `tool_used: Skill` matching the skill. Not-cases use a `tool_used: Skill` grader with `max: 0` and `arm: both`.
  - The cases need no scaffold beyond what a read-only skill needs.
  - Keep `tests/keel_evals_test.sh` green.
  - Commit `test(keel-harness): triggering evals per skill`.
- [ ] **Task 5 — master plan:** tick F2d, mark the status row ✅ with "triggering evals not run (owner)". Commit `docs(keel-harness): F2d done`.

## Acceptance

- `assess` has 11 axes in a fixed order, and the four new ones have rubric rows and tests.
- `build` names an LSP plugin only from the cited official docs.
- `codemap-stale` has tests, and the check count is updated everywhere it is written.
- Nine trigger cases exist and `tests/keel_evals_test.sh` passes.
- `./tests/run.sh` exits 0; `validate --strict` passes; the size limits hold.
