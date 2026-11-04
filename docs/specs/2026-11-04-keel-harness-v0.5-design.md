# keel-harness v0.5 — consolidated design (Design Spec)

**Date:** 2026-11-04
**Status:** approved by the owner on 2026-11-04. Decided in the audit rounds of 2026-11-04 (rounds 1–4 and the
boundary refinement).
**Supersedes:** every earlier keel-harness spec and plan — `docs/specs/2026-09-19-keel-harness-design.md`,
`2026-10-20-keel-harness-v0.2-design.md`, `2026-10-23-keel-harness-v0.3-design.md`,
`2026-10-24-keel-cli-design.md`, `2026-11-03-keel-cli-v0.4-design.md` and the 27 `docs/plans/*keel*`
files. They are deleted when this spec lands in `docs/specs/`; git history keeps them. Nothing here owes
them compatibility; where an earlier decision survives, it is restated here.
**Base:** the v0.4 `kh` design. Its M0 (`kh run`, `kh show`, `kh version`, evidence, redaction,
reduction, tree fingerprint) is implemented at `d3c16a6` [fact].
**Audit:** "Auditoria técnica — keel-harness (base para a v0.5.0)", 2026-11-04 (claude.ai artifact
`CZsYC6yVfhCESkYNsvcx7B`). Finding ids `P-n` and recommendation ids `Rn.n` below refer to it.

Legend: **[fact]** verified in code, docs or a run; **[owner]** decided by the owner; **[builder]** a
revisable call made while writing, pinned later by a test.

---

## 1. Why

The audit found no coherent, distributable version: the plugin on `main` installs the bash engine that
v0.4 declared obsolete, and `kh` cannot run a gate yet. Beyond that:

- an agent can rewrite `scripts/sensors/guard.sh` through the shell and keep the gate green (P-1);
- `keel approve` is run by the agent itself, so "approval" proves nothing (P-2);
- the installed harness needs the plugin for three operations: `plan-close`, config regeneration and
  protect-hook approval (P-3), and cites `/keel-harness:*` in 20+ messages (P-4);
- multi-agent support exists in name only: one adapter (Claude Code), untested elsewhere (P-5, P-6);
- the owner's checklist has absent areas (Git cycle, contract/property/performance tests, SCA/SAST);
- the same contracts are written in four places, already drifting (P-9 to P-11);
- 74 decisions and ~540 KB of specs for ~8 k lines of product.

v0.5 is meant to be **the definitive, distributable version**. There are no users, so justified breaking
changes are welcome [owner].

## 2. Goals, non-goals, anti-goals

**Goals**
- **G1** A harness that lives in the repository and works **without the plugin** in Claude Code, GitHub
  Copilot CLI and Devin CLI, latest versions [owner].
- **G2** One deterministic engine, `kh`, pinned per repository.
- **G3** A plugin that only **authors**: one skill that diagnoses, discovers, asks in rounds and writes
  only what the human confirms, file by file [owner].
- **G4** Every item of the owner's checklist (quality, standards, memory, Git) is either covered or
  declared out of scope with a reason (§15).
- **G5** The agent never changes the harness alone; it may guide the human to change it [owner].
- **G6** One source for each contract and one implementation for each metric.

**Non-goals**
- CI: keel generates no CI workflow. A team may wire `kh gate` into its own CI; unsupported [owner].
- Headless (`claude -p`) setup [owner].
- Codex or any agent beyond the three [owner]. Catalog stacks beyond TypeScript/JS, Python and JVM
  (Go stays out) [owner]. Windows outside WSL.
- Proving effect with with/without evals in v0.5 [owner]; the risk is declared in §17.
- Migration from v0.1–v0.3 installations [owner].
- Replacing task runners, sandboxing, toolchain management (mise/asdf), capability discovery by `kh`.

**Anti-goals** — the work fails even if it "works" when:
- a verdict comes from a model, or a non-zero exit is read as a pass;
- a missing tool, a timeout or a broken config reads as a pass;
- the agent loosens the harness (`keel.yml`, baselines, hooks, guides, ADRs) and the gate stays green
  without the human having confirmed the write;
- a script calls a model: inferential flows live only in skills and guides [owner];
- an operation the project needs exists only in the plugin;
- the same metric or validation is implemented twice;
- local execution state is committed (evidence, gate history, raw lessons, handoff notes);
- two repositories on one machine affect each other's `kh` version, state or hooks.

## 3. Architecture

### 3.1 Four planes

| Plane | Where | Contents | Who writes |
| --- | --- | --- | --- |
| **Contract and memory** | Repository, versioned | `AGENTS.md`, `CLAUDE.md`, rule topic files, `docs/review.md`, ADRs, `.agents/keel.yml`, baselines, active plans, task history, triaged lessons | The human confirms every write to a protected file; the agent writes plans and history (§10) |
| **Execution** | Repository, pinned | `.agents/bin/kh` (wrapper) + `.agents/keel.lock` → the `kh` binary in a per-user, per-version cache | keel's release process |
| **Adaptation** | Repository, versioned | `.claude/settings.json` hooks (read by all three agents, §9.1), reviewer agent definitions, git hooks | Written at setup with confirmation; protected afterwards |
| **Authoring** | Plugin, optional | One skill, references, catalog, templates, read-only scripts | keel; nothing of it runs at gate time |

### 3.2 Boundary rules [owner, 2026-11-04]

- **B1** If the project needs it while the plugin is absent, it is in `kh`.
- **B2** One implementation per metric or validation. When the plugin needs a number a gate also
  computes, it calls `kh` instead of re-implementing it.
- **B3** Plugin scripts only read and print. Every write into the repository is made by the agent through
  Write/Edit and confirmed by the human. (A script that wrote a protected file through the shell would be
  denied by the protection, by design.)
- **B4** Deterministic → code (`kh` or a plugin script). Inferential → skill or guide. No script ever
  calls a model.
- **B5** `keel.yml` holds only what `kh` reads; prose holds only what a person or agent reads; a value
  lives in exactly one of them.

### 3.3 Responsibilities

| Component | Owns | Does not own |
| --- | --- | --- |
| **`kh`** | Running scripts and gates; capture, timeout, retries; parsing by format; verdict; baselines (measure, compare); builtins incl. `guard`; evidence and redaction; `kh check`; agent and git hook logic; per-clone `kh setup`; `kh schema` | Judgment, proposals, talking to the user, writing guides, memory or baselines, installing itself into a repository |
| **Plugin skill** | Diagnosis, discovery, rounds, proposals with evidence and sources, templates, explaining `kh check` output, proposing a pin upgrade | Anything at gate time; committing |
| **Agent runtime** | Calling `kh hook …` through `.claude/settings.json` and relaying the answer; its own permission prompts and sandbox | Any verdict logic |
| **Git hooks** | Running `kh gate commit` (pre-commit), `kh hook commit-msg` (if adopted), `kh gate slow` (pre-push) for humans and agents alike | — |

## 4. End-to-end flows

### 4.1 Setup: create, review or update (Claude Code with the plugin)

1. The user asks for help to create, review or update the harness; the skill triggers (or
   `/keel-harness:harness`).
