# Catalog - Code

Types, lint, naming, complexity, function size, parameters, suppressions, formatting, dead code, duplication, file size, code language, comments and spelling. Linter-backed topics run the repository's own linter, never a copy of its rules.

Each topic is a section with the same six labels: **Questions** (what to ask), **Measure** (how to read the as-is state), **Default** (how the proposal is derived), **Why** (the reason and its source), **Class and gate** (what enforces it and where), **Opinion** (where the default is judgement). Brownfield: derive the default from the measured distribution (the next round number at or above p90 and not below p75) and say so; greenfield: use the catalog default and say so. The tools per stack are in `stack-typescript.md`, `stack-python.md` and `stack-jvm.md`, one row per topic id. After setup the project's `.agents/keel.yml` is the truth, not this catalog.

## types

**Questions**: Which type checker runs, at what strictness? Is it run in the build?
**Measure**: Read the configuration: `tsconfig.json` `strict`, mypy `strict`, pyright `typeCheckingMode`. `scripts/discover.sh` reports the checker.
**Default**: Keep what is configured; weakening it is a loosening that `guard` reports. Greenfield: the strictest mode the stack offers.
**Why**: TypeScript's `strict` turns on a family of checks (https://www.typescriptlang.org/tsconfig/#strict), mypy's `--strict` enables a predefined subset (https://mypy.readthedocs.io/en/stable/command_line.html) and pyright's `typeCheckingMode` is `off`, `basic`, `standard` or `strict` (https://microsoft.github.io/pyright/#/configuration). A model that fails to type-check can lower the mode instead of fixing the code.
**Class and gate**: correctness; fast gate; format errorformat
**Opinion**: The target strictness, and a migration plan when it is not strict yet.

## lint

**Questions**: Which linter runs and with which configuration? Are there findings today?
**Measure**: Run the linter with its own configuration and count findings with `kh measure lint` once the script is declared.
**Default**: The repository's linter with its own configuration. Brownfield: today's findings per file become a TSV baseline (heuristic, ratchet). Greenfield: strict.
**Why**: A ratchet lets the count only shrink, so legacy findings do not block work while no new ones enter (spec section 6).
**Class and gate**: heuristic; fast and commit gates; format eslint-json, sarif or checkstyle; TSV baseline
**Opinion**: Which rules are on; start from the linter's recommended set.

## naming

**Questions**: Which naming conventions does the team hold (case per kind of identifier, prefixes)?
**Measure**: The linter's report with only the naming rules on, counting findings.
**Default**: The language's convention as the linter encodes it; brownfield, today's findings are the baseline.
**Why**: `@typescript-eslint/naming-convention` takes a style per kind of identifier (https://typescript-eslint.io/rules/naming-convention/); ruff's `N` rules implement pep8-naming (https://docs.astral.sh/ruff/rules/#pep8-naming-n); Checkstyle's naming checks default to lowerCamelCase for methods (https://checkstyle.org/checks/naming/methodname.html).
**Class and gate**: heuristic; fast gate through the `lint` script; TSV baseline
**Opinion**: Every convention.

## complexity

**Questions**: Is cyclomatic complexity already reported? Which functions are tangled on purpose (parsers, state machines)?
**Measure**: The linter's report with only the complexity rule on, counting findings.
**Default**: Brownfield: the next round number at or above p90 of the reported values. Greenfield: 10.
**Why**: Checkstyle's default is 10 (https://checkstyle.org/checks/metrics/cyclomaticcomplexity.html), detekt's 14 (https://detekt.dev/docs/rules/complexity/) and ESLint's 20 (https://eslint.org/docs/latest/rules/complexity); ruff's `C901` takes `lint.mccabe.max-complexity` (https://docs.astral.sh/ruff/rules/complex-structure/). No study gives an exact number for agents.
**Class and gate**: heuristic; fast gate through the `lint` script; TSV baseline
**Opinion**: The number, and which functions are exempt.

## function-size

**Questions**: Is there a function length you already review against? Are generated functions excluded?
**Measure**: The linter with only this rule on, at the candidate size, counting findings and the files they sit in.
**Default**: Brownfield: the next round number at or above p90 of the lengths it shows. Greenfield: 50 lines.
**Why**: Tool defaults disagree: ESLint `max-lines-per-function` 50 (https://eslint.org/docs/latest/rules/max-lines-per-function), detekt `LongMethod` 60 (https://detekt.dev/docs/rules/complexity/), Checkstyle `MethodLength` 150 (https://checkstyle.org/checks/sizes/methodlength.html), ruff `PLR0915` counts statements, 50 by default (https://docs.astral.sh/ruff/rules/too-many-statements/). No study measures an optimal size for agents; the case for a limit is that a short function is read whole. Say so when proposing it.
**Class and gate**: heuristic; fast gate through the `lint` script; TSV baseline
**Opinion**: The exact number is opinion.

## max-params

**Questions**: Is there a parameter count you already review against? Do constructors or injected classes need a higher one?
**Measure**: The linter with only the parameter rule on, counting findings.
**Default**: Brownfield: the next round number at or above p90 of the counts. Greenfield: 5.
**Why**: Defaults disagree: ESLint 3 (https://eslint.org/docs/latest/rules/max-params), ruff 5 (https://docs.astral.sh/ruff/rules/too-many-arguments/), detekt 5 for functions (https://detekt.dev/docs/rules/complexity/), Checkstyle 7 (https://checkstyle.org/checks/sizes/parameternumber.html). No study measures an optimal count for agents.
**Class and gate**: heuristic; fast gate through the `lint` script; TSV baseline
**Opinion**: The number.

## suppressions

**Questions**: How many lint or type-check suppressions are in the code today? Is there a reviewed list of acceptable ones?
**Measure**: `scripts/measure.sh` has no subcommand for this; run `kh measure suppressions` once a `pattern` script (for example `@ts-ignore|@ts-nocheck|# noqa|# type: ignore|@SuppressWarnings`) is declared.
**Default**: No new suppression: today's count per file is the baseline, so suppressions can only shrink. Use the linter's own rule (`eslint-comments`, ruff `PGH003`, Checkstyle `SuppressWarnings`) when configured, and the `pattern` builtin otherwise.
**Why**: A suppression silences the check that was meant to catch the problem; `@typescript-eslint/ban-ts-comment` bans `@ts-ignore` and `@ts-nocheck` by default (https://typescript-eslint.io/rules/ban-ts-comment/). An agent told to make a failing check pass can add one, which is why the guidance says not to.
**Class and gate**: heuristic; fast gate (builtin pattern, TSV baseline)
**Opinion**: Whether a reasoned suppression is allowed (`@ts-expect-error` is left out of the pattern on purpose).

## formatting

**Questions**: Which formatter does the project use, and is it checked anywhere?
**Measure**: The formatter in check mode (`prettier --check`, `ruff format --check`, `spotlessCheck`); the count of files it would change.
**Default**: The project's formatter with its own configuration, in check mode, in the fast gate. Today's unformatted files should be formatted once, in a commit of their own, rather than baselined.
**Why**: The formatters document a check mode that changes nothing and exits non-zero on drift (https://prettier.io/docs/cli#--check, https://docs.astral.sh/ruff/formatter/, https://github.com/diffplug/spotless). Style is then no longer a matter of review.
**Class and gate**: correctness; fast gate; exit code
**Opinion**: Which formatter and its settings are the team's.

## dead-code

**Questions**: Is an unused-code tool already part of the build? Is the repository a library whose exports are used elsewhere?
**Measure**: The tool's report: `knip` for TypeScript, `vulture` for Python, PMD for the JVM. Optional; with the tool not installed there is nothing to measure.
**Default**: Report only: a TSV baseline of today's findings so the count can only shrink, in the slow gate.
**Why**: Static tools flag exports and functions with no detected use (https://knip.dev/, https://github.com/jendrikseipp/vulture, https://pmd.github.io/); they miss dynamic use, so findings are leads, not proof. Agents add helpers and leave the old ones behind, but nothing measured in this repository shows how often.
**Class and gate**: heuristic; slow gate; format errorformat (knip, vulture) or exit code (PMD); TSV baseline
**Opinion**: Whether to run it at all, and which findings are false positives.

## duplication

**Questions**: Is copy-paste detection already run? Which directories are generated or intentionally parallel?
**Measure**: `jscpd --reporters json` over the source roots, if installed: the percentage and the clone count.
**Default**: Report only, in the slow gate, with the tool's `--threshold` set to today's percentage.
**Why**: jscpd finds duplicated blocks across many languages (https://github.com/kucherenko/jscpd). A model that cannot see the whole repository tends to rewrite what exists; that is a hypothesis, not a measured effect here.
**Class and gate**: heuristic; slow gate; exit code
**Opinion**: The clone size that matters, and every threshold.

## file-size

**Questions**: Is there a size you already hold files to? Are generated or vendored files excluded?
**Measure**: `kh measure file-size` once the builtin is declared: per-file lines over the limit; `scripts/measure.sh` no longer has this subcommand.
**Default**: Brownfield: the next round number at or above p90 and not below p75 (for example p90 = 240, so 300). Greenfield: 300 lines.
**Why**: ESLint's `max-lines` defaults to 300 (https://eslint.org/docs/latest/rules/max-lines). Tool defaults disagree widely (Pylint's `max-module-lines` is 1000, Checkstyle's `FileLength` 2000), and no study measures an optimal size for agents; the case for a limit is that a short file is read whole and tends to hold one responsibility. Say so when proposing it.
**Class and gate**: heuristic; fast gate (builtin file-size, TSV baseline)
**Opinion**: The exact number is opinion; 300 is a convention, not a measurement.

## code-language

**Questions**: In which natural language must identifiers and comments be written? Is user-facing text in another language (it is ignored)?
**Measure**: `kh measure code-language` once the builtin is declared: flagged words per file.
**Default**: English for identifiers and comments; string literals ignored.
**Why**: Opinion, not measurement: one language for names keeps search and naming consistent. Back it with the measured count of flagged words and do not claim more than that. The stop-list is a heuristic; it catches Portuguese words, not every language.
**Class and gate**: heuristic; fast gate (builtin code-language, TSV baseline)
**Opinion**: Whether to enforce it at all is the team's call.

## comments

**Questions**: Do TODO, FIXME or XXX comments carry an issue reference today? Which tracker, and what does a reference look like?
**Measure**: `kh measure comments` once a `pattern` script (markers with no reference) is declared.
**Default**: A marker is allowed only with a reference right after it (`TODO(#123)`, `TODO: https://...`); today's markers are baselined.
**Why**: ESLint's `no-warning-comments` flags `todo`, `fixme` and `xxx` (https://eslint.org/docs/latest/rules/no-warning-comments) and ruff's `TD003` asks for a link on a TODO (https://docs.astral.sh/ruff/rules/missing-todo-link/). An unreferenced marker is a promise nobody tracks.
**Class and gate**: heuristic; fast gate (builtin pattern, TSV baseline); prefer the linter rules when configured
**Opinion**: Whether markers are forbidden outright or only need a reference.

## spelling

**Questions**: Is a spell checker already in the project? Which words are domain terms?
**Measure**: `codespell` or `cspell` if installed: the count of findings. Optional.
**Default**: Report only, with a project dictionary for domain terms. No builtin spell-checks.
**Why**: codespell uses curated lists of common misspellings (https://github.com/codespell-project/codespell) and cspell is a configurable checker for code (https://cspell.org/); both need the repository's own word list to avoid noise.
**Class and gate**: heuristic; slow gate; exit code
**Opinion**: Whether misspellings are worth a gate.
