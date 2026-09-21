# keel-harness

Assess, install and maintain an AI-agent harness in a repository. This plugin provides a one-command bootstrap, minimal guides, a fast gate of deterministic sensors, and an output contract that turns each sensor's exit code into guidance an agent can act on.

## Skills

### `/keel-harness:assess`

Diagnoses how ready a repository is for AI coding agents.

- **Reads:** Stack markers, real scripts, configured sensors, `docs/`, directory structure
- **Writes:** Nothing

### `/keel-harness:build`

Installs an AI-agent harness in a repository.

- **Reads:** Repository structure, user confirmations
- **Writes:** `AGENTS.md`, pointer docs, `docs/` stubs, `Makefile`, `scripts/sensors/`, `.agents/state.yml`, gate hook

### `/keel-harness:doctor`

Checks whether an installed harness has drifted from the repository it guards.

- **Reads:** `.agents/state.yml` and current project state
- **Writes:** Nothing

## v0.1 Rule

**Informs, does not block.** The gate runs, reports failures and returns guidance. No action is barred, no commit is refused.

## Eval baseline

Run `claude plugin eval . --scaffold` from `plugins/keel-harness/` (each case runs 3 times per arm,
with-plugin vs. no-plugin baseline). `build-typescript` and `gate-catches-defect` additionally
need `--allow-tools Write Edit Bash` (they install/run real commands), plus `socat`, `gitleaks`
and `bwrap` on the host.

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
`make gate-fast` directly): the harness fixture gates cleanly (`PASSED (4 of 4)`) before the planted
regression, and after `sed -i 's/cents \* 0.98/cents * 0.965/' src/posting.ts`, exactly the `tests`
sensor fails with a `guidance:` block present and the other three sensors stay green — precisely the
behavior the case's graders check for. The case is kept as-is; re-run `claude plugin eval` for it on
a host without this nested-sandbox restriction (or with an operator explicitly opting into
`sandbox.enableWeakerNestedSandbox`) to get an official score.