2. The skill's frontmatter hook is registered for the rest of the session [fact: Claude Code registers
   skill hooks when the skill is invoked and keeps them for the session]. It protects the harness paths
   before any repository hook exists (§9.4).
3. **Mode:** no `.agents/keel.yml` → create; present → review/update. Both start with the diagnosis.
4. **Diagnosis (read-only):** the rubric (§11.3); in review/update also `kh validate` and `kh check`.
5. **Discovery:** `scripts/discover.sh` (facts), `kh measure` (metrics that are also gates, B2) and
   `scripts/measure.sh` (proposal-only metrics).
6. **Rounds:** at most 4 questions each, the recommended option first, every proposal with its measured
   evidence and a cited source; areas in §11.4. Low confidence → narrow question; no confidence → the
   layer is not installed and the reason is said.
7. **One proposal block:** every file to write or change, one line of reason each.
8. **Writes, in this order, each confirmed:** wrapper + lock → `keel.yml` → native tool configs →
   baselines (`kh measure` output) → guides (`AGENTS.md`, `CLAUDE.md`, topic files) → ADRs → reviewer
   definitions + `docs/review.md` → PR template (if adopted) → git hooks → `.gitignore` →
   `.claude/settings.json` last (§9.4 explains why last).
9. **Verification:** `kh validate`, `kh check`, `kh gate fast --all`; `kh gate slow --all` if the user
   accepts its cost. Every result reported as measured.
10. **Hand-off:** the skill never commits. It tells the human to review and commit, to run
    `.agents/bin/kh setup`, and to open a **new session** — in any of the three agents. Reason: guides
    load at session start and the setup conversation is noise; settings-file hooks are picked up by
    Claude Code's file watcher [fact], so hooks are not the reason.

### 4.2 Development session (any of the three agents; plugin not needed)

- The agent loads `AGENTS.md`, an index of at most 100 lines (Claude via `CLAUDE.md` → `@AGENTS.md`;
  Copilot and Devin natively [fact]), and reads topic files only when a task needs them.
- A multi-step task gets `.agents/plans/<slug>.md` with `Status`, `Scope` and `Acceptance` (§10).
- Declared scripts run through `kh run <script>`. A direct call to a declared executable is denied with
  the exact `kh run …` to use (interception, §8.2).
- A write to a protected file through Write/Edit asks the human; through the shell it is denied (§8).
- **End of turn:** the Stop hook runs the `fast` gate when the tree changed since the last green result.
  A failure forces **one** more turn carrying the reduced result; the same failure relayed again lets the
  agent stop and shows the failure to the human (§9.1) [owner: +1 turn when needed].
- **Before finishing** (guide in `AGENTS.md`): gates green; **ask the human whether to run the
  independent review** [owner]; close the plan (delete it, append one history line); propose lessons for
  the human to triage; keep handoff notes local; when unsure whether something is shareable, ask.
- **Commit:** pre-commit runs the `commit` gate on staged files (incl. memory hygiene and secrets);
  commit-msg runs `commit-message` if adopted; pre-push runs the `slow` gate on the branch.

### 4.3 Fresh clone (a teammate without the plugin)

Clone → `.agents/bin/kh setup` (downloads and verifies the pinned `kh`, activates the git hooks in
native mode, runs `kh check`) → open any of the three agents. Agent hooks are versioned, so they work
from the first session (with no verified binary yet, the hooks behave as §9.5 says); `kh check` reports
`githooks-inactive` until `kh setup` ran. `AGENTS.md`'s first command line is `sh .agents/bin/kh setup`.
Every keel entry point (hooks, git hooks, docs) invokes the wrapper through `sh`, so no file depends on
an exec bit surviving a Write [builder].

### 4.4 Evolution

When a rule blocks legitimate work, the agent cannot edit the harness: it explains, proposes the change
(and the ADR when the change loosens a rule) and the human either confirms the edit or runs the skill in
update mode. `kh check` detects drift with no plugin; the skill only interprets its output.

## 5. Repository layout after setup

`V` versioned, `L` local (git-ignored), `P` protected (§8.1).

```
AGENTS.md                                V P  index, ≤100 lines, only what the agent cannot discover
CLAUDE.md                                V P  "@AGENTS.md" and nothing else
docs/architecture.md, conventions.md,    V P  rule sections (listed in keel.yml `guides:`)
  testing.md, …
docs/review.md                           V P  who reviews, when, and the checklist (§9.3)
docs/adr/NNNN-*.md                       V P  MADR; accepted ADRs are immutable (§8.3)
.github/pull_request_template.md         V P  if adopted (§12)
.agents/keel.yml                         V P  configuration (§6)
.agents/keel.lock                        V P  kh version + sha256 per platform
.agents/bin/kh                           V P  POSIX sh wrapper
.agents/baselines/*.tsv                  V P
.agents/githooks/{pre-commit,commit-msg,pre-push}  V P  native mode only (§6)
.agents/plans/<slug>.md                  V    active plans only; deleted at close
.agents/progress.md                      V    task history, one line per closed task
.agents/lessons.md                       V    triaged lessons
.agents/run/                             L    evidence, gate history, lock, handoff.md, lessons-inbox.md
.claude/settings.json                    V P  hooks → .agents/bin/kh hook … (all three agents, §9.1)
.claude/agents/keel-reviewer.md          V P  reviewer for Claude Code (Devin imports it)
.github/agents/keel-reviewer.agent.md    V P  reviewer for Copilot CLI
<native tool configs named in `config:`> V P  e.g. .dependency-cruiser.cjs, ArchUnit test, eslint config
```

`.agents/skills/` and anything else under `.agents/` not listed here belong to other tools (the
`skills` CLI already uses `.agents/skills/` in this repository [fact]); keel never reads, writes or
protects them. `.github/hooks/` and `.devin/` are not generated but are protected against writes (§8.1).

## 6. Configuration — `.agents/keel.yml` v1

Kept from v0.4: one entity, the **script** (package.json-like); a **gate** is a list of scripts; short
form (a plain command, exit code only) and expanded form; no implicit pre/post; pipes discouraged.

