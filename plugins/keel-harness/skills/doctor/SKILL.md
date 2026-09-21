---
name: doctor
description: >
  Checks whether an installed harness has drifted from the repository it guards: AGENTS.md
  over 100 lines, commands cited there that no longer exist, sensors declared in the Makefile
  whose tool is missing or fails to run, and a model_baseline that has fallen behind. Reports
  and proposes; writes nothing. Use when someone asks whether their harness is out of date,
  stale or still valid, or wants a harness health check.
---

# Doctor

Reports and proposes, never writes.

`doctor` looks at an already-installed harness against the repository it guards, right now, with
no history. It runs exactly four checks — no more, no less — each a single look at the current
state, never a comparison across runs. It does not fix anything: every fix goes back through
`build`.

## The four checks

1. **AGENTS.md size.** Read `AGENTS.md` and count its lines. Over **100 lines** is drift — the
   index has stopped being an index and started accumulating prose that belongs in `docs/`.

2. **Stale commands.** Read every command cited in `AGENTS.md` (the Build & run block, the sensor
   table, the quality-gate blocks) and resolve each one against `package.json` scripts, `Makefile`
   targets, and `$PATH`, in that order. A command that resolves against none of the three **no
   longer exists** in the project — name the exact command and where in `AGENTS.md` it is cited.

3. **Missing or failing sensor tools.** For every sensor declared in the `Makefile`'s `gate-fast`
   target and listed under `sensors:` in `.agents/state.yml`, run its wrapper
   (`scripts/sensors/<id>.sh`) once. A wrapper whose underlying tool is **not installed**, or that
   exits 2 (skip), is a sensor the gate is not actually running — name the sensor id and what the
   wrapper itself reported is missing.

4. **Stale model_baseline.** Read `model_baseline` from `.agents/state.yml` and compare it against
   the model running this session. If the installed baseline is behind the running model by one
   version or more, the harness was tuned for an older model — name both versions.

## The output rule

**One broken condition produces exactly one warning** — not zero, not two. Each warning names the
file it concerns, exactly what is wrong, and the `build` step that fixes it (e.g. "re-run `build`'s
guides phase to regenerate `AGENTS.md`", "re-run `build`'s fast-gate phase to reinstall this
sensor"). A check that finds nothing stays silent: `doctor` never manufactures a warning to fill
space, and never splits one broken condition into two lines or folds two distinct problems into
one. If none of the four checks find anything, say so plainly — a clean harness is a valid answer.

`doctor` writes nothing; it proposes and stops. If the repository has no installed harness at all
(no `.agents/state.yml`), say so and point at `build` — that is a precondition, not one of the four
checks itself.

## Not in v0.1

How often each sensor's failures turn out to be real problems versus noise, and whether
`AGENTS.md`'s prose still matches the code it describes (not just whether its commands still
resolve) — both need runs accumulated over time, which a fresh look at the repository does not
have. They are v0.2 checks, once `.agents/last-run.log` holds enough history to say something.
`doctor` v0.1 looks once, not across time.
