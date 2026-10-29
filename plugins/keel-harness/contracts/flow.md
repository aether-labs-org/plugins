# Flow contract

How each skill's phases run and how each rule in a skill is verified. Skills reach this file as
`${CLAUDE_PLUGIN_ROOT}/contracts/flow.md`.

## Phases

`scripts/keel` runs the order of a skill's phases in code (spec section 5.1). Skills call it as
`${CLAUDE_PLUGIN_ROOT}/scripts/keel` from the target repository's root; there is no `bin/` (D34). It is
bash 3.2, needs no `jq` and no network. `<skill>` is `assess`, `build` or `rules`; any other name exits 64.

| Command | Behaviour | Exit |
| --- | --- | --- |
| `keel check pre <skill>` | Preconditions (below). For `assess` it also prints `snapshot <token>`, a `git hash-object` of `git status --porcelain` (minus `.agents/run/`); it writes nothing | 0 met; 1 unmet, one `missing: …` line per item |
| `keel plan <skill> <file>` | Copies `<file>` to `.agents/run/flow/<skill>.proposal`, deletes `<skill>.approved` and `<skill>.applied`, prints `proposal <skill> <hash>` | 0; 1 if `<file>` is missing |
| `keel approve <skill> <hash>` | Writes `<skill>.approved` as `<hash><TAB><UTC ISO time>`. Run it only after the user accepted that proposal in the conversation | 0; 1 with no proposal or a hash that is not the current proposal's |
| `keel apply <skill>` | The gate before any write: `<skill>.approved` must name the current proposal's hash; then writes `<skill>.applied` | 0 approved; 1 with `no approval for the current proposal - show it to the user, then run keel approve` |
| `keel verify <skill>` | The self-verification (below). One line per item: `ok <item>` or `fail <item>: <why>` | 0 all ok; 1 any fail |
| `keel measure …` / `keel render …` | Run `scripts/measure.sh` / `scripts/render.sh` with the same arguments | theirs |
| `keel check` | Runs the plugin's `assets/core/harness-check.sh` in the repository | its exit code |
| anything else | usage on stderr | 64 |

The hash is `git hash-object` of the proposal file, so it needs no tool beyond git.

### State files

All under `.agents/run/flow/`, which is git-ignored (D39).

| File | Written by | Holds |
| --- | --- | --- |
| `<skill>.proposal` | `plan` | The proposal exactly as shown to the user |
| `<skill>.approved` | `approve` | `<hash><TAB><UTC ISO time>` of the proposal the user accepted |
| `<skill>.applied` | `apply` | The time the writes were allowed to start |

`plan` removes `.approved` and `.applied`, so a changed proposal can never run on an old approval, and
`verify` then fails its `applied` item until the new proposal goes through `approve` and `apply`. `apply`
recomputes the hash from `.proposal`, so editing that file after `approve` is refused too.

### The rule

**No write before `keel apply <skill>` exits 0. Done means `keel verify <skill>` exits 0.** A skill
that writes (`build`, `rules`) shows the proposal, gets the user's answer, then runs `plan` →
`approve` → `apply` before its first write. When the user's own request accepted the proposal up front
("do not pause for confirmation"), the skill still runs all three, and says in its reply that the
acceptance came from the request. `assess` writes nothing: it runs `check pre assess` first and
`verify assess` last.

**Known limit.** The agent itself runs `keel approve`. The hash proves that what was approved is what
gets applied, not that a human said yes. The other layers are the PreToolUse hook
`scripts/hooks/claude-protect.sh` (spec section 5.3; `contracts/consequence.md`), which denies `Write`,
`Edit` and `NotebookEdit` on harness paths unless a `build` or `rules` approval recorded in
`.agents/run/flow/` is current (not a Bash write, not a path outside the map), and the process evals that
grade "asked before writing?" (spec section 5.4).

### Preconditions (`check pre`)

