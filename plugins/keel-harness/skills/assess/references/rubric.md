# The rubric, and the right to say "I don't know"

Eleven axes, three states each (`Flaky tests` also has `not measured`), mandatory evidence. No third-party diagnosis tool — this is a
deterministic internal scan.

| Axis | Present | Partial | Absent |
| --- | --- | --- | --- |
| **Bootstrap** | Lockfile, and a single target that installs and builds — and it runs | Lockfile without a single target, or a target that exists and fails | Neither |
| **Guides** | An instruction file a target agent reads (`AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md`, `.devin/rules`), at most 100 lines, and `docs/` with content | One of the two, or an instruction file over the ceiling | Neither |
| **Fast sensors** | Types and style configured *and* runnable; an architecture tool configured (dependency-cruiser, ArchUnit, import-linter) counts as a structure sensor | Configured, but one does not run | No configuration |
| **Slow sensors** | A suite that runs, coverage configured **and** mutation testing configured (PIT, Stryker, mutmut) | Suite without coverage or without mutation testing, or a suite that fails | No suite |
| **Enforcement** | `.pre-commit-config.yaml`, husky or lefthook, plus a CI workflow running the same commands | One of the two, or divergent local/CI commands | Neither |
| **Context** | The instructions reach every target agent: `AGENTS.md` exists and either there is no `CLAUDE.md` or `CLAUDE.md` imports `@AGENTS.md` | `AGENTS.md` exists but a `CLAUDE.md` without the import hides it from Claude Code | No instruction file |
| **Rules** | At least one rule documented as a section in `docs/architecture.md`, `docs/conventions.md` or `docs/testing.md` with a sensor that enforces it | Documented rules without enforcement, or TODO stubs | None |
| **Reproducible build** | A committed lockfile **and** a frozen install in the `make bootstrap` target (`npm ci`, `pnpm install --frozen-lockfile`, `uv sync --frozen`, `poetry install --sync`) or a committed Gradle or Maven wrapper | A lockfile without a frozen install, or no wrapper | No lockfile |
| **Headless setup** | `make bootstrap` runs with no prompt: no `read`, no interactive login in the target; a `.env.example` when the code reads environment variables; a devcontainer is optional | One blocker found (a `read`, an interactive login, an env var the code needs and no `.env.example` names) | No bootstrap target |
| **Flaky tests** | Measured: the fast test command ran 3 times and all 3 runs agree on every test | Some test changed result between runs | Never. An unmeasured axis is reported `not measured`, not `absent` |
| **Observability** | A structured logging library configured (`pino`, `winston` with JSON, `structlog`, `logback` with a JSON encoder, ...) **and** a log-format line in `AGENTS.md` or `docs/` | One of the two | Neither |

The four axes after `Rules` are appended in this order, and the report keeps it: `Reproducible build`,
`Headless setup`, `Flaky tests`, `Observability`. Each is a signal with its own evidence and cost;
none is folded into another axis, and none enters a total (there is none).

**Reproducible build.** Evidence is the lockfile (or the wrapper script) and the Makefile that holds
the frozen install. A repository whose `make bootstrap` runs a plain `npm install` is `partial`: the
lockfile exists, but the install can rewrite it.

**Headless setup.** Evidence is the `Makefile` (or the file the target calls). Read the target body;
do not run it, because an install writes. One blocker is `partial`; no target at all is `absent`.

**Flaky tests.** This is the only axis that is *measured*. Running the fast test command three times
is a measurement, not a write, and it follows the single rule of `SKILL.md`: it needs the user's
agreement first, it persists no output (discard reports and caches, or redirect them outside the
repository), and the seconds it took are reported. Without agreement, or when the command is not
installed or does not run, the state is `not measured`, never `absent` and never a guess. The command
comes from discovery, never from assumption.

**Observability.** Evidence is the file that configures the logging library, plus the `AGENTS.md` or
`docs/` file that holds the log-format line. Finding only one of the two is `partial`.

## There is no aggregate score

This is a decision, not an oversight. A score suggests the ruler measures quality; it measures
presence of evidence. Summing axes would require weights no source justifies. Report each axis on
its own; never a total, never an overall grade.

## Cost units

- **estimated setup minutes** — how long `build` or `rules` takes to close that gap, confirmations included.
- **seconds added to the gate** — how much that sensor adds to every edit, measured by running the
  tool once on the real repository, never estimated.
- **`+N.Ns per run`** — only for `Flaky tests`: the measured seconds one run of the fast test command
  takes, which is what each extra run adds. Report the seconds the three runs took in total in the
  line under the table. `not measured` when it was not run.

Seconds are **measured**; setup minutes are labelled an estimate, since they cannot be measured before the skill runs. Run the tool once when it is installed and read the
real number. When the tool is not installed and cannot be measured, the cost is reported as
**not measured** — never as a guess.

## The third inference outcome

The rule "never an open question, always a confirmation of an inference" needs an exit for when
the inference fails. Three confidence levels, not two:

| Confidence | The kit does | Example |
| --- | --- | --- |
| **High** — consistent evidence | States the inference and asks for acceptance | "I see `api/`, `domain/` and `db/`, and `domain/` never imports `db/`. Is that the rule?" |
| **Low** — partial or contradictory | Narrow question with the options seen — never an open one | "I found two plausible layerings. Is it (a) or (b)? Or neither?" |
| **None** | Declares it could not infer, **does not install the layer**, records the reason in `.agents/state.yml` | "I could not identify module boundaries here. Without them a fitness function would be an invented rule — leaving it out." |

The `none` outcome exists to prevent the most expensive failure mode of this category of tool:
installing a rule the kit invented and presenting it as the project's. A layer left out costs one
line of explanation; an invented rule costs trust in every other rule.
