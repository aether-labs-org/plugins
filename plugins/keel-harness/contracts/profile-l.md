# Profile L components — the reviewer and journey sensors, and the autonomous-run recipe

Profile L is an agent that works for hours, over several sessions, and owns the whole job (spec 2.1).
Three components serve it: **C3** an inferential reviewer sensor, **C8** a journey sensor with
structured-log guidance, **C10** an orchestration recipe. All three are **experimental and unproven
(D52)**: each ships in v0.3 only if a with/without measurement shows a gain (Δ > 0), and phase R decides
what ships. Both sensors are opt-in, live in `scripts/sensors/slow/`, and are never run by the Stop hook
or the fast gate.

## 1. Their env files are rule env files

`harness-check` reads every `.agents/rules/*.env` as a rule (`rule-env.md`). `reviewer.env` and
`journey.env` therefore carry the rule metadata too, and the docs section they point at is anchored:

```sh
RULE_ID=reviewer
KIND=convention
ORIGIN=user
APPROVED_AT=2026-10-29
ENFORCEMENT=sensor:reviewer
DOC=docs/conventions.md#reviewer
REVIEWER_CMD=claude -p --model <a model other than the one that codes>
MAX_DIFF_LINES=800
TIMEOUT_SECONDS=120
```

- The section `docs/conventions.md#reviewer` (`<a id="reviewer"></a>`) says what the reviewer does and
  **states the `MAX_DIFF_LINES` number** (for example "a diff over 800 lines is skipped"): `harness-check`
  warns `rule-inconsistent` when a numeric key (`*MAX*`, `*LIMIT*`, `*MIN*`) does not appear in its section.
- `guard` reads `MAX_DIFF_LINES` as a `*MAX*` key: raising it asks for an ADR in the same change even
  though a larger budget reviews more. That is the existing rule for such keys, not a reviewer feature.
- Nothing in an env file is executed (`envparse.sh`): a value with `$(` or a backtick fails the sensor.

## 2. `reviewer` (C3) — `assets/core/sensors/slow/reviewer.sh`, class `heuristic`

| Key | Meaning | Default |
| --- | --- | --- |
| `REVIEWER_CMD` | The command that reviews. Split on whitespace, **no shell**: no quotes, pipes or `$VAR`. It reads the prompt on stdin and prints the verdict. For anything more, point it at a wrapper script in the repository. Use a model other than the one that wrote the change. | none: the sensor skips |
| `MAX_DIFF_LINES` | Skip when the diff is longer. | 800 |
| `TIMEOUT_SECONDS` | Stop the command and skip after this long. | 120 |

- **Input.** One prompt on stdin: a short brief, the output format, `AGENTS.md`, each docs section
  `AGENTS.md` cites (`→ docs/<topic>.md#<anchor>`), then the diff since the base. The base is
  `KEEL_GUARD_BASE`, else the merge-base with `origin/HEAD`, else `HEAD` (as `guard`), and untracked files
  count. **The diff and the rules leave the machine** by way of `REVIEWER_CMD`; do not enable it on a
  repository whose code may not be sent to that model.
- **Output.** `PASS`, or one `FAIL: <file>: <rule and why>` line per violation. Any `FAIL` line fails the
  sensor (`status fail`, exit 1, at most 5 reasons printed, then `guidance:`). A reply with no such line,
  an empty reply, a non-zero exit, a timeout, a missing command or a diff over the budget is a `skip`
  (exit 2) with the reason on line 1. **Never a pass.**
- **Cost.** One model call per `make gate-slow`, billed to the user. The slow gate's verdict line then
  reads `model cost: reviewer sensor ran ...` instead of `US$0.00`.
- **A model can be wrong.** The guidance says: read each reason against the rule it cites, fix the code
  if it is right, say why in the pull request if it is wrong, and do not edit the rules, `reviewer.env`
  or the sensor to make it pass.
- **Calibration.** `tests/fixtures/keel/reviewer/` (in the plugin repository, not installed) holds a diff
  that violates a rule and one that does not, and a stub `REVIEWER_CMD`. The tests use only the stub. To
  calibrate a real model, run both diffs through it and expect `FAIL` then `PASS`.

## 3. `journey` (C8) — `assets/core/sensors/slow/journey.sh`, class `correctness`

Runs the project's Playwright journeys (user-visible flows, end to end).

| Key | Meaning | Default |
| --- | --- | --- |
| `JOURNEY_DIR` | Where the journeys live; passed to `npx playwright test`. | `e2e` |
| `JOURNEY_RESULTS` | Where Playwright keeps traces. | `test-results` |

- **Runs** `npx playwright test <JOURNEY_DIR> --reporter=line --trace=retain-on-failure` and reduces the
  line reporter to the sensor contract. Playwright has no file-level mode, so `SCOPE` is not used.
- **Skips** when `npx` is missing, `node_modules/.bin/playwright` is missing, `JOURNEY_DIR` does not exist,
  or Playwright reports `No tests found`.
- **Fails** with `<n> of <total> journey(s) failed`, up to 3 `journey:` lines (the failing test's name) and
  up to 2 `trace:` lines (`trace.zip` under `JOURNEY_RESULTS`), then guidance with the
  `npx playwright show-trace <trace>` command and the wrong fix (editing the journey or its assertions).
  A crash before any result is also a fail, with the last lines of output.
- No model call, no network call of its own (the journeys may use the network the app uses).

## 4. The recipe (C10) is documentation only

`README.agents.md` (short) and the plugin README (full) describe it. keel orchestrates nothing (D47).
