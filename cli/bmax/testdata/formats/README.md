# Recorded tool outputs

Each parsed format has real output of real tools here. `go test ./internal/format` parses every
fixture and compares the result with its `.want.json`.

Convention: `<format>/<tool>-<version>.<ext>` is the recorded output, `<tool>-<version>.cmd` holds
the exact command (line 1), `tool version: ...` (line 2), the recording date (line 3) and, for
`errorformat`, the pattern (line 4); `<tool>-<version>.want.json` is the expected `[]result.Finding`.

How they were recorded: each tool was installed in a scratch directory outside the repository
(npm with a local prefix, a Python venv, Maven/Gradle with the JDK on the machine, release jars)
and run on a minimal project with one failing test or rule. Absolute paths are normalised to
`/work`, host names to `host`, and the Maven `<properties>` block (system properties of the
recording machine) is removed. Nothing else is edited. A tool that changes flags or output after the
recording is not detected by these tests (spec section 17).

## Fixtures

| Format | Fixture | Tool and command |
| --- | --- | --- |
| junit | `junit/vitest-4.1.12` | vitest `run --reporter=junit` |
| junit | `junit/jest-30.5.2` | jest with jest-junit 17.0.0 |
| junit | `junit/playwright-1.64.1` | Playwright Test `--reporter=junit` (a test without a browser) |
| junit | `junit/pytest-9.2.0` | pytest `--junitxml` |
| junit | `junit/gradle-9.1.0` | Gradle 9.1.0 `test` (JUnit Jupiter 5.13.4) |
| junit | `junit/surefire-3.5.4` | Maven Surefire 3.5.4 (JUnit Jupiter 5.13.4) |
| junit | `junit/archunit-1.4.1` | ArchUnit 1.4.1 through `archunit-junit5` on Surefire, a real layering violation |
| checkstyle | `checkstyle/checkstyle-14.4.0` | Checkstyle 14.4.0 with `sun_checks.xml` |
| checkstyle | `checkstyle/detekt-1.23.8` | detekt 1.23.8 `--report xml:` |
| checkstyle | `checkstyle/ktlint-1.8.0` | ktlint 1.8.0 `--reporter=checkstyle` |
| checkstyle | `checkstyle/biome-2.6.5` | Biome 2.6.5 `check --reporter=checkstyle` (lint, format and import findings; a format difference is `source="format"` at line 0) |
| sarif | `sarif/eslint-10.14.0` | eslint 10.14.0 with `@microsoft/eslint-formatter-sarif` 3.1.0 |
| sarif | `sarif/ruff-0.17.3` | ruff 0.17.3 `--output-format sarif` (`--select E,F`) |
| sarif | `sarif/gitleaks-8.30.1` | gitleaks 8.30.1 `--report-format sarif --redact` (fake keys; the report holds none) |
| sarif | `sarif/semgrep-1.183.0` | semgrep 1.183.0 `--sarif` with a local rule (the result has no level: the rule default applies) |
| sarif | `sarif/osv-scanner-2.7.0` | osv-scanner 2.7.0 `scan source --format sarif` on `pyyaml==5.3` |
| sarif | `sarif/detekt-1.23.8` | detekt 1.23.8 `--report sarif:` |
| eslint-json | `eslint-json/eslint-10.14.0` | eslint 10.14.0 `-f json` |
| errorformat | `errorformat/tsc-7.0.2` | tsc 7.0.2 `--noEmit --pretty false` |
| errorformat | `errorformat/mypy-2.4.1` | mypy 2.4.1 `--show-column-numbers --show-error-codes` |
| errorformat | `errorformat/pyright-1.1.414` | pyright 1.1.414 text output (the rule sits on the continuation line, so it stays in the message) |
| errorformat | `errorformat/javac-25` | javac 25 (the source line is joined into the message) |
| errorformat | `errorformat/dependency-cruiser-17.4.3` | dependency-cruiser 17.4.3 `--output-type err` (needs TypeScript below 6: with TypeScript 7 it cruised nothing) |
| errorformat | `errorformat/import-linter-2.15` | import-linter 2.15 `lint-imports` (the "file" is a module name) |
| errorformat | `errorformat/vulture-2.16` | vulture 2.16 |
| errorformat | `errorformat/knip-6.44.1` | knip 6.44.1 `--reporter compact` |

## Unverified

Tools with a catalog row whose format `bmax` parses but that could not be recorded on this machine.
The catalog marks their rows `unverified`.

(none so far)