```yaml
version: 1
adr_dir: docs/adr                               # default
review_due: 2027-05-04                          # harness review date (kh check: review-due)
guides: [AGENTS.md, CLAUDE.md, docs/architecture.md, docs/conventions.md, docs/testing.md, docs/review.md]
githooks: { mode: native, pre-commit: commit, pre-push: slow, commit-msg: commit-message }
scripts:
  test:
    run: npx vitest run --reporter=junit --outputFile={report}
    format: junit
    reports: "{report}"
    class: correctness
    timeout: 10m
    retries: 1
    guidance: >-
      Read the failing assertion; do not change the expectation to the new value without an ADR.
  lint:
    run: npx eslint -f json
    files: "*.{ts,tsx}"
    format: eslint-json
    class: heuristic
    baseline: .agents/baselines/lint.tsv        # baseline present = ratchet
    config: [eslint.config.js]                  # changing these files is a loosening (§8.3)
  typecheck:
    run: npx tsc --noEmit
    files: "*.{ts,tsx}"
    pass_files: false
    format: errorformat
    pattern: '^(?P<file>[^(]+)\((?P<line>\d+),(?P<col>\d+)\): error (?P<rule>TS\d+): (?P<message>.*)$'
    class: correctness
  architecture:
    run: npx depcruise src --config .dependency-cruiser.cjs --output-type err
    format: errorformat
    pattern: '…'                                # [builder] pinned by a recorded fixture
    class: correctness
    config: [.dependency-cruiser.cjs]
    decision: docs/adr/0002-hexagonal.md
    doc: docs/architecture.md#layers
  file-size:
    builtin: file-size
    with: { limit: 300, include: ["src/**"] }
    class: heuristic
    baseline: .agents/baselines/file-size.tsv
    decision: docs/adr/0003-file-size.md
  secrets: { run: "gitleaks detect --no-banner --report-format sarif --report-path {report}", format: sarif, reports: "{report}", class: security, requires: [gitleaks] }
  memory: { builtin: memory, class: correctness }
  commit-message: { builtin: commit-message, with: { pattern: '^(feat|fix|docs|refactor|test|chore)(\(.+\))?!?: .+' } }
  merge-check: { builtin: merge-check }
gates:
  fast:   { scripts: [guard, secrets, typecheck, lint, file-size, architecture], changes: worktree, ceiling: 30s }
  commit: { scripts: [guard, secrets, memory, lint], changes: staged, ceiling: 30s }
  slow:   { scripts: [guard, test, merge-check], changes: branch, ceiling: 10m }
```

Rules (v0.4 rules kept unless stated):
- `run:` is a shell string run with `bash -o pipefail -c` from the repository root; `{report}` expands to
  a fresh path under the run's evidence directory.
- **Change scoping** (pre-commit model): `files:` globs changed files; matches are appended as
  arguments (`pass_files: true` by default); `kh gate <name> --all` passes every tracked match, batched
  under `ARG_MAX`, one merged verdict; no match → `skip` "no changed files in scope", never a silent pass.
- **Change base per gate:** `worktree` (tracked diff vs `HEAD` + untracked), `staged` (files in the
  index), `branch` (vs `KEEL_GUARD_BASE`, else merge-base with `origin/HEAD`, else `HEAD`). `staged`
  narrows the file list only; tools read content from disk — a declared limitation.
- **Missing tool:** `requires:` executables not on `PATH`, or exit 127 with no `requires`, is a `skip`
  naming the tool and the fix. A `skip` of a `class: security` script fails the gate.
- **Ratchet vs strict** [owner, round 3 cut]: a script with `baseline` is a ratchet (findings may only
  shrink); a script without one is strict. Only `class: heuristic` scripts take a keel TSV baseline;
  `correctness` scripts may use their tool's native baseline (ArchUnit freeze, `depcruise-baseline`);
  `security` never takes one — `kh validate` rejects the other combinations (v0.3 sensor contract kept).
- **TSV baseline format** (v0.3 kept): first line `# measured_at: YYYY-MM-DD review_by: YYYY-MM-DD`, then
  `path<TAB>count`, one row per file, count = all findings of that script in that file. A file absent from
  the baseline may have zero. A script fails when any file exceeds its row; shrinking is always allowed.