| Skill | Needs |
| --- | --- |
| `build` | A git work tree |
| `rules` | `scripts/gate.sh`, `scripts/lib/baseline.sh`, `scripts/lib/envparse.sh`, `scripts/sensors/guard.sh`, `.agents/state.yml`, and the Makefile targets `gate-fast` and `gate-slow`. If any is missing, offer `/keel-harness:build` first |
| `assess` | A git work tree |

### Verification (`verify`)

Item names are the words after `ok` / `fail`.

**`verify build`**

| # | Item | Passes when |
| --- | --- | --- |
| 1 | `agents-md` | `AGENTS.md` exists, has at most 100 lines, no `{{`, and a `Last updated: YYYY-MM-DD` line |
| 2 | `state-schema` | `.agents/state.yml` has `schema_version: 3` |
| 3 | `run-ignored` | `git check-ignore -q .agents/run/x` succeeds |
| 4 | `gate-ran` | `.agents/run/last-run.log` exists and its last line starts with `gate: fast - ` |
| 5 | `harness-check` | `bash scripts/harness-check.sh` exits 0 |
| 6 | `baselines` | Every `.agents/baselines/*.tsv` starts with `# measured_at:` |
| 7 | `portable-scripts` | `scripts/gate.sh`, `scripts/sensors/` and `scripts/lib/` contain neither `${CLAUDE_` nor `claude` as a command |
| 8 | `guard-installed` | `scripts/sensors/guard.sh` and `scripts/lib/envparse.sh` exist |
| 9 | `hook-settings` | When `state.yml` says `hook: installed`: `.claude/settings.json` has a `Stop` entry naming `scripts/hooks/claude-stop.sh` and the literal `${CLAUDE_PROJECT_DIR}`, and no `PostToolUse` entry running the gate |
| 10 | `hook-executable` | The same condition: `scripts/hooks/claude-stop.sh` is executable |
| 11 | `hook-json` | The same condition: `.claude/settings.json` is valid JSON (`python3 -I -m json.tool`; without `python3` the item says `skip (no python3)` and counts as ok) |
| 12 | `applied` | `.agents/run/flow/build.applied` exists: the install went through `keel apply` |
| 13 | `authority-map` | When `state.yml` says `authority: installed`: `.agents/consequence.yml` exists, has a `harness: <glob>` line, and every line is a comment, `!glob` or `category: glob` (`contracts/consequence.md`); otherwise `ok authority-map skip (authority is not installed)` |
| 14 | `authority-settings` | The same condition: `.claude/settings.json` has a `PreToolUse` entry with matcher `Write\|Edit\|NotebookEdit` naming `scripts/hooks/claude-protect.sh` with the literal `${CLAUDE_PROJECT_DIR}`, and is valid JSON (`python3 -I -m json.tool`; skipped without `python3`) |
| 15 | `authority-executable` | The same condition: `scripts/hooks/claude-protect.sh` is executable |

Two items stay with the skill because no script can check them: every command cited in `AGENTS.md`
really runs, and deep content is `→ docs/X.md` pointers rather than prose.

**`verify rules`**

| # | Item | Passes when |
| --- | --- | --- |
| 1 | `harness-check` | `bash scripts/harness-check.sh` exits 0 |
| 2 | `gate-passed` | `.agents/run/last-run.log` ends with a line starting `gate: fast - PASSED` |
| 3 | `rule-env` | Every `.agents/rules/*.env` parses with `scripts/lib/envparse.sh` and has `RULE_ID`, `KIND`, `ORIGIN` and `DOC` |
| 4 | `rule-doc` | Every `DOC=<file>#<anchor>` names an existing file with an `<a id="<anchor>">` |
| 5 | `applied` | `.agents/run/flow/rules.applied` exists |

**`verify assess <token>`**

| # | Item | Passes when |
| --- | --- | --- |
| 1 | `status` | The token of `git status --porcelain` minus `.agents/run/` equals the one `check pre assess` printed. Without a token it fails and asks for it |

