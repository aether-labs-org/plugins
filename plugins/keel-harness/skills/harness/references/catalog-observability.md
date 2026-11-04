# Catalog - Observability

Logging and error handling. Linter rules first; the `pattern` builtin covers what the linter does not.

Each topic is a section with the same six labels: **Questions** (what to ask), **Measure** (how to read the as-is state), **Default** (how the proposal is derived), **Why** (the reason and its source), **Class and gate** (what enforces it and where), **Opinion** (where the default is judgement). Brownfield: derive the default from the measured distribution (the next round number at or above p90 and not below p75) and say so; greenfield: use the catalog default and say so. The tools per stack are in `stack-typescript.md`, `stack-python.md` and `stack-jvm.md`, one row per topic id. After setup the project's `.agents/keel.yml` is the truth, not this catalog.

## logging

**Questions**: Which logger does the project use? Are scripts and tests allowed to print?
**Measure**: `kh measure logging` once a `pattern` script for direct console output is declared: files and total matches.
**Default**: No direct output in application code (tests and scripts excluded); today's are baselined. Prefer the linter rules when configured.
**Why**: ESLint's `no-console` disallows calls on `console` (https://eslint.org/docs/latest/rules/no-console) and ruff's `T201` flags `print` calls (https://docs.astral.sh/ruff/rules/print/). Output that bypasses the logger has no level, context or destination.
**Class and gate**: heuristic; fast gate through `lint` or the builtin pattern; TSV baseline
**Opinion**: Which logger, and which paths may print.

## error-handling

**Questions**: How does the code report errors (exceptions, result types)? Is swallowing an error ever acceptable here?
**Measure**: `kh measure error-handling` once a `pattern` script for empty handlers is declared: files and total matches.
**Default**: No new empty handler; today's are baselined. The `pattern` builtin sees one-line forms only, so prefer the linter rules where configured.
**Why**: ESLint's `no-empty` flags empty `catch` blocks (https://eslint.org/docs/latest/rules/no-empty), ruff's `S110` flags `except` handlers that only `pass` (https://docs.astral.sh/ruff/rules/try-except-pass/) and Checkstyle's `EmptyCatchBlock` checks for empty catch blocks (https://checkstyle.org/checks/blocks/emptycatchblock.html).
**Class and gate**: heuristic; fast gate through `lint` or the builtin pattern; TSV baseline
**Opinion**: What counts as handling.