- **One harness per git repository** [builder, flagged]: `kh` resolves the project root as the git
  top-level and reads `.agents/keel.yml` there; a `keel.yml` below the top-level is a `kh validate` error
  in v0.5 (replaces v0.4's "nearest `keel.yml` wins"). Monorepos use one `keel.yml` with per-package
  scripts scoped by `files:`. A git submodule is its own repository and has its own harness. `enforcement`,
  `mandatory`, substitute ADRs and CODEOWNERS approval are gone; every loosening needs an ADR (§8.3).
- **Rule metadata** (fields of the script that enforces the rule): `decision` (ADR path), `doc` (docs
  anchor), `config` (files whose change is a loosening), `exceptions: [{path, until}]` (deadline that can
  only shrink), `exemplar`, `legacy`. `origin`, `approved_at` and `plan` are dropped (git has them).
  A builtin's own parameters go under `with:` with a strict sub-schema per builtin.
- A rule with no computational check (an inferential principle) is not in `keel.yml`; it lives in its
  topic file and in the review checklist.
- **Required gates:** `fast` (Stop hook), `commit` (pre-commit), `slow` (pre-push). Each must list
  `guard`; a missing one is a `kh validate` error.
- **`githooks.mode`:** `native` — `kh setup` points `core.hooksPath` to `.agents/githooks/`; `external`
  — the project's own manager (husky, lefthook, pre-commit) calls the same `.agents/bin/kh` commands and
  `kh check` verifies the call is present in its config.
- **Strict validation:** unknown keys, an unknown builtin, a format without its required fields, a gate
  naming an unknown script, a required gate without `guard` → exit 3. `kh validate` is the authority;
  `kh schema keel` prints the JSON Schema (single source, R0.6). "An installed harness" means
  `.agents/keel.yml` exists; there is no `state.yml` (P-13).
- Tool-native affected selection (`vitest --changed`, `nx affected`) is preferred when it exists; that is
  catalog guidance, not a `kh` feature.

## 7. Execution — `kh`

```
kh run <script> [-- extra args]       one declared script
kh run -- <command…>                  any command: capture, verdict from exit code, generic reduction
kh gate <name> [--all]                the gate's scripts, in order
kh show <run-id> [--failures|--full|--json]
kh measure <script>                   per-file counts as a TSV baseline on stdout; never writes a file
kh validate | kh check | kh guard
kh hook pre-tool-use | stop | commit-msg <file>
kh setup                              per clone: fetch + verify the pinned kh, activate native git hooks, run kh check
kh schema keel|result|memory          JSON Schemas (the single contract source)
kh version
```

Kept from v0.4 (implemented in M0 where marked):
- Each script runs in its own process group; stdout and stderr captured as one ordered stream, streamed
  to the evidence log, redacted [M0]. Timeout per script (default 10 min): SIGTERM, then SIGKILL after
  5 s; status `error` [M0]. Retries 0–3 on `fail` only; a pass after a retry is `pass (flaky: k/n)`;
  `error` is never retried. Scripts run sequentially; one gate at a time per repository (lock in
  `.agents/run/`).
- **Statuses and invariants:** `pass` 0, `fail` 1, `skip` 2, `error` 3; `kh gate` exits 1 if any script
  failed or errored; invalid config or pin 3; bad usage 64. The verdict comes from the exit code, the
  parser and the baseline, never from a model. A parser enriches a failure and never turns a non-zero
  exit into `pass`; the only exception is a baselined `heuristic` script, whose status is the comparison
  with its baseline. An unrecognised output falls back to the generic reduction with `parsed: false`; a
  declared report missing after the run is `error`.
- **Output:** compact text by default (one block per non-passing script with at most 5 findings, most
  severe first; one line per passing script; a verdict line; stdout capped at 40 lines, cap announced);
  `--json` result schema versioned with `keel.yml` (`kh schema result`).
- **Generic reduction** without a parser: exit code, first 5 lines matching a fixed error vocabulary,
  last 10 lines [M0]. Nothing is lost: `kh show` prints the rest.
- **Evidence:** `.agents/run/runs/<id>/` (`meta.json` with `kh` version, `HEAD`, diff hash, exit,
  attempts, timings; `output.log`; `findings.json`; report copies); ID `YYYYMMDD-HHMMSS-<4 hex>`;
  retention 50 runs or 200 MB [M0]. Redaction of secret-looking env values and known token patterns,
  best effort; evidence never leaves the machine [M0].
- No network and no model at gate time; the wrapper's one-time download is the only network access.

### 7.1 Formats (parsing per format, not per tool)

`junit`, `sarif` (2.1.0), `checkstyle`, `eslint-json`, `errorformat` (one named-group regex,
multi-line continuation optional), none (exit code). **Each catalog row whose format `kh` parses has a
recorded real output** of that tool as a fixture in `cli/kh/testdata/formats/<format>/<tool>-<version>.*`,
with the exact command and tool version that produced it [owner, round 4]. A tool that changes flags or
output after the recording is not detected by these tests — declared in §17.

### 7.2 Builtins

Kept from v0.4: `guard`, `file-size`, `code-language`, `folder-layout`, `pattern`,
`architecture-grep`, `test-presence`, `dependencies`. **Their behaviour and parameters are ported from
the v0.3 bash sensors and their tests** (`assets/core/sensors/**`, `tests/keel_*_test.sh`), which are
the reference: parameter names become `with:` keys in snake_case [builder]. The port happens in M3,
before M6 deletes the bash sources. New in v0.5:

| Builtin | Checks | Default class / gate |
| --- | --- | --- |
| `memory` | Format of plans, progress and lessons (`kh schema memory`); forbidden content in versioned memory: absolute user paths (`/home/<user>`, `/Users/<user>`), references to `.agents/run/` or run IDs, secret patterns (the redaction set) | correctness / `commit` |
| `scope` | Changed files outside the `Scope:` globs of the active plan(s); no active plan → `skip` | heuristic / `fast` |
| `merge-check` | Conflicts with the upstream branch (`git merge-tree --write-tree`); summary says how many commits behind | correctness / `slow` |
| `commit-message` | The commit message matches `with.pattern` (used by `kh hook commit-msg`) | correctness / commit-msg |
| `branch-name` | The current branch matches `with.pattern` | heuristic / `slow` |

`exec:` stays as the escape hatch: a file that obeys the line-1 contract
(`id<TAB>class<TAB>status<TAB>summary`, exit 0/1/2).

## 8. Protection, guard and authority

### 8.1 Protected set

Fixed by `kh` and not configurable, apart from the files each script names in `config:` [owner; no
generic `protect:` key, owner 2026-11-04]:
- **Engine and configuration:** `.agents/keel.yml`, `.agents/keel.lock`, `.agents/bin/**`,
  `.agents/baselines/**`, `.agents/githooks/**`, files named in any script's `config:`.
- **Agent hooks and agent configuration that can disable them:** `.claude/settings.json`,
  `.claude/settings.local.json`, `.claude/agents/keel-reviewer.md`, `.github/hooks/**`,
  `.github/copilot/settings*.json`, `.github/agents/keel-reviewer.agent.md`, `.devin/**` (e.g.
  `read_config_from` could turn the `.claude/` import off), `.git/hooks/**`, `.git/config`; and the
  user-level agent settings files that can disable repository hooks (exact paths per agent: builder).
- **Guides:** every path in `guides:`; `docs/review.md`; the PR template.
- **ADRs:** everything under `adr_dir` [owner].

### 8.2 Decisions of `kh hook pre-tool-use`

| Agent action | Decision |
| --- | --- |
| Write/Edit/MultiEdit/NotebookEdit (Claude names; Copilot `create`/`edit` arrive as `Write`/`Edit` in Claude format [fact]) on a protected path | `ask`, the reason naming the file and its class |
| The same while `permission_mode` is `bypassPermissions` or `dontAsk` | `deny` — `ask` is not guaranteed to prompt there [builder]; the reason tells the human to switch mode |
| Shell command that writes a protected path: redirection (`>`, `>>`), `tee`, `sed -i`, `perl -i`, `cp`, `mv`, `rm`, `ln`, `install`, `truncate`, `touch`, `chmod`, `git checkout/restore/reset/apply` on it, interpreters (`python -c`, `node -e`, `perl -e`, `ruby -e`) whose code names a protected path | `deny` |
| `git commit -n/--no-verify`, `git push --no-verify`, `git config core.hooksPath`, `git -c core.hooksPath=…`, `git update-index --assume-unchanged/--skip-worktree`, an inline `KH_BINARY=` or `KH_RELEASE_URL=` | `deny` |
| A Bash segment whose command signature equals a declared script's signature (v0.4 D62 tokenizer: split on `&&`, `\|\|`, `;`, `\|`, newlines; drop leading assignments; skip `cd`/`export`/`echo`; first token extended through known launchers) | `deny` naming `kh run <script>` and "do not pipe its output"; `kh run -- …` is the escape for undeclared commands |
| Anything the tokenizer cannot split (unbalanced quotes, `eval`, `$(…)` at the head) | allow |

The tokenizer only splits; it never rewrites. **Declared limit** (README and `AGENTS.md`): protection is
friction with evidence, not a security boundary; `guard` and the git hooks are the second line, and a
human can still bypass them — by design.

### 8.3 `guard` (builtin, in every required gate)

Compares the work tree with the base (`KEEL_GUARD_BASE` → merge-base with `origin/HEAD` → `HEAD`).
Loosenings: a script removed from a gate; `timeout`, `ceiling` or `retries` raised; `class` changed away
from `security`; `files` narrowed; `format` replaced by none; any change to the `run:` of a script with
`decision` set (thresholds living in the command line, D74); a baseline row grown or added; a file named
in `config:` changed; a `kh hook` entry removed or changed in `.claude/settings.json`; a `guides:` file
deleted; **an accepted ADR edited or deleted** (only the status line may change to
`Superseded by NNNN`) [owner: ADRs in the immutability set]. The v0.3 type-strictness checks (tsconfig
`strict`, mypy/pyright strictness) stay.

A loosening passes only when an ADR added since the base names the loosened script by id
(`.agents/keel.yml#file-size`) or the file; naming the whole `keel.yml` releases nothing. The ADR is a
protected write, so the human confirmed it.

**Tightening needs no ADR.** A baseline row that shrinks or disappears passes `guard`. When the measured
counts fall below the baseline, `kh check` warns `baseline-stale`; at close the agent proposes the
`kh measure` output as the new baseline and writes it with the human's confirmation (baselines are
protected). `kh` never auto-tightens (V15).

### 8.4 Authority

Local only [owner]: pre-commit and pre-push git hooks (agent-agnostic) and the agent hooks. Guidance with
friction, not a server-side gate.

## 9. Agent adaptation

### 9.1 One hook file for the three agents [builder, flagged for the owner]

Evidence [fact, official references read 2026-11-04]:
- Copilot CLI reads `.claude/settings.json` and `.claude/settings.local.json` in the repository, and
  "all hook entries from all sources are run". PascalCase events switch the payload to Claude's shape
  (`tool_name`, `tool_input`, Claude tool names).
- Devin CLI imports hooks, commands and custom subagents from `.claude/` by default
  (`read_config_from.claude`).
- So a separate `.github/hooks/keel.json` would make every hook run **twice** in Copilot.

