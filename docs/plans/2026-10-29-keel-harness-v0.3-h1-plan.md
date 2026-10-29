# keel-harness v0.3 — H1 Temp-dir hardening: Implementation Plan

> **For agentic workers:** read `docs/plans/2026-10-29-keel-harness-v0.3-agent-rules.md` first. Phase id: `h1`. Free; no eval.

**Goal:** No installed script may write outside the repository or give a wrong verdict when `mktemp` fails. Found while validating E2 (master plan, "Validated 2026-10-29"):
- 16 places call `mktemp` without checking the result. With no usable `TMPDIR` (as in the eval sandbox), `tmp` is empty;
- `"$tmp/sizes"` then becomes `/sizes`. As root, the scripts write at the filesystem root; otherwise the writes fail and checks are silently lost;
- `guard` then fails on every run with a malformed summary (` loosening(s)` with no count).

**Reproduction** (before the fix), in a repository with an installed harness:

```bash
TMPDIR=/nonexistent-keel bash scripts/harness-check.sh   # prints "mktemp: failed …", writes /sizes, /stale as root
TMPDIR=/nonexistent-keel KEEL_GUARD_BASE=HEAD bash scripts/sensors/guard.sh   # "fail	 loosening(s) …" with no change at all
```

## The rule

Every script that needs a temporary file or directory uses this order:
1. `mktemp` in `TMPDIR` (the default);
2. else a fresh directory under `.agents/run/tmp/`, relative to the repository root where the script runs. That path is git-ignored since F2b, and excluded from `SCOPE`;
3. else stop with a clear verdict:

| Script | Verdict when no temp dir can be made |
| --- | --- |
| a sensor, except `guard` | exit 2 (skip), summary `no writable temp directory (TMPDIR or .agents/run/tmp/)` |
| `guard` (class `security`) | exit 1 (fail), the same summary, and `  guidance: make TMPDIR writable or let the gate create .agents/run/tmp/; never delete this sensor` |
| `harness-check.sh` | print `harness-check: no writable temp directory (TMPDIR or .agents/run/tmp/)` on stderr, exit **3**, and document exit 3 in its header |
| `scripts/measure.sh` (runs from the plugin) | message on stderr, exit 1 |

The existing `trap 'rm -rf "$tmp"' EXIT` (or `rm -f`) stays and also removes a fallback directory. A file temp (`since="$(mktemp)"`, `empty="$(mktemp)"`) follows the same order, with `mktemp .agents/run/tmp/XXXXXX` in place of `mktemp -d …`.

Implement it inline in each file as a small function. Do not add a new installed library: repositories installed by v0.2 and F2b must keep working with only the updated sensor file copied in. Example shape (adapt the failure branch per the table):

```bash
# A temp dir: TMPDIR, else .agents/run/tmp/ (git-ignored), else none.
keel_tmpdir() { mktemp -d 2>/dev/null || { mkdir -p .agents/run/tmp 2>/dev/null && mktemp -d .agents/run/tmp/XXXXXX 2>/dev/null; }; }
tmp="$(keel_tmpdir)" || tmp=""
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "no writable temp directory (TMPDIR or .agents/run/tmp/)"
  exit 2
fi
trap 'rm -rf "$tmp"' EXIT
```

`mktemp -d <template>` and `mktemp <template>` with a relative path behave the same on GNU and BSD/macOS. Keep that form.

## Files (all 16 call sites; `grep -rn mktemp plugins/keel-harness/assets plugins/keel-harness/scripts` must list only the new pattern afterwards)

- `assets/core/harness-check.sh`
- `assets/core/lib/baseline.sh` (`baseline_compare`: on failure return 2 and let the calling sensor report skip; check every caller handles 2)
- `assets/core/sensors/common/guard.sh`
- `assets/core/sensors/jvm/lint.sh`, `jvm/tests.sh`
- `assets/core/sensors/python/lint.sh`, `assets/core/sensors/typescript/lint.sh`
- `assets/core/sensors/rules/architecture.sh`, `architecture-grep.sh`, `code-language.sh`, `file-size.sh`, `folder-layout.sh`, `test-presence.sh`
- `assets/core/sensors/rules/slow/diff-coverage.sh`, `slow/mutation.sh`
- `scripts/measure.sh`

## Tasks

- [ ] **Task 1 — test first.** Add `tests/keel_tmpdir_test.sh`. For each script above, in a repository built with the existing helpers (copy the setup style of `tests/keel_rule_sensors_test.sh`, `tests/keel_guard_test.sh` and `tests/keel_harness_check_test.sh`), run three cases:
  1. **Fallback:** `TMPDIR=/nonexistent-keel-$$`.
     - No `mktemp: failed` on stderr.
     - The verdict equals the verdict with a normal `TMPDIR`: same exit code, same line-1 status and summary.
     - `.agents/run/tmp/` holds no leftover directory afterwards.
     - Cover at least: `guard` with no change passes; `guard` with a grown baseline fails with the count `1 loosening(s)`; `harness-check` still reports `agents-size` for a 130-line `AGENTS.md`; `file-size` still fails an oversize file.
  2. **No temp dir at all:** `TMPDIR=/nonexistent-keel-$$` and `.agents/run` made a regular file, so `mkdir` fails. The verdicts follow the table (sensors skip, `guard` fails with the summary, `harness-check` exits 3, `measure.sh` exits 1).
  3. **Nothing at the root:** a structural check that no script can expand `"$tmp/…"` with an empty `tmp`. Every `tmp=`/`since=`/`empty=` assignment from `mktemp` is followed by the emptiness check, enforced with `grep`/`awk` over the files.

  Run it on the old code and keep the failure count for the report. Do not commit a red suite: commit Task 1 together with Task 2.
- [ ] **Task 2 — the fix** in all 16 call sites, per the rule above. Update each sensor's header comment only if it lists exit codes. Run `shellcheck -S warning` on every changed file. Commit `fix(keel-harness): fall back to .agents/run/tmp when mktemp fails; never write at the filesystem root` with both tasks.
- [ ] **Task 3 — docs.**
  - `skills/build/references/sensor-contract.md`: one sentence on the temp-dir rule.
  - `assets/core/README.agents.md`: `.agents/run/tmp/` in the run-state row.
  - Do **not** edit any SKILL.md: F2c-1 runs in parallel and rewrites `assess` and removes `doctor`. The owner carries "exit 3" into `assess` at merge.
  - Master plan: tick H1 in the status table, with the evidence.
  - Commit `docs(keel-harness): temp-dir rule (H1)`.

## Acceptance

- The two reproduction commands no longer print `mktemp: failed`, write nothing outside the repository, and give the same verdict as with a working `TMPDIR`.
- `tests/keel_tmpdir_test.sh` is green and was red on the old code.
- `./tests/run.sh` exits 0 with no FAIL; `validate --strict` passes; `shellcheck` is clean at warning level.
- No new installed file; no change to the sensor line-1 contract.
