# Sensor contract — the seven fields, the classes, and the wrapper protocol

A **sensor** is a computational check the agent can run itself and read the answer of without a
human. Every sensor this kit installs is a small shell wrapper in `scripts/sensors/<id>.sh` that
runs a tool the repository already has and translates its output into one fixed shape. The shape is
what makes the gate legible to an agent: same first line, same exit codes, same place to look for
what to do next, whatever the language or the tool underneath.

Read this file before writing any wrapper. The stdout format below is a contract, not a suggestion —
`scripts/gate.sh`, the eval graders, and `doctor` all parse it.

---

## 1. The seven fields

Five come from the study; two are this kit's own, and their absence had a concrete consequence — the
ratchet and the raisable threshold would otherwise have applied to a leaked credential too.

| # | Field | What it means | Where it lives |
| --- | --- | --- | --- |
| 1 | **pass signal** | The exact, literal output that means "clean". An agent must never have to judge whether output *looks* good. | the wrapper's `status` field (`pass`) and its one-line summary |
| 2 | **guidance** | On failure, what to do next **in the repository's own terms** — which file, which decision, what action. Never a restatement of the tool's error. | the `guidance: ` block on `fail` |
| 3 | **scope** | What the sensor looked at: the changed files (`SCOPE`) or the whole repository. A sensor whose tool has no file-level mode says so. | the `SCOPE` env var in, the summary line out |
| 4 | **cost** | Wall time, measured, in milliseconds. The **money** cost of the fast gate is **US$0.00**: no v0.1 sensor calls a language model. | measured by `gate.sh`, reported per sensor |
| 5 | **bounded verbosity** | The wrapper prints a handful of detail lines, not the tool's full spew. `gate.sh` truncates stdout at 40 lines and writes the untruncated run to `.agents/last-run.log`. | detail lines, capped inside the wrapper |
| 6 | **class** | `security`, `correctness` or `heuristic` — see §2. Decides whether the sensor may ratchet. | the wrapper's `class` field |
| 7 | **ceiling** | The fast gate declares a limit in seconds (`gate.fast.ceiling_seconds` in `.agents/state.yml`, default 5). A sensor that alone blows it is **not installed**, and the kit says which one and why. | `.agents/state.yml`, enforced at install time |

## 2. The three classes

| Class | v0.1 sensors | Ratchet? | Raisable threshold? |
| --- | --- | --- | --- |
| **security** | secret scanning | **never** | **never** |
| **correctness** | types, affected tests | **never** | **never** |
| **heuristic** | style, size, complexity | yes | yes |

A `security` or `correctness` sensor fails on the first problem, full stop. It is **never** given a
snapshot to compare against, and its threshold is **never** raised to make a run go green — "we only
have three leaked keys, same as yesterday" is not a passing state. Only a `heuristic` sensor gets
the "don't get worse" comparison and a threshold that may be moved.

**The ratchet is a comparison, not a label.** A `heuristic` wrapper's `status` must come from
comparing the tool's current count against the snapshot in `.agents/state.yml` — `pass` when
`current <= snapshot`, `fail` only when it rose — never from the tool's raw exit code. A linter
exits non-zero whenever it finds *any* problem, snapshot or not; a wrapper that reports `fail`
whenever the exit code is non-zero, without reading and comparing the snapshot, has implemented no
ratchet at all — it behaves exactly like a `correctness` sensor while its `guidance:` text keeps
claiming "this only fails when it gets worse," which is now false. §6 below is the worked example
of the comparison this requires; skipping it is as much a contract break as mislabelling the class.

### The ratchet expiry

Every **heuristic** sensor records, at install time, its install-day snapshot **and a `review_by`
date six months out**:

```yaml
sensors:
  - id: lint
    class: heuristic
    snapshot: { problems: 34, measured_at: 2026-09-19 }
    review_by: 2027-03-19
  - id: secrets
    class: security          # no snapshot, no review_by: security has no ratchet
  - id: typecheck
    class: correctness       # no snapshot, no review_by: correctness has no ratchet
```

Without the expiry, "don't get worse" freezes a bad state forever and the ratchet stops being a
ratchet. `doctor` reads `review_by`; past that date the snapshot is stale and is meant to be
re-measured downward, never upward to accommodate drift.