`assess` writes nothing, so neither `check pre assess` nor `verify assess` writes a file.

## Traceability

Every line of a `skills/*/SKILL.md` that contains `never`, `Never`, `always`, `Always`, `**Write nothing`,
`writes nothing` or `must` has a row here (D37). `tests/keel_traceability_test.sh` collects those lines
mechanically and fails when one has no row, when a row's quote matches no line of its skill, or when a
`Checked by` target does not exist.

**Form** follows the failure the rule prevents (spec section 5.5): `recipe` (the shape of the output),
`slot` (a required field of the output) or `discipline` (skipping a step, writing early, inventing a
command).

**Checked by** lists one or more targets separated by `; `, each optionally followed by a note in
parentheses:

- `test:tests/<file>.sh`: a test under `tests/`. A note `(text)` means the test only pins the rule's
  wording in the skill or contract; it does not exercise the behaviour.
- `verify:<skill> item N`: row `N` of that skill's `keel verify` table above.
- `eval:<case>/graders/<file>`: a grader under `evals/` (run by the owner, never by `tests/run.sh`).
- `hook:<file>`: a hook script, as a path from the plugin root (`hook:assets/adapters/claude/claude-protect.sh`, the PreToolUse hook of `contracts/consequence.md`).
- `none (reason)`: nothing checks the rule. The reason is mandatory and the row is a gap.

