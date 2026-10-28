# keel-harness

Assess, install and maintain an AI-agent harness and the project's own rules — architecture, testing
strategy, conventions — in a repository. keel acts as a harness engineer: it listens to the team,
measures what the code does today, proposes what it should do and why, and records what the human
approves. Everything deterministic ships as tested bash files you can read and edit; the skills hold
only judgment.

## Skills

### `/keel-harness:assess`

Diagnoses how ready a repository is for AI coding agents on a seven-axis rubric (bootstrap, guides,
fast sensors, slow sensors, enforcement, context, rules) and infers whether it is greenfield or
brownfield.

- **Reads:** stack markers, scripts, sensors, every instruction file the target agents load, `docs/`
- **Writes:** nothing

### `/keel-harness:build`

Installs the harness: bootstrap, `AGENTS.md` (at most 100 lines) and a `CLAUDE.md` that imports it, a
fast and a slow gate, tool sensors, the Claude Code Stop hook, the portable validator and a guide for
editing the harness by hand. Asks in rounds of at most 4 questions and upgrades v0.1 installs.

- **Reads:** repository structure, user confirmations
- **Writes:** `AGENTS.md`, `CLAUDE.md`, `Makefile`, `scripts/` (gate, sensors, hook, validator, baseline
  library), `.agents/` (state, gate budgets, guide), `.claude/settings.json` (merged), `.gitignore`

### `/keel-harness:rules`

Decides, records and enforces the repository's own rules with the team: context interview, as-is
measurements, proposals backed by data and a cited source, rounds of questions, ADRs. It writes only
what the user approved and never migrates production code.

- **Reads:** the code (read-only measurements), instruction files, existing ADRs
- **Writes:** rule sections in `docs/architecture.md`, `docs/conventions.md`, `docs/testing.md`;
  ADRs in the repository's ADR folder (`docs/adr/` by default); `.agents/rules/<id>.env`; rule sensors, baselines and generated tool config
  (ArchUnit test, `.dependency-cruiser.cjs`, `.importlinter`); local plans in `.agents/plans/`

### `/keel-harness:doctor`

Runs the repository's own validator (`harness-check.sh`, 14 checks), explains each warning and proposes
the fix. Writes nothing.

## The v0.2 rule

**keel proposes, the human decides.** Facts (commands, structure, measurements) are discovered or
measured. Norms (rules, limits, architecture, tools) may be proposed with a justification and are
written only after approval, in rounds of questions. An approved breaking change becomes a rule, a
baseline, an ADR and a local migration plan; keel never executes the migration. Still no action is
blocked: the Stop hook hands the fast gate's guidance back to Claude and stops after a loop guard.

## Target agents

| Agent | What it gets |
| --- | --- |
| Claude Code | `AGENTS.md` via the `CLAUDE.md` import, plus the Stop hook that returns gate guidance |
| GitHub Copilot | `AGENTS.md` (nearest file wins): "Before you finish" tells it to run `make gate-fast` and read it |
| Devin | `AGENTS.md` (CLI and Desktop). **Risk:** whether Devin's cloud product reads `AGENTS.md` is unverified |

## Stacks, architecture and mutation tools

| Stack | Fast gate | Architecture rule | Mutation (slow gate) |
| --- | --- | --- | --- |
| TypeScript | tsc, ESLint, Vitest/Jest, gitleaks | dependency-cruiser | Stryker |
| React | as TypeScript (reuses `sensors/typescript/`) | dependency-cruiser | Stryker |
| Python | mypy/pyright, ruff, pytest, gitleaks | import-linter | mutmut |
| Java / Kotlin | compile, Checkstyle/ktlint/detekt, JUnit, gitleaks | ArchUnit (`onionArchitecture()`) | PIT |

Go and Terraform stay documentation only. `make gate-slow` runs mutation testing and diff coverage
on the changed files; it is never run by the hook and never wired to CI.

## Tests

`make check` runs `tests/run.sh`: shell tests with stub tools (no network, no model, free).
`make validate` runs `claude plugin validate --strict`.

## Evals (`claude plugin eval`, manual and paid)

Run `claude plugin eval . --scaffold` from `plugins/keel-harness/`. Host prerequisites per case:

| Case | Host prerequisites |
| --- | --- |
| `assess-mature-repo`, `assess-claude-md`, `should-not-trigger` | none |
| `build-typescript`, `build-react`, `gate-catches-defect`, `rules-brownfield`, `rules-effect-with/without` | node/npm, network, `gitleaks`, `socat`, `bwrap`; `--allow-tools Write Edit Bash` |
| `build-python` | python3 with `venv`, network |
| `build-java`, `rules-architecture-java` | JDK 17+, network (Gradle wrapper) |
| `rules-greenfield` | none beyond the tool allow-list |
| `doctor-finds-drift`, `doctor-validator-drift` | node/npm, network, `gitleaks`; `--allow-tools Bash` (the doctor skill runs the validator) |

v0.2 numbers, **partial baseline**: 5 of the 15 cases measured (the read-only ones). `rules-effect-with`
and `rules-effect-without` are meant to run with `--ablation none` and be compared by hand, since that
pair is the only test of whether rules proposed by keel and approved by a human help an agent; they
have not run.

- Dates: 2026-10-25 (smoke run) and 2026-10-28 (the measured runs).
- Claude Code: 2.1.310 for the smoke run, 2.1.312 for all measured runs (the CLI updated between the two
  dates). The result files do not record the model.
- Measured at commit `cf495ff`, each case 3 runs per arm (with-without ablation).
- Host: Ubuntu 26.04.1 LTS, kernel 7.0.0-42-generic.
- Not run: the 10 tool cases (`build-typescript`, `build-python`, `build-java`, `build-react`,
  `gate-catches-defect`, `rules-brownfield`, `rules-greenfield`, `rules-architecture-java`,
  `rules-effect-with`, `rules-effect-without`). On this host AppArmor
  `apparmor_restrict_unprivileged_userns=1` blocks nested bwrap (`bwrap: No permissions to create a new
  namespace`), which Claude Code's Bash sandbox needs. The owner chose to measure only the 5 read-only
  cases here, and the sandbox was not weakened.
- F1b attempt (2026-10-28, stopped by the owner): a Claude Code cloud container (Ubuntu 24.04.5 LTS,
  Claude Code 2.1.312, running as root) passed the nested-bwrap check, but no tool case qualified. Under
  `claude plugin eval` the Bash sandbox mounted the working directory, `.git`, `.claude` and `$TMPDIR`
  read-only, so `gate-catches-defect` could not write `gate-output.txt` (WITH 0.20, W-OUT 0.20, one run
  per arm). Spent USD 0.22. See findings.
- Total spent: USD 5.18 (smoke 0.12, `should-not-trigger` 0.36, `assess-*` 1.68, `doctor-*` 3.03).
- Cost (USD) is each case's total `costUsd` over 3 runs x 2 arms (judge cost was 0). The smoke run is not
  included in the per-case costs. Raw results: `docs/evals/keel-v0.3-f0/`.

| Case | WITH | W-OUT | Δ | Verdict | Cost (USD) |
| --- | --- | --- | --- | --- | --- |
| `assess-mature-repo` | 1.00 | 0.33 | +0.67 | pass | 0.82 |
| `assess-claude-md` | 1.00 | 0.60 | +0.40 | pass | 0.85 |
| `should-not-trigger` | 1.00 | 1.00 | 0.00 | pass (correct result) | 0.36 |
| `build-typescript` | not run | | | host-blocked (nested bwrap) | |
| `build-python` | not run | | | host-blocked (nested bwrap) | |
| `build-java` | not run | | | host-blocked (nested bwrap) | |
| `build-react` | not run | | | host-blocked (nested bwrap) | |
| `gate-catches-defect` | not run | | | host-blocked (nested bwrap) | |
| `rules-brownfield` | not run | | | host-blocked (nested bwrap) | |
| `rules-greenfield` | not run | | | host-blocked (nested bwrap) | |
| `rules-architecture-java` | not run | | | host-blocked (nested bwrap) | |
| `rules-effect-with` / `-without` | not run | | | host-blocked (nested bwrap) | |
| `doctor-finds-drift` | 1.00 | 0.33 | +0.67 | pass | 1.52 |
| `doctor-agents-not-loaded` | 1.00 | 1.00 | 0.00 | retired in E1, see findings | 1.51 |
| `doctor-validator-drift` (E1) | 0.80 | 0.67 | +0.13 | weak; `writes-nothing` confounded, see E1 results | 0.59 |

