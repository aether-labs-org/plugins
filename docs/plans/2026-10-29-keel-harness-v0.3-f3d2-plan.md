# keel-harness v0.3 — F3d-2 Catalog entries: Implementation Plan

> **For agentic workers:** read `docs/plans/2026-10-29-keel-harness-v0.3-agent-rules.md` first. Phase id: `f3d2`. Free; no eval. Starts after F3d-1 is merged (it needs `pattern.sh` and `measure.sh pattern`).

**Goal:** spec D44. The catalog gains the entries below. Each entry has the catalog's six labels (**Questions, Measure, Default, Why, Sensor, Opinion**), sources you can cite, and a sensor path that is tested. Every new entry is marked `**Status**: unproven — no with/without measurement yet (D50; F3d acceptance)`. `rules` proposes an entry only when `measure.sh` shows a problem or the user asks for it.

**Prefer configuring an existing tool over a new sensor.** Most entries are a rule of the linter the repository already runs (ESLint, ruff, Checkstyle/detekt). The `lint` sensor already enforces them with a baseline. A new keel sensor exists only where no common tool covers it, and then it is a `pattern.sh` preset.

## Entries

| Entry | Measure | Enforced by |
| --- | --- | --- |
| `function-size` | linter in report mode, or `measure.sh` (new subcommand, see Task 2) | ESLint `max-lines-per-function`, ruff `PLR0915`, Checkstyle `MethodLength`, detekt `LongMethod` |
| `complexity` | linter report | ESLint `complexity`, ruff `C901`, Checkstyle `CyclomaticComplexity`, detekt `CyclomaticComplexMethod` |
| `max-params` | linter report | ESLint `max-params`, ruff `PLR0913`, Checkstyle `ParameterNumber`, detekt `LongParameterList` |
| `dead-code` (optional) | tool report | `knip` / `ts-prune` (TS), `vulture` (Python); slow gate only |
| `duplication` (optional) | `jscpd --reporters json` | `jscpd`; slow gate only |
| `comments` | `measure.sh pattern` for `TODO\|FIXME\|XXX` without an issue reference | `pattern.sh` preset (`TODO` must carry `#<n>` or a URL) |
| `spelling` | `codespell`/`cspell` if installed | the tool as a sensor (`pattern.sh` cannot), or not installed |
| `code-style` | formatter `--check` | the project's formatter in `--check` mode (prettier, ruff format, spotless) inside the `lint` sensor |
| `naming` | linter report | ESLint `@typescript-eslint/naming-convention`, ruff `N` rules (pep8-naming), Checkstyle naming checks |
| `suppressions` | `measure.sh pattern` for `eslint-disable\|@ts-ignore\|# noqa\|# type: ignore\|@SuppressWarnings` | `pattern.sh` preset with baseline, so suppressions can only shrink |
| `dependencies` | count of direct dependencies in the manifest | `guard`-style check that a new direct dependency in `package.json`, `pyproject.toml` or `build.gradle*`/`pom.xml` since the base has an ADR naming the manifest: a new `pattern`-like sensor `dependencies.sh` (tests) |
| `type-strictness` | `tsconfig.json` `strict`, mypy `strict`, pyright `typeCheckingMode` | `guard` extension: any of these weakening since the base is a loosening that needs an ADR (tests) |
| `error-handling` | `measure.sh pattern` for empty catch/except blocks | `pattern.sh` preset (`catch\s*\([^)]*\)\s*\{\s*\}`, `except[^:]*:\s*pass`) |
| `logging` | `measure.sh pattern` for `console\.log\|print\(\|System\.out\.print` under source roots | `pattern.sh` preset, excluding tests and scripts |
| `test-conventions` | `measure.sh tests` | `test-presence` + `folder-layout` parameters (test file naming and location); no new sensor |

## Tasks

- [ ] **Task 1 — catalog text.** One section per entry in `skills/rules/references/catalog.md`, or split the catalog into `references/catalog/<entry>.md` with an index if it would pass 300 lines. Each `Why` cites the tool's own documentation URL for the default it names; check each URL exists. No study backs an exact number for agents; say so where it applies, as the `file-size` entry does. Commit `docs(keel-harness): catalog entries (D44), each marked unproven`.
- [ ] **Task 2 — presets and new checks**, tests first:
  - `pattern.sh` presets as documented env-file examples in `contracts/rule-env.md`, plus a test per preset with fixture files that must and must not match: `comments`, `suppressions`, `error-handling`, `logging`;
  - `assets/core/sensors/rules/dependencies.sh` (class `security`, no baseline);
  - the `type-strictness` comparison inside `guard.sh`;
  - `measure.sh` subcommands `function-size <lang>` and `deps`, only if cheap and robust in bash. Otherwise `Measure` says "the linter's report" and no subcommand is added.

  Commit `feat(keel-harness): catalog presets, dependencies sensor, type-strictness in guard`.
- [ ] **Task 3 — `rules` proposes only on evidence.** The proposals phase says: propose a D44 entry only when its measurement shows a problem (any match for a pattern entry; any function over the default for a size entry) or the user asks. Add a `tests/rules_test.sh` assertion. Commit `feat(keel-harness): rules proposes catalog entries only on evidence (D44)`.
- [ ] **Task 4 — master plan:** tick F3d, mark it ✅ with "entries unproven until with/without runs (owner)". Commit `docs(keel-harness): F3d done`.

## Acceptance

- Every entry has the six labels, a status line and cited URLs.
- Every new sensor and preset has must-match and must-not-match tests.
- `guard` flags a weakened `tsconfig` `strict`.
- `./tests/run.sh` exits 0; `validate --strict` passes; `shellcheck` is clean; the size limits hold.
