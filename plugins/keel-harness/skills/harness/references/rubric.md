# The rubric, and the right to say "I don't know"

Fifteen axes. Each is `absent`, `partial` or `present` with the file that proves it, or `not measured`. There is no aggregate
score: a score suggests the ruler measures quality, and it measures the presence of evidence. Report each axis alone, never a
total and never an overall grade.

| Axis | Present | Partial | Absent | Proving file |
| --- | --- | --- | --- | --- |
| **Bootstrap** | One command installs and builds, and it runs without a prompt | The command exists and fails, or needs a manual step | None | `Makefile`, `package.json` scripts, `gradlew` |
| **Reproducible build** | A committed lockfile and a frozen install (`npm ci`, `pnpm install --frozen-lockfile`, `uv sync --frozen`) or a committed Gradle or Maven wrapper | A lockfile without a frozen install, or no wrapper | No lockfile | lockfile, wrapper, the bootstrap command |
| **Guides** | `AGENTS.md` of at most 100 lines that carries only what an agent cannot discover, and topic files that exist | One of the two, or an index over 100 lines | Neither | `AGENTS.md`, `docs/` |
| **Context reach** | Every agent in use loads `AGENTS.md`: Copilot and Devin natively, Claude Code through a `CLAUDE.md` that is exactly `@AGENTS.md` | `AGENTS.md` exists but a `CLAUDE.md` without the import hides it from Claude Code | No instruction file | `CLAUDE.md`, `AGENTS.md` |
| **Fast gate** | `.agents/keel.yml` declares a `fast` gate with `guard` and checks that run (types, lint, secrets) inside its ceiling | A gate that is declared but a script in it does not run, or has no ceiling | No gate | `.agents/keel.yml` |
| **Slow gate** | A `slow` gate runs the suite (JUnit report) and `merge-check`; mutation or coverage is configured when the project wants it | The suite runs without a report, or fails | No suite | `.agents/keel.yml`, the test configuration |
| **Enforcement** | Git hooks run the `commit` and `slow` gates (`.agents/githooks/` with `core.hooksPath`, or a hook manager that calls the wrapper) and the agent hooks run the Stop and PreToolUse hooks. No CI is required | One of the two | Neither | `.agents/githooks/`, `.claude/settings.json`, `kh check` |
| **Protection** | `.claude/settings.json` registers `kh hook pre-tool-use`; the guides, ADRs, config and baselines are in the protected set | Hooks registered but guides unlisted in `guides:` (`guide-unlisted`) | No hook | `.claude/settings.json`, `guides:` |
| **Rules** | At least one rule recorded in a topic file and enforced by a script, with its ADR | Documented rules with no script, or scripts with no ADR | None | `docs/`, `.agents/keel.yml`, ADRs |
| **Memory** | `.agents/plans/`, `progress.md` and `lessons.md` follow the formats (`memory` builtin passes) and `.agents/run/` is ignored | Some of it | None | `.agents/`, `.gitignore` |
| **Git cycle** | A commit convention enforced by `commit-message`, a PR template, `scope` and `merge-check` where the team wants them | One of them | None | `.agents/keel.yml`, `.github/` |
| **Review** | `docs/review.md` and both reviewer definitions exist; `AGENTS.md` says to ask the human before finishing | Some of it | None | `docs/review.md`, `.claude/agents/`, `.github/agents/` |
| **Security** | A secrets script of class `security`, plus SCA or SAST where the stack has them, none with a baseline | Secrets only | Nothing | `.agents/keel.yml` |
| **Observability** | A structured logging library configured and a log-format line in a guide | One of the two | Neither | logging config, `AGENTS.md`, `docs/` |
| **Flaky tests** | Measured: the fast test command ran three times and the three runs agree on every test | A test changed result between runs | (never absent) | the test command |

`Flaky tests` is the only axis that is measured, not read. Running the fast test command three times needs the user's agreement
first, persists no output (discard reports and caches, or write them outside the repository), and reports the seconds it took.
Without agreement, or when the command does not run, the state is `not measured`, never `absent` and never a guess.

## Evidence and `not measured`

- Every state names the file that proves it. A claim with no file is not made.
- What can be measured is measured by a script (`kh measure`, `scripts/measure.sh`), never estimated. Time a tool by running it
  once on the real repository. When a tool is not installed and cannot be run, its cost is `not measured`.
- Setup minutes are an estimate and say so; seconds added to the gate are measured.
- A read-only diagnosis writes nothing: run only read-only commands, and ask before running anything that writes.

## Cost units

- **Estimated setup minutes**: how long closing the gap takes, confirmations included.
- **Seconds added to the gate**: what the script adds to every edit, measured on the real repository.

## Confidence

Every inference ends in a confirmation, never an open question. Three levels:

| Confidence | You do | Example |
| --- | --- | --- |
| **High**: consistent evidence | State the inference and ask for acceptance | "I see `api/`, `domain/` and `db/`, and `domain/` never imports `db/`. Is that the rule?" |
| **Low**: partial or contradictory | Ask a narrow question with the options seen | "I found two plausible layerings. Is it (a) or (b)? Or neither?" |
| **None** | Say you could not infer it, install nothing for that layer, and say why | "I could not identify module boundaries. Without them an architecture check would be an invented rule, so I leave it out." |

The `none` outcome prevents the most expensive failure of this kind of tool: installing a rule you invented and presenting it as
the project's. A layer left out costs one line of explanation; an invented rule costs trust in every other rule.

See also: [discovery](discovery.md) for how to gather the evidence, [rounds](rounds.md) for how to turn it into questions.