### Findings (partial baseline at `cf495ff`)

**`should-not-trigger` (Δ 0.00).** This is the negative control: the skill must stay silent on an
unrelated git question, so Δ 0 is its expected result, and v0.1 recorded it the same way. All 3 runs in
both arms scored 1.00. Whether the existence floor applies to a control case is left to the owner.

**`doctor-agents-not-loaded` (Δ 0.00).** WITH 1.00 and W-OUT 1.00 in all 3 runs each: the no-plugin arm
also named the CLAUDE.md that does not import `AGENTS.md` and the `@AGENTS.md` bridge, so this case does
not separate the two arms in this measurement. It is a candidate for the existence floor (rewrite or
delete after three consecutive runs with Δ ≤ 0); this is one measurement session, and nothing is deleted
in F1.

**E1 (2026-10-28): `doctor-agents-not-loaded` retired, `doctor-validator-drift` added.** A model without
the plugin already knows the `@AGENTS.md` bridge, and `harness-check.sh`'s `agents-not-loaded` check is
covered by `tests/keel_harness_check_test.sh`. The new case tests what only the plugin's `doctor` adds:
the repository carries an older `harness-check.sh` that has no `guard-missing` check and reports no
guard problem, the guard sensor is missing, and only the plugin's current validator names it. Both
`doctor-*` cases now grant `Bash`, which the skill needs to run the validator: F1's `doctor-*` runs
could not run it. The scaffold's AGENTS.md also points at `dist/`, which the scaffold never builds, so
`dangling-pointer` is an extra warning in both cases; the graders do not count warnings.

**E1 results (2026-10-28, commit `c8b71ca`).** Both `doctor-*` cases, 3 runs per arm (with-without),
`--allow-tools Bash`, in a Claude Code cloud container (Ubuntu 24.04, Claude Code 2.1.312, `gitleaks`
8.24.2, nested bwrap working). Spent USD 1.17 of the approved USD 8 (measured run 1.10, plus a 0.06
diagnostic run; a first attempt died in every scaffold before any agent turn and cost 0). Raw results:
`docs/evals/keel-v0.3-e1/`.

| Case | WITH | W-OUT | Δ | WITH / W-OUT without `writes-nothing` | Cost (USD) |
| --- | --- | --- | --- | --- | --- |
| `doctor-finds-drift` | 0.44 | 0.67 | -0.22 | 0.67 / 1.00 | 0.52 |
| `doctor-validator-drift` | 0.80 | 0.67 | +0.13 | 1.00 / 0.83 | 0.59 |

- **Not comparable with F1.** F1's `doctor-finds-drift` row (1.00 / 0.33) ran without Bash; these runs
  grant it, so the WITH arm can run the validator and the W-OUT arm can run any command.
- **`writes-nothing` failed in all 12 runs, in both arms.** Whenever Claude Code's Bash tool runs, it
  creates an empty directory `.claude/.cc-writes/` in the working directory (reproduced with a one-`ls`
  case and `--keep-temp`), and the grader's `**/*` matches it. It measures the Bash tool, not the agent,
  and costs every run 1/3 (`doctor-finds-drift`) or 1/5 (`doctor-validator-drift`) of its score. The
  grader was not changed in E1; the column above shows the scores without it. Running
  `harness-check.sh` itself writes nothing.
- **`doctor-validator-drift` separates the arms only weakly.** WITH named the missing guard and the
  validator drift in 3 of 3 runs; W-OUT named the guard in 3 of 3 and the drift in 2 of 3. The Δ comes
  from that one W-OUT run. WITH needed 4 to 5 turns, W-OUT 10.
- **`doctor-finds-drift` has Δ ≤ 0.** W-OUT named the AGENTS.md size drift in 3 of 3 runs, WITH in 2 of
  3. The trace files were not retained, so why the one WITH run missed it is not known. With Bash, the
  no-plugin arm can find the drift itself.