Decision: **only `.claude/settings.json`** carries keel's hooks:

```json
{
  "hooks": {
    "PreToolUse": [{ "matcher": "Write|Edit|MultiEdit|NotebookEdit|Bash",
                     "hooks": [{ "type": "command", "command": "<kh> hook pre-tool-use", "timeout": 10 }] }],
    "Stop":       [{ "hooks": [{ "type": "command", "command": "<kh> hook stop", "timeout": 120 }] }]
  }
}
```

`<kh>` is `sh <repository root>/.agents/bin/kh`; the exact command form must work in all three agents
(root found from the payload's `cwd` and `git rev-parse --show-toplevel`, not from `$CLAUDE_PROJECT_DIR`
alone) [builder, pinned by the contract tests].

**Output contract:** one JSON valid for Claude and Copilot.
- PreToolUse: `hookSpecificOutput.{hookEventName, permissionDecision, permissionDecisionReason}` (Claude)
  and the same two fields at top level (Copilot).
- Stop: `{"decision": "block", "reason": <reduced gate result>}` — accepted by both; Copilot's
  `agentStop` has no `additionalContext` [fact].
- **Loop guard:** with `stop_hook_active` true (both agents send it [fact]) and the same failure
  fingerprint already relayed, the hook lets the agent stop and surfaces the failure to the human
  (`systemMessage` / stderr). At most one forced continuation per distinct failure; Copilot's cap of 8
  consecutive blocks is never reached.

**Verification:** the design **assumes the Copilot cross-read works as documented** [owner]; there is no
gating spike. Contract tests use payloads recorded headless from the installed CLIs where possible
(`claude -p`, `copilot -p`; Claude Code 2.1.318 and Copilot CLI 0.0.377 are on the owner's machine
[fact]), else the documented payload shapes. The owner validates the live behaviour in the three agents
after delivery and opens a fix if needed; the fallback then is a Copilot-specific file with
deduplication. Devin is trusted through its `.claude/` import the same way [owner].

### 9.2 Instructions

`AGENTS.md` is the only content file. `CLAUDE.md` contains only `@AGENTS.md`, so Devin, which reads both
[fact], gets no duplicate. No `.github/copilot-instructions.md`, no `.devin/rules` (Copilot CLI and
Devin read `AGENTS.md` [fact]). No `/keel-harness:*` reference anywhere in an installed harness (P-4):
messages cite `kh …` or "ask the human".

### 9.3 Independent review [owner]

- `docs/review.md`: who reviews (`keel-reviewer` subagent, a human, or another CLI the team names), when
  (before finishing / before the PR), and the checklist — the single copy of it.
- Two thin definitions with the same text: `.claude/agents/keel-reviewer.md` (Claude Code; Devin imports
  `.claude/` subagents [fact; exact path unconfirmed, trusted]) and `.github/agents/keel-reviewer.agent.md`
  (Copilot CLI loads agent profiles from `.github/agents` [fact]). Each says: fresh context, read-only
  tools, apply `docs/review.md` to the diff, report findings, change nothing.
- `AGENTS.md` "Before you finish": **always ask the human whether to run the independent review.**
- No script calls a model; `reviewer.sh` is gone.

### 9.4 Protection during the setup session

The skill's frontmatter declares a PreToolUse hook: `${CLAUDE_PLUGIN_ROOT}/kh/bin/kh hook pre-tool-use
--setup`. The plugin carries the wrapper and lock of the `kh` version it installs (same cache as the
repositories). With no `keel.yml`, `--setup` applies the fixed protected set of §8.1 plus the files the
setup will write. Once `.claude/settings.json` is written, the repository hook is also active in the
session (file watcher) and both may prompt for one write; that is why it is written last. The real
behaviour is checked in M6 [builder].

### 9.5 When `kh` cannot run [owner]

A fresh clone before `kh setup`, an offline machine, a cached binary that fails verification: the agents
treat a failing or timed-out hook as non-blocking, so protection would silently disappear. Instead:
- In hook mode (`hook …` as its first argument) **the wrapper never downloads** — the PreToolUse timeout
  is 10 s. Without a verified binary it answers by itself, in POSIX `sh` with no `jq`.
- **PreToolUse:** `ask` for every Write/Edit/Bash call, reason "kh unavailable: run
  `sh .agents/bin/kh setup`", in the dual shape of §9.1; `deny` when the payload's `permission_mode` is
  `bypassPermissions` or `dontAsk`. The human stays in the loop; the agent stays usable.
- **Stop:** never blocks; it tells the human that the gates did not run and why.
- The same applies to the plugin's setup-session hook (§9.4).

## 10. Memory [owner]

| Artifact | Where | V/L | Written by | Lifecycle | Checked by |
| --- | --- | --- | --- | --- | --- |
| ADRs | `adr_dir` | V, P | agent proposes, human confirms | accepted → immutable; changed only by a superseding ADR | `guard` |
| Active plans | `.agents/plans/<slug>.md` | V | agent | created for multi-step tasks; **deleted at close** | `memory`, `kh check` (`plan-stale`) |
| Task history | `.agents/progress.md` | V | agent, at close | one line: `- YYYY-MM-DD <slug>: <outcome> — <one line> [ADR NNNN]` | `memory`, `kh check` (`progress-size`) |
| Triaged lessons | `.agents/lessons.md` | V | agent proposes at close, human confirms | entry: Problem → Solution → Destination (rule id, ADR, guide or none) | `memory` |
| Raw lessons inbox | `.agents/run/lessons-inbox.md` | L | agent | emptied when triaged | — |
| Handoff notes | `.agents/run/handoff.md` | L | agent | per session | — |
| Evidence, gate history | `.agents/run/runs/` | L | `kh` | retention §7 | — |

Plan format: `# <title>`, `Status: active`, `Scope: <globs>`, `## Acceptance` (checklist), optional
`## Notes`. Exact schemas: `kh schema memory` [builder within these fields].
**Sanitization** [owner: always; commit only the indispensable]: the `memory` builtin in the `commit`
gate (§7.2), plus the guide line "commit only what another person needs; when unsure whether something
is shareable, ask the human". `kh` never writes memory (B3/B5): the agent writes, `kh` checks.

## 11. Plugin

### 11.1 Layout

```
plugins/keel-harness/
  .claude-plugin/plugin.json             version 0.5.0
  README.md                              ≤150 lines, user-facing; declared limits (§17)
  kh/bin/kh, kh/keel.lock                wrapper + lock of the kh version this plugin installs
  skills/harness/SKILL.md                entry point + frontmatter hook (§9.4)
  skills/harness/references/*.md         one level deep from SKILL.md
  skills/harness/templates/*             AGENTS.md, CLAUDE.md, keel.yml per stack, settings.json,
                                         reviewer ×2, review.md, ADR (MADR), plan, githooks,
                                         native architecture configs per style × tool, PR template
  skills/harness/scripts/*.sh            read-only: discover.sh, measure.sh
```

Skill name `harness`, invoked as `/keel-harness:harness` [builder]. The plugin carries no binary.

### 11.2 `SKILL.md`

