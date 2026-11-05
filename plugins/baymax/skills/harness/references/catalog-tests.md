# Catalog - Tests

Unit and integration tests, the kinds of test a project may add (end to end, contract, property-based), the regression rule, mutation testing, coverage and performance. Opt-in items are proposed only when the repository needs them.

Each topic is a section with the same six labels: **Questions** (what to ask), **Measure** (how to read the as-is state), **Default** (how the proposal is derived), **Why** (the reason and its source), **Class and gate** (what enforces it and where), **Opinion** (where the default is judgement). Brownfield: derive the default from the measured distribution (the next round number at or above p90 and not below p75) and say so; greenfield: use the catalog default and say so. The tools per stack are in `stack-typescript.md`, `stack-python.md` and `stack-jvm.md`, one row per topic id. After setup the project's `.agents/bmax.yml` is the truth, not this catalog.

## unit

**Questions**: Which runner does the project use and where do the tests live? How long does the suite take?
**Measure**: `scripts/measure.sh tests` gives main, test, unit, integration and e2e file counts and `untested_main`. The runner itself reports the count and the time.
**Default**: The project's runner, writing a JUnit report, in the slow gate. Prefer the runner's own affected-file selection (`vitest --changed`, `pytest --testmon`) for the fast gate when it exists.
**Why**: The test pyramid puts most checks at the cheap bottom (https://martinfowler.com/articles/practical-test-pyramid.html). A runner with a JUnit report gives bmax named failures instead of a log to grep.
**Class and gate**: correctness; slow gate (and fast when the runner can select affected tests); format junit
**Opinion**: Whether unit tests belong in the fast gate depends on the suite time; the ceiling of the fast gate decides.

## integration

**Questions**: Which tests need a database, a container or the network? Are they separated from unit tests (a directory, a marker, a source set)?
**Measure**: `scripts/measure.sh tests` counts `integration` files by name and directory convention.
**Default**: Run them in the slow gate through the same runner, selected by marker or source set, writing a JUnit report.
**Why**: Integration tests catch what unit tests cannot (wiring, serialisation, queries) and are slower, so they sit in the slow gate (https://martinfowler.com/articles/practical-test-pyramid.html).
**Class and gate**: correctness; slow gate; format junit
**Opinion**: Where the line between unit and integration falls is the team's.

## e2e

**Questions**: Is there a user-facing flow worth an end-to-end test (a browser, a CLI, a public API)? Can CI-less local runs start the system?
**Measure**: `scripts/measure.sh tests` counts `e2e` files; the runner reports duration and flakiness (three runs; see the rubric).
**Default**: Opt-in. One or two critical flows, run in the slow gate. Never in the fast gate.
**Why**: End-to-end tests are the slowest and flakiest layer; a few critical paths give most of the value (https://martinfowler.com/articles/practical-test-pyramid.html).
**Class and gate**: correctness; slow gate; format junit
**Opinion**: Whether to have them at all; they are proposed, never imposed.

## contract

**Questions**: Does the repository consume or expose an API that another team owns? Is there a broker or a shared schema?
**Measure**: Read the code: HTTP clients, message consumers, OpenAPI or schema files. There is no automatic measurement.
**Default**: Opt-in. Consumer-driven contract tests with Pact in the slow gate, only when a second team depends on the interface.
**Why**: A consumer-driven contract fails the provider when it breaks a consumer, without a full integration environment (https://docs.pact.io/).
**Class and gate**: correctness; slow gate; exit code (the contract tests run inside the unit runner)
**Opinion**: Whether the cost of maintaining contracts is worth it for this interface.

## property-based

**Questions**: Are there pure functions with rich input spaces (parsers, serialisers, calculations)? Is a property-based library already a dependency?
**Measure**: Read the code and the dependencies (`scripts/discover.sh` lists the test runner; the library is in the manifest).
**Default**: Opt-in. Properties live in the unit suite, so the unit runner is the sensor; no extra script.
**Why**: Property-based tests explore inputs a person would not write and shrink failures to a minimal case (https://fast-check.dev/, https://hypothesis.readthedocs.io/, https://jqwik.net/).
**Class and gate**: correctness; part of the unit runs; exit code of the runner
**Opinion**: Which functions deserve properties.

## regression

**Questions**: When a bug is fixed here, does the fix come with a test that failed before it?
**Measure**: `bmax measure test-presence` (builtin) counts main files with no mapped test.
**Default**: The `test-presence` builtin (changed main files must have a test at a mapped path), the guide line "a fix comes with a test that failed before", and a checklist item in `docs/review.md`.
**Why**: A regression test pins a fixed defect so it cannot return; mapping main files to tests lets a script check the part that is mechanical. Whether the test failed before the fix is judgement, so it lives in the guide and the review.
**Class and gate**: heuristic; fast or commit gate (builtin test-presence, TSV baseline)
**Opinion**: The mapping from a main file to its test, and which directories are exempt.

## mutation

**Questions**: Is a mutation tool configured? How long does a run on the changed files take?
**Measure**: `scripts/measure.sh tests` reports `mutation_tool`; the tool reports the score.
**Default**: Opt-in. The tool on the changed files in the slow gate, failing below a threshold set in the tool's own configuration (the exit code is the verdict).
**Why**: Mutation testing checks that tests assert something, which matters because generated tests are not trustworthy by default (https://martinfowler.com/articles/harness-engineering.html). Stryker, mutmut and PIT enforce a threshold themselves (https://stryker-mutator.io/docs/stryker-js/configuration/, https://mutmut.readthedocs.io/, https://pitest.org/quickstart/maven/).
**Class and gate**: correctness; slow gate; exit code (threshold in the tool config, protected with `config:`)
**Opinion**: The threshold; start at today's score and raise it.

## coverage

**Questions**: Is coverage measured? On the whole suite or on the diff? Is there a minimum today?
**Measure**: The coverage tool reports the global figure; `diff-cover` reports the figure on the changed lines.
**Default**: Diff coverage of at least 80 percent in the slow gate, and the tool's global threshold when one is already configured. Never lower an existing threshold.
**Why**: Coverage on the changed lines asks whether the new code was exercised without demanding the whole legacy base be covered (https://github.com/Bachmann1234/diff_cover). A global threshold ratchets the whole suite (https://www.jacoco.org/jacoco/trunk/doc/check-mojo.html).
**Class and gate**: correctness; slow gate; exit code (threshold in the command or the tool config)
**Opinion**: The percentage; coverage says what ran, not whether it was checked.

## performance

**Questions**: Does the repository run a service with latency or throughput promises? Is there a load or benchmark suite?
**Measure**: Read the repository: a `load/` or `bench/` directory, k6 or JMH files. Measure with the tool, on a quiet machine.
**Default**: Opt-in, only for services. Thresholds in the tool (k6 `thresholds`, `pytest-benchmark --benchmark-compare-fail`), run in the slow gate or on a schedule.
**Why**: A threshold that fails the run turns a performance promise into a check (https://grafana.com/docs/k6/latest/using-k6/thresholds/).
**Class and gate**: correctness; slow gate; exit code
**Opinion**: Whether performance is a gate at all; it is noisy on shared machines.