- **Host fix.** The eval strips the proxy and CA variables from the scaffold's environment, so `npm
  install` failed with `SELF_SIGNED_CERT_IN_CHAIN` in this container. Setting `cafile` in npm's global
  config (`/opt/node22/etc/npmrc`, pointing at the container's proxy CA bundle) fixed it; the sandbox
  was not changed.

No case scored below 1.0 in the WITH arm. In the W-OUT arm the failing graders were: `rubric-axes` and
`rubric-states` (`assess-mature-repo`), `context-partial` (`assess-claude-md`), `names-the-drift`
(`doctor-finds-drift`), each in all 3 runs.

**Confounders.**
- All five cases allow only `[Read, Glob, Grep, Skill]`. The `doctor` skill's first step runs
  `harness-check.sh` through Bash, which these cases do not grant. The WITH arm still scored 1.00 on both
  `doctor-*` cases, but the result files keep no transcripts (the trace files were not retained), so
  whether the validator ran or the agent read the files by hand is not known from this data.
- The recorded turns of the `doctor-*` runs (WITH 12 to 21, W-OUT 16 to 23) go above the `max_turns: 20` in
  their prompts; the result files do not say how turns are counted.
- The `doctor-*` run exceeded its USD 3 ceiling by USD 0.03 through runs already in flight; no run was
  skipped and the exit code was 0.
- Claude Code changed from 2.1.310 to 2.1.312 between the smoke run and the measured runs.

**F1b attempt: the 10 tool cases are still not measured.** F1b
(`docs/plans/2026-10-28-keel-harness-v0.3-f1b-plan.md`) tried a cloud container and stopped at its smoke
run (`gate-catches-defect`, one run per arm). Raw results: `docs/evals/keel-v0.3-f0/f1b-smoke*.json`.
- Host checks passed: `bwrap` inside `bwrap` (including a writable bind), `gitleaks` 8.24.2
  (checksum-verified), OpenJDK 21, node 22 / npm 10, python3 `venv`, `validate --strict`.
- Scaffold: `claude plugin eval` runs scaffolds with a minimal environment that drops
  `NODE_EXTRA_CA_CERTS`. The container's egress proxy re-signs TLS, so `npm install` retried until the
  scaffold was killed (`scaffold failed (exit null)` after about 281 s, USD 0). pip, Java and curl were
  not affected. Fixed on the host with `cafile=/root/.ccr/ca-bundle.crt` in npm's global `npmrc`
  (`/opt/node22/etc/npmrc`); no plugin, eval or sandbox setting changed.
- Bash sandbox: with the scaffold fixed, both arms scored 0.20. The agent ran `make gate-fast` (`ran-gate`
  passed), but every write from Bash failed with `Read-only file system`: the trace shows the working
  directory, `.git`, `.claude` and `$TMPDIR` mounted `ro`, and `scripts/gate.sh` itself could not write
  `.agents/last-run.log`. No `apply-seccomp` or `setgroups` error appeared. Outside the eval, a nested
  `bwrap` with a writable bind works on the same host, so the read-only mounts come from how the eval
  sets up the sandbox there. The likely cause is that the eval ran as root; the eval warns "the harness is
  running as root, which a directory mode does not bind". This is not confirmed.
- The owner stopped F1b here instead of running the eval as a non-root user, which would need that user
  to get the Claude Code login.

## v0.1 eval baseline (historical)

Run `claude plugin eval . --scaffold` from `plugins/keel-harness/` (each case runs 3 times per arm,
with-plugin vs. no-plugin baseline). `build-typescript` and `gate-catches-defect` additionally
need `--allow-tools Write Edit Bash` (they install/run real commands), plus `socat`, `gitleaks`
and `bwrap` on the host. Both scaffolds also run `npm install`, so they need network access when
they run.

- Date: 2026-09-21
- Claude Code version: 2.1.278

| Case | WITH | W-OUT | Δ | Verdict |
| --- | --- | --- | --- | --- |
| `assess-mature-repo` | 1.00 | 0.33 | +0.67 | pass |
| `should-not-trigger` | 1.00 | 1.00 | 0.00 | pass (correct result) |
| `build-typescript` | 0.57–1.00 | 0.43 | +0.14 to +0.57 | pass, confounded — see below |
| `gate-catches-defect` | 0.20 (single-arm, `--ablation none`) | n/a | n/a | environment-blocked — see below |
| `doctor-finds-drift` | 1.00 | 0.33 | +0.67 | pass |

`assess-mature-repo` and `doctor-finds-drift` were freshly re-run for this table (3/3 runs each
arm). `should-not-trigger`, `build-typescript` and `gate-catches-defect` carry over the numbers
from the same eval session (same date, same Claude Code version) without a fresh re-run — the
operator chose to skip re-confirming them rather than spend another live run on cases whose
behavior has no reason to have changed since the last commit touched them.

`doctor-finds-drift`'s Δ is driven by `names-the-drift`: an unmodified model asked "is the harness
up to date?" has no reason to independently notice or cite a 161-line `AGENTS.md` against a 100-line
convention it was never told about, so it fails that grader in the without arm every time (`writes-
nothing` passes in both arms, since the without arm has no tools to write with either).

`assess-mature-repo`'s Δ is driven by `rubric-axes` and `rubric-states`: the no-plugin baseline
never emits the six-axis table, so those two graders fail in the without arm while everything
scores in the with arm. `should-not-trigger`'s Δ = 0 is the correct result — the skill correctly
stays silent on an unrelated git question in both arms.

**`build-typescript`** ranged from a clean 1.00 (single `--ablation none` run, all 5 graders) to a
noisier 0.57 with/0.43 without (Δ +0.14) across a full 3-run with-without ablation. The spread comes
from this host's sandbox (see `gate-catches-defect` below): in the with-without run, one of three
"with" runs scored 0.00 because every `Bash` call failed and the agent ran out of turns before
finishing, while the other two runs recovered by falling back to the `Write` tool once `Bash` proved
unusable and still produced a correct `AGENTS.md` + `Makefile` + `.agents/state.yml`. The "without"
arm scores a non-trivial 0.43 because an unmodified model, told explicitly to "install everything...
and write the linecount," reasonably writes *some* `AGENTS.md` and `linecount.txt` on its own — it
never produces the `gate-fast` Makefile target or `.agents/state.yml`, which are what actually
differentiate the plugin. Net: Δ is real and positive on every run attempted, so the case clears the
existence floor, but the magnitude is measured under a host-level confound and is likely an
underestimate of the plugin's true effect.

**`gate-catches-defect`** could not complete a single valid `claude plugin eval` run on this host: all
four attempts (Step 4's required run, plus three retries to rule out flakiness) scored 0.20 with
`Bash called 1x` or `2x` but no `gate-output.txt` ever written. Reading the kept sandbox traces shows
why: every `Bash` tool call — even a bare `echo hello` — fails immediately with `apply-seccomp: write
/proc/self/setgroups (nested userns is capability-restricted; caller must provide CAP_SYS_ADMIN):
Permission denied`. This is nested-bubblewrap sandboxing: `claude plugin eval` runs the whole spawned
session inside its own OS sandbox, and Claude Code's own `Bash` tool (once granted) tries to sandbox
each command again inside that — a second, nested unprivileged user namespace, which this host's
AppArmor policy (`apparmor_restrict_unprivileged_userns=1` plus the `bwrap-userns-restrict` profile)
explicitly denies to bwrap's own children, by design. Reproduced directly with a raw
`bwrap … bwrap …` command outside Claude entirely — same denial, so this is a host/kernel-policy
limitation, not a `claude plugin eval` bug. The one documented escape hatch,
`sandbox.enableWeakerNestedSandbox: true`, was attempted once via `--settings` and was itself refused
by this session's own permission classifier as a security-weakening action; per that policy the
refusal was not worked around.

Per spec §8's existence floor, a case is rewritten or deleted when it shows **Δ ≤ 0 across three
consecutive runs** — i.e. when the plugin itself fails to add value. That is not what happened here:
`gate-catches-defect` never got a valid run to measure a Δ from at all, for a host-sandboxing reason
unrelated to the case's design or the plugin's behavior. The case and its fixture were instead
verified by hand, outside `claude plugin eval` (`bash scaffold.sh` in a scratch dir, then
`make gate-fast` directly): `scaffold.sh` already bakes the planted regression in, so running it once
only ever produces the regressed state directly — `make gate-fast` → `FAILED (1 of 4)`, exactly the
`tests` sensor failing with a `guidance:` block present and the other three sensors green. To see the
clean baseline, revert just the planted change (`git checkout src/posting.ts` — `build-typescript/
scaffold.sh` committed the original before this script's `sed` ran) and run `make gate-fast` again:
`PASSED (4 of 4)`. This is precisely the behavior the case's graders check for. The case is kept
as-is; re-run `claude plugin eval` for it on
a host without this nested-sandbox restriction (or with an operator explicitly opting into
`sandbox.enableWeakerNestedSandbox`) to get an official score.