---

## 3. The wrapper protocol

Every `scripts/sensors/<id>.sh` written into a user repository:

- reads the environment variable **`SCOPE`**, a newline-separated list of changed files (**empty
  means the whole repo**);
- writes **line 1** to stdout as four tab-separated fields:
  `<id>\t<class>\t<status>\t<summary>`, where `class` is `security|correctness|heuristic` and
  `status` is `pass|fail|skip`;
- writes detail lines **indented by two spaces**, and on `fail` a block starting `guidance: `
  saying what to do, in the user's repository terms;
- exits **`0` on pass, `1` on fail, `2` on skip** (the tool is not installed — **never** a silent
  pass).

Rules that follow from it, and that the wrapper must honour:

- **The line-1 `printf` is copied verbatim, field order and all:**
  `printf '%s\t%s\t%s\t%s\n' "$id" "$class" "$status" "$summary"` — **`id` first, then `class`,
  then `status`, then `summary`.** `gate.sh`, the eval graders and `doctor` all `cut -f1`/`-f2`/
  `-f3`/`-f4` in that exact order; reordering the fields (e.g. leading with `status`) or swapping
  in the elapsed time as the fourth field instead of the summary is not a stylistic variant, it is
  a contract break that silently corrupts every downstream reader. **Do not re-derive this line
  from memory — copy the `printf` from §4–§6 character for character** and change only the values
  bound to `id`, `class`, `status` and `summary`. Cost is measured by `gate.sh` from the outside
  (wall time around the wrapper's own execution); a wrapper does **not** print its own elapsed time
  on line 1.
- **The wrapper reads and honours `$SCOPE` — it does not hardcode a scope string.** When the
  underlying tool has a file-level mode (`vitest related --run $SCOPE`, `eslint $SCOPE`), pass the
  files from `$SCOPE` to it; only fall back to the whole repo when `$SCOPE` is empty or the tool has
  no such mode (say so, as `tsc` does in §4). Printing a fixed `scope: src` regardless of what
  changed is a second, quieter way the same contract gets violated.
- **`<id>` matches the filename** and the `id:` recorded in `.agents/state.yml`.
- **The summary is one line** and states the pass signal in the tool's own numbers ("Found 0 errors
  in 12 files"), not an adjective ("looks fine").
- **A missing tool is a `skip`, never a pass.** Exit 2, and say in the summary what is missing and
  how to get it (usually `make bootstrap`).
- **`guidance:` appears only on `fail`,** and never paraphrases the error. The error says *what*
  broke; guidance says *what is done about it here*.
- **A wrapper never `cd`s.** `gate.sh` invokes every sensor from the repository root, so every
  path in a wrapper is relative to the root. Run one by hand the same way: from the root, as
  `bash scripts/sensors/<id>.sh`.
- **Never `set -e` past the tool call** — the wrapper must survive a non-zero tool exit and
  translate it, not die of it.
- **No network, no model call.** The money cost of the fast gate is zero.
- **No plugin paths.** See §8, portability.

A wrapper whose line 1 reads `fail\ttypecheck\tcorrectness\t1.06s` (status leading, cost trailing)
is the exact failure this section exists to prevent — it has four tab-separated fields, so a
careless glance calls it compliant, but `cut -f3` now returns `correctness` where every downstream
reader expects `status`. **Check field order explicitly, not just field count.**

---

## 4. Worked example — a passing sensor

`scripts/sensors/typecheck.sh`:

```bash
#!/usr/bin/env bash
# typecheck — correctness. Wrapper protocol: see the kit's sensor contract.
# In:  SCOPE (newline-separated changed files; empty = whole repo).
# Out: line 1 = id<TAB>class<TAB>status<TAB>summary. Exit 0 pass / 1 fail / 2 skip.
set -uo pipefail
id=typecheck
class=correctness

tsc="node_modules/.bin/tsc"
if [ ! -x "$tsc" ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "tsc is not installed - run: make bootstrap"
  exit 2
fi

# tsc has no per-file mode under a project config: this sensor is whole-repo by nature.
out="$("$tsc" --noEmit -p tsconfig.json 2>&1)"; rc=$?
files=$(git ls-files '*.ts' '*.tsx' | wc -l | tr -d ' ')

if [ "$rc" -eq 0 ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "Found 0 errors in $files files."
  exit 0
fi

n=$(printf '%s\n' "$out" | grep -cE 'error TS')
printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "Found $n type error(s) in $files files."
printf '%s\n' "$out" | grep -E 'error TS' | head -5 | sed 's/^/  /'
printf '  guidance: fix the FIRST error listed above and re-run; the ones below it are usually\n'
printf '  its cascade. If the type is genuinely unknowable at that point, model the absence\n'
printf '  (undefined, a union, a narrowing check) rather than widening it to `any` - `any` makes\n'
printf '  this sensor blind to every future change in that file.\n'
exit 1
```

A passing run. Line 1 is what `gate.sh` parses; the exit code is what it trusts:

```
$ SCOPE="src/posting.ts" bash scripts/sensors/typecheck.sh; echo "exit=$?"
typecheck	correctness	pass	Found 0 errors in 12 files.
exit=0
```

## 5. Worked example — a failing sensor

`scripts/sensors/tests.sh` carries the heaviest guidance, because a test failing after an edit is
the most common and most misread signal in the gate — and the one place an agent is most tempted to
"fix" the test instead of the code:

```bash
#!/usr/bin/env bash
# tests — correctness. Runs the tests related to the changed files.
set -uo pipefail
id=tests
class=correctness

vitest="node_modules/.bin/vitest"
if [ ! -x "$vitest" ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "vitest is not installed - run: make bootstrap"
  exit 2
fi

changed=$(printf '%s\n' "${SCOPE:-}" | sed '/^$/d' | grep -E '\.(ts|tsx|js|jsx)$')
if [ -n "$changed" ]; then
  # shellcheck disable=SC2086
  out="$("$vitest" related --run $changed 2>&1)"; rc=$?
else
  out="$("$vitest" run 2>&1)"; rc=$?
fi

line=$(printf '%s\n' "$out" | grep -E '^ *Tests +' | tail -1 | sed 's/^ *//')
[ -n "$line" ] || line="no related test found for the changed files"

if [ "$rc" -eq 0 ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "$line"
  exit 0
fi

printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "$line"
printf '%s\n' "$out" | grep -E 'FAIL|AssertionError|expected' | head -6 | sed 's/^/  /'
printf '  guidance: a test that passed before now fails, so behaviour changed. Read the failing\n'
printf '  assertion above (expected vs received), then look at what changed in the source file it\n'
printf '  exercises - `git diff` shows it. If that behaviour change was NOT intended, revert it in\n'
printf '  the source; do not edit the test to match the new number. If it WAS intended, update the\n'
printf '  test and record the decision in docs/decisions/ as a new ADR - never edit an accepted one.\n'
exit 1
```

A failing run:

```
$ SCOPE="src/posting.ts" bash scripts/sensors/tests.sh; echo "exit=$?"
tests	correctness	fail	Tests  1 failed (1)
  FAIL  src/posting.test.ts > applies the fee
  AssertionError: expected 1181 to be 1200 // Object.is equality
  guidance: a test that passed before now fails, so behaviour changed. Read the failing
  assertion above (expected vs received), then look at what changed in the source file it
  exercises - `git diff` shows it. If that behaviour change was NOT intended, revert it in
  the source; do not edit the test to match the new number. If it WAS intended, update the
  test and record the decision in docs/decisions/ as a new ADR - never edit an accepted one.
exit=1
```

## 6. Worked example — a heuristic with a ratchet

A `heuristic` sensor compares against the snapshot in `.agents/state.yml` and fails only when the
count **rose**:

```bash
#!/usr/bin/env bash
# lint — heuristic, ratcheted against the install-day snapshot.
set -uo pipefail
id=lint
class=heuristic

eslint="node_modules/.bin/eslint"
if [ ! -x "$eslint" ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "eslint is not installed - run: make bootstrap"
  exit 2
fi

out="$("$eslint" src 2>&1)"
now=$(printf '%s\n' "$out" | grep -cE '^ +[0-9]+:[0-9]+ +(error|warning)')
snap=$(sed -n 's/.*problems: *\([0-9][0-9]*\).*/\1/p' .agents/state.yml | head -1)
: "${snap:=$now}"

if [ "$now" -le "$snap" ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "$now problems. same as snapshot ($snap)."
  exit 0
fi
printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "$now problems, up from snapshot ($snap)."
printf '%s\n' "$out" | grep -E '^ +[0-9]+:[0-9]+' | head -5 | sed 's/^/  /'
printf '  guidance: this gate only forbids getting worse. Clear the new problems listed above in\n'
printf '  the files you just touched - the %s pre-existing ones are not yours to fix now. Do not\n' "$snap"
printf '  raise the snapshot in .agents/state.yml to make this pass; that single edit is what turns\n'
printf '  the ratchet off.\n'
exit 1
```

Note what is *not* here: no `snapshot` for `typecheck` and none for a secret scanner, because
neither is a heuristic. Copying this ratchet into a `security` sensor is the exact mistake the class
column exists to prevent.

---

## 7. `scripts/gate.sh` — the runner

**Copy the script below byte-for-byte into `scripts/gate.sh`.** Do not re-derive its field parsing,
per-sensor timing, truncation or report rendering from memory or from a simpler idea of what a
runner "should" do — a hand-rolled runner that skips the `cut -f` parsing, the millisecond timing,
the 40-line truncation or the `✓/✗/○` report is a contract violation even on a run where it happens
to work, because it is what Task 6's graders and `doctor` will fail to parse next. The only parts of
this file that legitimately vary by repository are already parameters it reads (`$state`, the
sensor ids) — not the shape of its own output.

One file, written once per repository. It runs every sensor listed in `.agents/state.yml`, times
each in milliseconds, renders the report, truncates stdout at 40 lines, writes the full output to
`.agents/last-run.log`, and exits non-zero if any sensor failed.

```bash
#!/usr/bin/env bash
# gate.sh — runs the fast gate. Invoked by `make gate-fast`.
# Reads the sensor list from .agents/state.yml. No plugin, no network, no model.
set -uo pipefail
cd "$(dirname "$0")/.."
state=".agents/state.yml"
log=".agents/last-run.log"
mkdir -p .agents

# Millisecond clock, portable: `date +%s%N` is GNU-only and silently breaks this
# arithmetic on macOS/BSD `date` (no %N). Bash 5+ gets microsecond precision from
# the builtin $EPOCHREALTIME, no external tool and no GNU dependency; anything
# older (e.g. the bash 3.2 macOS ships by default) falls back to whole seconds via
# $SECONDS, which every bash has had since 2.0. $EPOCHREALTIME's own decimal
# separator follows LC_NUMERIC on at least some bash builds (comma, not period,
# under e.g. a pt_BR locale) - normalise it before splitting, or the arithmetic
# below silently mis-measures instead of erroring.
now_ms() {
  if [ -n "${EPOCHREALTIME:-}" ]; then
    local t="${EPOCHREALTIME/,/.}"
    local sec="${t%.*}" usec="${t#*.}"
    echo $(( sec * 1000 + 10#${usec:0:3} ))
  else
    echo $(( SECONDS * 1000 ))
  fi
}

# Unicode marks only where the terminal can actually render them; plain ASCII
# everywhere else (piped/redirected output, a non-UTF-8 locale, `TERM=dumb`). This
# is the real implementation of the terminal-conditional described below the
# rendered example — not just prose next to a script that always emits one or the
# other. Agents read line 1 and the exit code; these marks are for a human only.
if [ -t 1 ] && locale charmap 2>/dev/null | grep -qi 'utf-8'; then
  m_pass="✓"; m_fail="✗"; m_skip="○"
else
  m_pass="v"; m_fail="x"; m_skip="-"
fi

# SCOPE = files changed since the last commit (tracked + untracked). Empty = whole repo.
SCOPE="$( { git diff --name-only HEAD 2>/dev/null; \
            git ls-files --others --exclude-standard 2>/dev/null; } | sed '/^$/d' | sort -u )"
export SCOPE
n_scope=$(printf '%s' "$SCOPE" | grep -c . )

ceiling=$(sed -n 's/^ *ceiling_seconds: *\([0-9][0-9]*\).*/\1/p' "$state" 2>/dev/null | head -1)
: "${ceiling:=5}"
ids=$(sed -n 's/^ *- id: *\([A-Za-z0-9_-]*\).*/\1/p' "$state" 2>/dev/null)

report=""; total_ms=0; n=0; failed=0
for id in $ids; do
  s="scripts/sensors/$id.sh"
  [ -f "$s" ] || continue
  n=$((n + 1))
  start=$(now_ms)
  out="$(bash "$s" 2>&1)"; rc=$?
  ms=$(( $(now_ms) - start ))
  total_ms=$((total_ms + ms))

  head1=$(printf '%s\n' "$out" | head -1)
  body=$(printf '%s\n' "$out" | tail -n +2)
  cls=$(printf '%s' "$head1" | cut -f2)
  st=$(printf '%s' "$head1" | cut -f3)
  sum=$(printf '%s' "$head1" | cut -f4)

  case "$rc" in
    0) mark="$m_pass" ;;
    2) mark="$m_skip" ;;
    *) mark="$m_fail"; st=fail; failed=$((failed + 1)) ;;
  esac

  if [ "$ms" -ge 1000 ]; then t="$((ms / 1000)).$(( (ms % 1000) / 100 ))s"; else t="${ms}ms"; fi
  report="${report}$(printf '%s %-12s [%-11s] %-44s %8s' "$mark" "$id" "$cls" "$sum" "$t")
"
  [ -n "$body" ] && report="${report}${body}
"
done

if [ "$n_scope" -gt 0 ]; then scope_line="scope: $n_scope files changed since last commit"
else scope_line="scope: whole repository (no uncommitted changes)"; fi
if [ "$total_ms" -ge 1000 ]; then spent="$((total_ms / 1000)).$(( (total_ms % 1000) / 100 ))s"
else spent="${total_ms}ms"; fi
if [ "$failed" -gt 0 ]; then verdict="FAILED ($failed of $n)"; else verdict="PASSED ($n of $n)"; fi

{
  printf '%s' "$report"
  printf '\n%s\n' "$scope_line"
  printf 'gate: fast - %s | ceiling %ss, spent %s | model cost: US$0.00\n' "$verdict" "$ceiling" "$spent"
} > "$log"

lines=$(wc -l < "$log" | tr -d ' ')
head -40 "$log"
if [ "$lines" -gt 40 ]; then
  printf 'output truncated at 40 lines - full log in .agents/last-run.log\n'
else
  printf 'full log in .agents/last-run.log\n'
fi
[ "$failed" -gt 0 ] && exit 1
exit 0
```

And the `Makefile` target, added beside `bootstrap` without touching it:

```make
gate-fast:
	@bash scripts/gate.sh
```

The rendered report, in the shape the spec fixes — `✓ ✗ ○` where the terminal takes them, plain
`v x -` where it does not, exactly as `now_ms`'s neighbouring `if [ -t 1 ] && locale charmap ...`
block above implements it, not a variant a copier has to invent (the marks are for humans; agents
read line 1 and the exit code):

```
$ make gate-fast

✓ typecheck   [correctness]  Found 0 errors in 12 files.          312ms
✓ secrets     [security   ]  No leaks found in 12 changed files.  118ms
✓ lint        [heuristic  ]  0 problems. same as snapshot (34).   840ms
✗ tests       [correctness]  3 passed, 1 failed.                   2.1s
  src/posting.test.ts:41 - expected 1200, received 1180
  guidance: rounding changed in applyFee(). If the change was intentional, update the test
  and record a new ADR in docs/decisions/ - never edit an accepted ADR. If it was not, the
  bug is in the calculation.

scope: 12 files changed since last commit
gate: fast - FAILED (1 of 4) | ceiling 5s, spent 3.4s | model cost: US$0.00
full log in .agents/last-run.log
```

## 8. Portability

`scripts/gate.sh` and every wrapper are plain `bash` living in the user's repository. They must run
identically with this plugin absent, uninstalled and unknown — no `${CLAUDE_*}` variable, no path
into the plugin directory, no `claude` invocation, no `npx` that would reach the network. That is
the portability promise: the harness belongs to the repository, not to the kit. Verify it by running
`make gate-fast` in a shell that has never heard of the plugin.