Short (target ≤200 lines; Anthropic's guidance is under 500, references one level deep). It holds:
- the trigger description (create, review, update or assess a harness; make a repository agent-ready;
  define rules, conventions, architecture or testing strategy for agents);
- the mode detection and the phases of §4.1, each naming the reference to read;
- the invariants, stated once: nothing is written before the decisions; rounds of ≤4 questions,
  recommended first; evidence for every claim, "not measured" when not measured; what can be measured is
  measured by a script, never estimated; no inferential flow becomes a script; every write confirmed;
  never commit; never bump the `kh` pin silently;
- the write order of §4.1.

References (one level): `rubric.md`, `discovery.md`, `rounds.md`, `gates.md`, `protection.md`,
`memory.md`, `git.md`, `review.md`, `agents.md`, `verify.md`, catalog area files and stack profiles
(§12). Content is mined from today's assess/build/rules references.

### 11.3 Rubric

Axes, each `absent` / `partial` / `present` with the file that proves it, or `not measured`; no
aggregate score: bootstrap, reproducible build, guides, context reach (all three agents), fast gate, slow
gate, enforcement (git hooks + agent hooks; **no CI requirement**, P-7), protection, rules, memory, Git
cycle, review, security, observability, flaky tests (measured by three runs, else `not measured`).

### 11.4 Areas the rounds cover

Gates and scripts per stack; rules (architecture, layout, size, language, standards); testing strategy
(unit, integration, contract, e2e, property, regression, mutation, coverage, performance); security
(secrets, SCA, SAST); observability; memory; Git cycle (commit and branch conventions, PR template,
scope, merge check); review; agents in use; git-hook mode.

### 11.5 Scripts (read-only, B2/B3)

- `discover.sh`: languages and package managers, test runners, linters and their configs, architecture
  tools, existing git hooks and managers, instruction files (`AGENTS.md`, `CLAUDE.md`,
  `.github/copilot-instructions.md`, `.devin/`), agent hook files, commit-message and branch-name
  conventions from `git log`, CI files (informational), what is under `.agents/`.
- `measure.sh`: only proposal metrics no gate computes (directory shape, import matrix, framework imports
  inside the domain, test-file ratios, commit-message statistics). Every metric that is also a gate comes
  from `kh measure`.
Both print to stdout, write nothing, and are covered by bash tests.

## 12. Catalog

**Area files** (`references/catalog-<area>.md`, tool-agnostic), one section per topic with: id,
Questions, Measure (`kh measure <script>` or the tool with one rule on), Default (brownfield: the next
round number at or above p90 and not below p75; greenfield: the catalog default), Why (one line + one
source), Class and gate, Opinion (where the default is judgement).

**Stack profiles** (`references/stack-typescript.md`, `stack-python.md`, `stack-jvm.md`), one row per
topic: recommended tool, alternatives, command emitting a supported format, format, native baseline,
known pitfall (e.g. an ArchUnit release older than the JDK passes without checking anything), official
doc link, fixture id (or "unverified", which the skill must say when proposing it).

Growth: a new stack is one file; a new topic is one section and one row per stack. **The user chooses:**
the rounds offer the recommended tool and its alternatives and accept any tool that emits a supported
format, or only an exit code. After setup the project's `keel.yml` is the truth, not the catalog.

Topics and the recommended tool per stack [builder may substitute a tool when its fixture cannot be
recorded, and must say so]:

| Area | Topic | TypeScript/JS | Python | JVM |
| --- | --- | --- | --- | --- |
| tests | unit, integration | vitest / jest (junit) | pytest `--junitxml` | Gradle / Maven Surefire (junit) |
| tests | e2e (opt-in) | Playwright (junit) | pytest-playwright (junit) | runner (junit) |
| tests | contract (opt-in) | Pact JS | Pact Python | Pact JVM |
| tests | property-based | fast-check (inside the unit runner) | Hypothesis | jqwik |
| tests | regression | `test-presence` builtin + guide + review checklist item | same | same |
| tests | mutation (slow) | Stryker (`thresholds.break`) | mutmut | PIT (`mutationThreshold`) |
| tests | coverage (slow) | diff-cover `--fail-under` / vitest thresholds | diff-cover / coverage.py `fail_under` | diff-cover / JaCoCo check |
| tests | performance (opt-in, services) | k6 thresholds | pytest-benchmark compare / k6 | JMH via script / k6 |
| code | types | tsc (errorformat) | mypy / pyright (errorformat) | compiler (errorformat) |
| code | lint, naming, complexity, function size, params, suppressions | ESLint (eslint-json / SARIF) | ruff (SARIF) | Checkstyle / detekt (checkstyle) |
| code | formatting | Prettier `--check` | ruff format `--check` | Spotless check |
| code | dead code, duplication | knip, jscpd | vulture, jscpd | PMD, jscpd |
| code | file size, code language, comments, spelling | builtins (`file-size`, `code-language`, `pattern`) | same | same |
| architecture | layering, dependencies | dependency-cruiser | import-linter | ArchUnit (junit) |
| architecture | folder layout, exemplars | `folder-layout` builtin, `exemplar`/`legacy` | same | same |
| security | secrets | gitleaks (SARIF) | same | same |
| security | SCA | osv-scanner (SARIF) / npm audit | osv-scanner / pip-audit | osv-scanner / OWASP dependency-check |
| security | SAST | semgrep (SARIF) | semgrep | semgrep / SpotBugs (SARIF) |
| observability | logging, error handling | ESLint `no-console`, empty-catch rules + `pattern` | ruff `T20`, `BLE001` + `pattern` | Checkstyle/PMD rules + `pattern` |
| git | commit, branch, scope, conflicts, PR | builtins `commit-message`, `branch-name`, `scope`, `merge-check`; PR template | same | same |
| docs | `AGENTS.md`, topic files, ADRs | `kh check` | same | same |

## 13. `kh check`

Warnings about the harness itself; never part of a gate verdict.
- Kept from v0.4: `agents-size`, `agents-not-loaded`, `stale-command`, `dangling-pointer`,
  `hook-missing`, `guard-missing`, `baseline-stale`, `baseline-malformed`, `exception-expired`,
  `script-unavailable`, `run-state`, `review-due`.
- Restored [owner, R1.2/R1.6]: `exemplar-missing`, `plan-stale`, `progress-size`, and the memory format
  through the same code as the `memory` builtin (B2: one implementation, two entry points).
- New: `githooks-inactive`, `reviewer-missing`, `guide-unlisted` (a topic file linked from `AGENTS.md`
  that is not in `guides:`, hence unprotected), `pin-mismatch`.
- Removed: `mandatory-unsensored` (no `mandatory`), `protect-missing` (folded into `hook-missing`).

## 14. What changes in this repository

| Today | v0.5 |
| --- | --- |
| `plugins/keel-harness/assets/**` (bash engine, sensors, Claude adapters, CI workflow, pre-commit configs, `consequence.yml`, `README.agents.md`) | Removed; templates move to `skills/harness/templates/` |
| `scripts/keel`, `scripts/render.sh` | Removed (self-approval gone; native configs are the truth) |
| `scripts/measure.sh` | Trimmed to proposal-only metrics, moved to `skills/harness/scripts/` |
| `contracts/**` (8 files) | Removed; `kh schema` + this spec are the single source |
| `skills/assess`, `skills/build`, `skills/rules` | Replaced by `skills/harness` (content mined) |
| `evals/**` (30 cases) | Removed (effect evals out of v0.5; cases target removed skills) |
| `README.md` (459 lines, forensic) | Rewritten, ≤150 lines |
| `tests/keel_*.sh`, `assess_test.sh`, `build_test.sh`, `rules_test.sh` and keel fixtures | Removed with their subjects; new tests for the skill structure, templates and read-only scripts |
| `docs/specs/*keel*` (5), `docs/plans/*keel*` (27) | Removed; this spec added as `docs/specs/2026-11-04-keel-harness-v0.5-design.md`. Other plugins' docs untouched |
| `cli/kh` (M0) | M1–M5 completed |
| `.github/workflows/validate.yml` | Kept; a release workflow for `kh` added |
| `plugin.json` / marketplace | 0.5.0 |

## 15. Checklist coverage

"Catalog" means opt-in, proposed in the rounds, never imposed; "builtin" is `kh` code; "guide" is
inferential text. Every row is covered; none is out of scope for v0.5.

| Item | v0.5 coverage |
| --- | --- |
| Unit / integration tests | Catalog `unit`, `integration` (junit, recorded fixtures) |
| Contract tests | Catalog `contract` (Pact per stack) |
| End-to-end | Catalog `e2e` (Playwright and peers, slow) |
| Mutation testing | Catalog `mutation`; the tool enforces its threshold (exit code) |
| Property-based testing | Catalog `property-based`; the unit runner is the sensor |
| Regression | `test-presence` builtin + guide "a fix comes with a test that failed before" + review checklist |
| Load / performance | Catalog `performance`, proposed only when the repository runs a service |
| Coverage minimum | Catalog `coverage` (diff coverage and/or the tool's global threshold) |
| Mandatory gates before finishing | Stop hook (`fast`), pre-commit (`commit`), pre-push (`slow`), "Before you finish"; local limit declared |
| Independent verification | `guard` in every gate + reviewer subagent (asked every time) |
| Architecture fitness functions | Catalog `architecture` (native tool, config protected via `config:`), `folder-layout`, `dependencies`, `architecture-grep` |
| Naming, formatting, style guides | Catalog → the stack's linter and formatter |
| Directory layout | `folder-layout` builtin |
| Architectural principles | Catalog + topic file; uncomputable principles → guide + review checklist |
| Documentation conventions | `AGENTS.md` ≤100 lines, topic files, MADR ADRs; `kh check` |
| Error handling, logging, observability | Catalog `logging`, `error-handling` (linter rules + `pattern`) + guide |
| Security | `secrets` (security class, no baseline), catalog SCA and SAST, protection, `guard` |
| Golden samples | `exemplar`/`legacy` fields, nested `AGENTS.md` "follow X, not Y", `exemplar-missing` |
| Persistence, ADRs, history, task history, in-progress state | §10 |
| Handoff | Local notes + active plans (§10) |
| Self-sanitization | `memory` builtin in `commit` + guide + `kh check` |
| Branch and commit conventions | Catalog (detected from `git log` first), `commit-message`, `branch-name` |
| PRs and code review | PR template (Acceptance + pasted gate verdict lines) + `docs/review.md` |
| Independent agent review | Reviewer subagent definitions (§9.3) |
| Changes outside the task | `scope` builtin |
| Conflicts and unexpected changes | `merge-check` builtin; `guard`; tree fingerprint in evidence |

Status words for the checklist after v0.5: catalog rows with a recorded fixture are **"verified by
recorded output"**, not "verified with the real tool".

## 16. Release and distribution

- `github.com/aether-labs-org/plugins` is public [fact: anonymous API and page return 200], so the wrapper
  downloads release assets anonymously and GitHub artifact attestations are available.
- **Sequencing:** from M5 on, the release workflow publishes pre-releases `cli/kh/v0.5.0-rc.N`; the plugin's
  lock pins the latest rc until M8, which tags `cli/kh/v0.5.0` and bumps the lock. Tags are pushed by the
  owner (or with the owner's explicit confirmation). Tests before a published rc use `KH_BINARY` with a
  locally built binary and a test lock.
- Tags `cli/kh/vX.Y.Z`; reproducible builds (`CGO_ENABLED=0 -trimpath`, pinned Go toolchain; `make dist`
  byte-identical twice); `SHA256SUMS`; GitHub artifact attestations. Platforms: linux and darwin, amd64
  and arm64; Windows only through WSL.
- The release workflow lives in keel's own repository ("no CI" applies to target repositories).
- In each repository: `.agents/bin/kh` (POSIX `sh`, the Gradle-Wrapper/Bazelisk pattern) and
  `.agents/keel.lock`. The wrapper resolves the per-version cache (`$XDG_CACHE_HOME/keel/<version>/kh`,
  macOS `~/Library/Caches/keel/…`), downloads to a temp file, verifies, renames atomically, refuses a
  mismatch, and `exec`s. `KH_BINARY` (verified against the lock) and `KH_RELEASE_URL` (mirror) as
  overrides; a binary built from the tagged source with `make dist` matches the lock.
- **Trust root:** the lock the plugin carries for the version it installs; the skill copies it.
- Versions aligned: plugin 0.5.0 installs `kh` 0.5.0 [builder].
- Multi-project isolation (v0.4 D72) kept: per-repo pin, per-version cache, never a `kh` from `PATH`,
  per-repo and per-worktree run state, the git top-level's `.agents/keel.yml` is the only one (§6), the
  skill never bumps a pin silently.

## 17. Risks and declared limits

| Risk / limit | Handling |
| --- | --- |
| Effect never measured; a generated `AGENTS.md` can make agents worse (Gloaguen et al., arXiv 2602.11988: −0.5 to −2 % success, +20–23 % cost) | Evals out of v0.5 [owner]. Mitigation by design only: `AGENTS.md` carries only what the agent cannot discover, every line confirmed by the human. Declared in the README |
| Protection is friction, not a boundary | Declared; second line `guard` + git hooks |
| Copilot's handling of Claude-format output is not documented explicitly | Assumed to work [owner]; the owner validates after delivery; fallback in §9.1 |
| Devin import trusted, not tested | Owner reports problems [owner] |
| Recorded outputs miss tool flag/format changes | Declared; fixture names carry tool versions |
| `staged` scope reads disk content | Declared |
| Double prompt in the setup session; ~20 confirmations per setup | Write order (§4.1); accepted by the owner |
| First run needs the release host | `KH_RELEASE_URL`, `KH_BINARY`, source build |

## 18. Decisions

| ID | Decision | Origin |
| --- | --- | --- |
| V1 | v0.5 is the definitive version; breaking changes allowed; no migration from v0.1–v0.3 | owner |
| V2 | Four planes and boundary rules B1–B5 | owner, 2026-11-04 |
| V3 | `kh` is the only engine; the copied bash engine is removed | owner (was D54) |
| V4 | Authority is local; no generated CI | owner (D55) |
| V5 | Target agents: Claude Code, Copilot CLI, Devin CLI, latest versions | owner |
| V6 | One hook file, `.claude/settings.json`, for the three agents; one output contract | builder, flagged (§9.1) |
| V7 | Human confirms each harness write: `ask` on Write/Edit, `deny` for shell writes and bypass modes | owner (+ builder for bypass) |
| V8 | Protected set of §8.1, including accepted ADRs | owner |
| V9 | `plan/approve/apply` and `scripts/keel` removed | owner |
| V10 | Stop hook: at most +1 turn per distinct failure, `decision: block` | owner |
| V11 | Devin through its `.claude/` import; no `.devin/hooks.v1.json` | owner |
| V12 | No headless setup | owner |
| V13 | Reviewer subagent definitions + `docs/review.md`; the agent always asks; no model-calling script | owner |
| V14 | Memory model of §10 | owner |
| V15 | `kh` never writes memory, guides or baselines; the agent writes, `kh` checks | owner |
| V16 | `render` removed; native tool configs are the truth; `config:` protects them and makes any change a loosening that needs an ADR naming the script; no generic `protect:` key | owner |
| V17 | One entry skill | owner |
| V18 | Skill-scoped protection hook during setup | builder, from docs (§9.4) |
| V19 | Catalog = area files + stack profiles; parsing per format; the user may choose any tool | owner |
| V20 | Catalog stacks: TypeScript/JS, Python, JVM | owner |
| V21 | Catalog verification by recorded real outputs | owner |
| V22 | Checklist gaps in v0.5 as opt-in catalog items: Git cycle, test kinds, SCA/SAST, observability | owner |
| V23 | Cuts: A/S/L profiles, C0–C10, `mandatory` + substitute ADR + CODEOWNERS, upgrade paths, old docs, evals | owner |
| V24 | Effect evals out of v0.5 | owner |
| V25 | Dogfooding before release | owner |
| V26 | Versions aligned at 0.5.0; the plugin carries wrapper + lock | builder |
| V28 | With no verified `kh`, hooks fail safe: PreToolUse `ask` on every Write/Edit/Bash (`deny` under bypass), Stop never blocks and says the gates did not run; the wrapper never downloads in hook mode | owner |
| V29 | One harness per git repository (top-level `keel.yml`); nested `keel.yml` rejected in v0.5 | builder, flagged |
| V30 | No gating spike: the Copilot and Devin cross-reads are assumed to work; the owner validates live after delivery and opens fixes | owner |
| V31 | One feature branch from `origin/main`, merged once at release; M1–M5 additive; rc tags from M5 pushed by the owner | builder, flagged |
| V27 | Kept from v0.4: deterministic verdict and evidence (D53), scripts/gates (D56), scoping (D57), formats (D58), output/statuses (D59), evidence (D60), timeouts/retries (D61), interception for declared scripts (D62, now for all three agents), thin adapters (D63), distribution (D67), platforms (D68), no sandbox (D71), isolation (D72), no task-runner replacement (D73), tool-enforced thresholds (D74) | owner, 2026-11-03 |

## 19. Roadmap and acceptance

**Branching** [builder, flagged]: one feature branch `feat/keel-v0.5` from `origin/main` (the local
`main` is behind it [fact]); each milestone is a checkpoint on that branch whose acceptance holds and
whose `make check` and `make validate` pass. The branch merges into `main` once, at release, because the
marketplace serves the plugin from `main` [fact: `.claude-plugin/marketplace.json` → `./plugins/keel-harness`].
M1–M5 are additive (the old plugin stays intact); the removals of §14 happen in M6–M7. Commits and pushes
only with the owner's confirmation.

| M | Deliverable | Acceptance |
| --- | --- | --- |
| **M0** | Core run (done) | As shipped at `d3c16a6` |
| **M1** | `keel.yml` v1 schema and strict validation, gates, scoping, `requires`, lock check, `kh validate`, `kh gate`, `kh measure`, `kh schema keel` | `staged` excludes work-tree-only files; no match → `skip`; missing scanner on a `security` script fails the gate; `--all` batches past `ARG_MAX`; every invalid fixture exits 3, incl. a required gate without `guard`, an unknown `with:` key, a missing `githooks` gate |
| **M2** | Formats and reduction, text and `--json`, recorded fixtures | One recorded fixture per parsed row of §12 (tool, version, command recorded) parses to the expected findings; non-zero + unparseable report is never `pass`; ≤40 lines with the cap announced |
| **M3** | Builtins (v0.4 set + `memory`, `scope`, `merge-check`, `commit-message`, `branch-name`), baselines, `guard` | Every loosening of §8.3 fails without an ADR and passes with one naming the script; an accepted ADR edit fails; a removed `kh hook` entry fails; a `config:` file change fails; a grown baseline row fails; each new builtin has pass and fail fixtures |
| **M4** | `kh hook pre-tool-use`, `stop`, `commit-msg`; protection; interception; the hook file | Contract tests over Claude and Copilot payloads (recorded headless where possible, §9.1) produce the dual-shape output; every vector of §8.2 denied; protected Write/Edit → `ask`; bypass → `deny`; `./gradlew test` denied with `kh run test` when declared; undeclared `make foo` allowed; Stop silent on an unchanged green tree, blocks once on a failure, lets the agent stop on the same failure; the P-1 reproduction (shell edit of `keel.yml` removing `guard`) denied, and `kh validate` fails if it lands anyway |
| **M5** | `kh check` (§13), `kh setup`, wrapper, distribution, release workflow | Two repositories pinned to different versions run side by side; a tampered cached binary or `KH_BINARY` is refused; `make dist` byte-identical twice; wrapper runs on bash-less `sh`; with no verified binary the wrapper in hook mode downloads nothing and answers `ask` (PreToolUse), `deny` under bypass, and a non-blocking notice (Stop), in under 1 s; `kh setup` on a fresh clone activates native hooks; a release dry run produces `SHA256SUMS` and attestations |
| **M6** | Plugin: `skills/harness` (SKILL.md, references, catalog, templates, scripts, frontmatter hook); removals of §14 | Plugin tests green; `claude plugin validate --strict`; every reference link resolves; the `keel.yml` template for each stack passes `kh validate` on a fixture repository; `settings.json` template matches the hook contract; `discover.sh`/`measure.sh` leave the tree unchanged (asserted); no `/keel-harness:` string in any template; the setup-session hook asks on a protected write in a manual run |
| **M7** | Docs: this spec in `docs/specs/`, old keel docs removed, README ≤150 lines, versions 0.5.0 | No file in the repository references a removed path; README states the limits of §17 |
| **M8** | Dogfooding and release | This repository runs its own v0.5 harness, installed through the skill (`tests/run.sh`, `go test`, `make validate` as scripts); its gates green; tags `cli/kh/v0.5.0` and plugin 0.5.0 |

## 20. Left to the builder

Go package layout and YAML library; the generic reduction's error vocabulary; the wrapper's download tool
(`curl`, else `wget`); the exact command form of the hooks in `.claude/settings.json` (within §9.1); the
exact user-level agent settings paths in the protected set; exact memory schemas within §10's fields;
tool flags of each stack row (each pinned by its fixture); the errorformat patterns; whether the Stop
hook mentions `githooks-inactive`; `kh check` exit codes; JSON Schema generation; the order of M2/M3.
