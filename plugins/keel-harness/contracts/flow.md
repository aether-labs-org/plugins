# Flow contract

How each skill's phases run and how each rule in a skill is verified. Skills reach this file as
`${CLAUDE_PLUGIN_ROOT}/contracts/flow.md`.

## Phases

`scripts/keel` runs the order of a skill's phases in code (spec section 5.1). Skills call it as
`${CLAUDE_PLUGIN_ROOT}/scripts/keel` from the target repository's root; there is no `bin/` (D34). It is
bash 3.2, needs no `jq` and no network. `<skill>` is `assess`, `build` or `rules`; any other name exits 64.

| Command | Behaviour | Exit |
| --- | --- | --- |
| `keel check pre <skill>` | Preconditions (below). For `assess` it also snapshots `git status --porcelain` (minus `.agents/run/`) into `.agents/run/flow/assess.pre` | 0 met; 1 unmet, one `missing: …` line per item |
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
| `assess.pre` | `check pre assess` | `git status --porcelain --untracked-files=all` before `assess` ran, without `.agents/run/` |

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
gets applied, not that a human said yes. The other layers are F3c's PreToolUse hook (spec section 5.3)
and the process evals that grade "asked before writing?" (spec section 5.4).

### Preconditions (`check pre`)

| Skill | Needs |
| --- | --- |
| `build` | A git work tree |
| `rules` | `scripts/gate.sh`, `scripts/lib/baseline.sh`, `scripts/lib/envparse.sh`, `scripts/sensors/guard.sh`, `.agents/state.yml`, and the Makefile targets `gate-fast` and `gate-slow`. If any is missing, offer `/keel-harness:build` first |
| `assess` | A git work tree |

### Verification (`verify`)

Item names are the words after `ok` / `fail`.

**`verify build`**

| Item | Passes when |
| --- | --- |
| `agents-md` | `AGENTS.md` exists, has at most 100 lines, no `{{`, and a `Last updated: YYYY-MM-DD` line |
| `state-schema` | `.agents/state.yml` has `schema_version: 3` |
| `run-ignored` | `git check-ignore -q .agents/run/x` succeeds |
| `gate-ran` | `.agents/run/last-run.log` exists and its last line starts with `gate: fast - ` |
| `harness-check` | `bash scripts/harness-check.sh` exits 0 |
| `baselines` | Every `.agents/baselines/*.tsv` starts with `# measured_at:` |
| `portable-scripts` | `scripts/gate.sh`, `scripts/sensors/` and `scripts/lib/` contain neither `${CLAUDE_` nor `claude` as a command |
| `guard-installed` | `scripts/sensors/guard.sh` and `scripts/lib/envparse.sh` exist |
| `hook-settings` | When `state.yml` says `hook: installed`: `.claude/settings.json` has a `Stop` entry naming `scripts/hooks/claude-stop.sh` and the literal `${CLAUDE_PROJECT_DIR}`, and no `PostToolUse` entry running the gate |
| `hook-executable` | The same condition: `scripts/hooks/claude-stop.sh` is executable |
| `hook-json` | The same condition: `.claude/settings.json` is valid JSON (`python3 -I -m json.tool`; without `python3` the item says `skip (no python3)` and counts as ok) |
| `applied` | `.agents/run/flow/build.applied` exists: the install went through `keel apply` |

Two items stay with the skill because no script can check them: every command cited in `AGENTS.md`
really runs, and deep content is `→ docs/X.md` pointers rather than prose.

**`verify rules`**

| Item | Passes when |
| --- | --- |
| `harness-check` | `bash scripts/harness-check.sh` exits 0 |
| `gate-passed` | `.agents/run/last-run.log` ends with a line starting `gate: fast - PASSED` |
| `rule-env` | Every `.agents/rules/*.env` parses with `scripts/lib/envparse.sh` and has `RULE_ID`, `KIND`, `ORIGIN` and `DOC` |
| `rule-doc` | Every `DOC=<file>#<anchor>` names an existing file with an `<a id="<anchor>">` |
| `applied` | `.agents/run/flow/rules.applied` exists |

**`verify assess`:** `git status --porcelain` minus `.agents/run/` equals the `assess.pre` snapshot
(item `status`). Without a snapshot it fails with `run keel check pre assess first`.

## Traceability

Filled in F2c-3: every `never` / `always` in a skill mapped to a test, a `keel verify` item or an eval
grader, classified by form (recipe / slot / discipline).