| Skill | Rule | Form | Checked by |
| --- | --- | --- | --- |
| assess | "always before the build skill" | recipe | none (a routing hint in the description, not a behaviour - a gap) |
| assess | "every fix is proposed, never made" | discipline | verify:assess item 1; eval:assess-finds-drift/graders/no-write.md; eval:assess-finds-drift/graders/no-bash-write.md; eval:assess-pressure-fix-it/graders/no-write.md; eval:assess-pressure-fix-it/graders/no-bash-write.md; eval:assess-pressure-fix-it/graders/names-agents-size.md; eval:assess-pressure-create-agents/graders/names-build.md |
| assess | "It writes nothing;" | discipline | test:tests/keel_cli_test.sh (check pre assess creates no .agents/) |
| assess | "Never invent commands" | discipline | none (assess reports commands it found and writes none - a gap) |
| assess | "never assumption" | discipline | none (same as the row above - a gap) |
| assess | "never guess or estimate a number" | discipline | test:tests/assess_test.sh (text) |
| assess | "never guess the checks" | discipline | test:tests/keel_tmpdir_test.sh (the validator without a temp directory) |
| assess | "skill never manufactures a warning" | discipline | test:tests/keel_harness_check_test.sh (a clean harness reports `harness is clean`) |
| assess | "**This skill writes nothing.**" | discipline | verify:assess item 1; eval:assess-finds-drift/graders/no-write.md; eval:assess-finds-drift/graders/no-edit.md; eval:assess-finds-drift/graders/no-notebook-edit.md; eval:assess-finds-drift/graders/no-bash-write.md; eval:assess-pressure-fix-it/graders/no-edit.md; eval:assess-pressure-fix-it/graders/no-notebook-edit.md; eval:assess-pressure-create-agents/graders/no-write.md; eval:assess-pressure-create-agents/graders/no-edit.md; eval:assess-pressure-create-agents/graders/no-notebook-edit.md; eval:assess-pressure-create-agents/graders/no-bash-write.md; eval:assess-pressure-format/graders/no-write.md; eval:assess-pressure-format/graders/no-edit.md; eval:assess-pressure-format/graders/no-notebook-edit.md; eval:assess-pressure-format/graders/no-bash-write.md; eval:assess-pressure-format/graders/no-formatter.md; test:tests/keel_evals_test.sh (every read-only and bash case carries the four write graders); test:tests/assess_test.sh (disallowed-tools) |
| assess | "Never guess a number." | discipline | test:tests/assess_test.sh (text) |
| assess | "Never emit a total" | recipe | test:tests/assess_test.sh (text) |
| assess | "never record it as fact" | discipline | none (the mode is a sentence in the reply - a gap) |
| build | "writes nothing before the user confirms" | discipline | verify:build item 12; test:tests/keel_cli_test.sh (apply refuses without an approval of the current proposal); hook:assets/adapters/claude/claude-protect.sh (once installed, denies a Write, Edit or NotebookEdit on a harness path without a current approval, see tests/keel_protect_test.sh) |
| build | "You never regenerate a script from prose" | discipline | test:tests/keel_harness_check_test.sh (sensor-malformed catches a script whose id, class or mode drifted); verify:build item 5 |
| build | "Never regenerate a script from prose" | discipline | test:tests/keel_harness_check_test.sh (sensor-malformed catches a script whose id, class or mode drifted); verify:build item 5 |
| build | "Never invent a command" | discipline | test:tests/keel_harness_check_test.sh (stale-command catches an AGENTS.md command that does not exist); verify:build item 5 |
| build | "Never install a layer on a guess" | discipline | eval:build-java/graders/compile-not-installed.md |
| build | "The entry point is always" | slot | none (the bootstrap target is not machine-checked - a gap) |
| build | "never cite a script bare" | discipline | none (a gap, same as the row above) |
| build | "Never touch the managed-by header or the line-1 contract" | discipline | test:tests/keel_harness_check_test.sh (sensor-malformed) |
| build | "sensors never get one" | discipline | test:tests/build_test.sh (text) |
| build | "must run with this plugin absent" | discipline | verify:build item 7; test:tests/keel_assets_test.sh (no plugin path in any asset) |
| build | "the adapter always exits 0" | recipe | test:tests/keel_stop_hook_test.sh (the hook exits 0 for every gate result) |
| build | "never replace it with this repository's absolute path" | discipline | verify:build item 9; test:tests/keel_cli_test.sh (hook-settings fails on an absolute path) |
| build | "never edit the test to match" | slot | test:tests/keel_assets_test.sh |
| build | "**Write nothing before the user accepts" | discipline | verify:build item 12; test:tests/keel_cli_test.sh (apply refuses without an approval of the current proposal); hook:assets/adapters/claude/claude-protect.sh (once installed, denies a Write, Edit or NotebookEdit on a harness path without a current approval, see tests/keel_protect_test.sh) |
| build | "Never invent an owner" | discipline | none (no check can tell an invented owner from a real one, the rule is in SKILL.md and references/authority.md, and a line nobody answered stays out of CODEOWNERS - a gap) |
| rules | "always with a" | slot | eval:rules-brownfield/graders/mentions-p90.md |
| rules | "never migrates production" | discipline | eval:rules-brownfield/graders/never-edits-src.md; eval:rules-brownfield/graders/never-writes-src.md |
| rules | "Never present an" | discipline | eval:rules-brownfield/graders/env-origin.md (a proposed rule is recorded `ORIGIN=proposed`) |
| rules | "Never edit an accepted ADR" | discipline | none (no check reads ADR history - a gap) |
| rules | "sensors never get one" | discipline | test:tests/build_test.sh (text) |
| rules | "keel never raises one" | discipline | test:tests/keel_guard_test.sh (a grown baseline fails unless an ADR added in the same change names it) |
| rules | "keel never raises a baseline" | discipline | test:tests/keel_guard_test.sh (a grown baseline fails unless an ADR added in the same change names it) |
| rules | "must leave the gate green" | recipe | verify:rules item 2 |
| rules | "never run by the Stop hook" | discipline | test:tests/keel_stop_hook_test.sh |
| rules | "Plans never go under" | discipline | eval:rules-brownfield/graders/plan.md (a plan is written under `.agents/plans/`) |
| rules | "this skill never migrates anything itself" | discipline | eval:rules-brownfield/graders/never-edits-src.md; eval:rules-brownfield/graders/never-writes-src.md |
