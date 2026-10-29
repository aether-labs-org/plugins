---
name: assess
description: >
  Diagnoses a repository for AI coding agents, in two modes. Without an installed harness it scans
  the repo against a seven-axis rubric (bootstrap, guides, fast sensors, slow sensors, enforcement,
  context, rules), reporting each axis as absent, partial or present with the file that proves it,
  plus the estimated setup minutes to close each gap and the seconds added to the gate. With a
  harness installed (.agents/state.yml) it runs the portable validator, explains each warning
  (oversize AGENTS.md, stale commands, missing Stop hook or guard sensor, CI or pre-commit no longer
  running the gate, rules that disagree with their env files, stale baselines, overdue review) and
  proposes the fix. Writes nothing. Use when someone asks whether their repository is ready for AI
  agents, what is missing to work with coding agents, for an agent-readiness assessment or a
  harness diagnosis (always before the build skill), or whether their harness is out of date, stale
  or still valid, or wants a harness health check.
disallowed-tools: Write Edit NotebookEdit
---

# Assess

Report how ready this repository is for AI coding agents, or whether its installed harness is still
healthy.

## 0. Which question

First run `${CLAUDE_PLUGIN_ROOT}/scripts/keel check pre assess` from the repository root. It prints
`snapshot <token>`, the repository's status for the check at the end; keep the token. It writes nothing; when it exits non-zero (not a git work tree), show its
`missing:` line and stop. Then look for `.agents/state.yml`.

- **Absent: the readiness question.** No harness is installed. Follow sections 2 to 5: the rubric,
  the cost to close each gap, the report table.
- **Present: the health question.** A harness is installed. Follow sections 6 to 8: run the validator,
  explain each warning, propose the fix.
- **The user asks both** (for example "is the harness current, and is the repo ready for more?"): do
  both, health check first, then the rubric for the axes the harness does not already settle.

## 1. The single rule

**This skill writes nothing.** The tool list enforces it for `Write`, `Edit` and `NotebookEdit`; this
rule covers the shell. No shell command that modifies the
repository — no `touch`, no `mkdir`, no `git add`/`commit`, no formatter or fixer run "just to
check". Discovery is read-only: `cat`, `ls`, `find`, `grep`, and commands that only report (`--dry-run`,
`--check`, a linter or type checker's default read-only invocation). If a command would change a
file, or you are not sure whether it would, do not run it. When a sensor's cost can only be
measured by running it, running it to measure is fine as long as it does not persist output the
repository would otherwise not have (e.g. do not let it write a cache file into a tracked
directory — redirect elsewhere or discard).

Running `harness-check.sh` (section 6) is allowed: the validator is read-only, and its only possible
write is git-ignored temporary state under `.agents/run/tmp/`. So is `scripts/keel`: its assess commands
write nothing (the snapshot is a token in this conversation).

## 2. Discovery (readiness)

Identify the stack(s) by reading the filesystem. Monorepos can show more than one stack — expect
and handle several.

| Marker | Stack |
| --- | --- |
| `package.json` + `tsconfig.json` | typescript |
| `package.json` (no tsconfig) | javascript |
| `pom.xml` / `build.gradle` / `build.gradle.kts` | java |
| `pyproject.toml` / `setup.py` / `requirements.txt` | python |
| `go.mod` | go |
| `Cargo.toml` | rust |
| `*.csproj` / `*.fsproj` / `*.sln` | dotnet |
| none of the above | unknown — derive from repo artifacts |

Run these in parallel to build a picture of the repo. **Never invent commands** — use only what
you find here; the exact command comes from discovery, never assumption:

```bash
# Real scripts / targets
cat package.json 2>/dev/null | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('scripts',{}))" 2>/dev/null
grep -E "^[a-zA-Z_-]+:" Makefile 2>/dev/null | head -30
ls mvnw gradlew pnpm-lock.yaml yarn.lock package-lock.json uv.lock poetry.lock 2>/dev/null

# Docs (source of truth) and architecture hints
ls docs/ 2>/dev/null; find docs/ -maxdepth 2 -name "*.md" 2>/dev/null | sort
ls src/ lib/ app/ packages/ services/ cmd/ internal/ 2>/dev/null

# Existing sensors / CI / enforcement
ls .eslintrc* eslint.config* .prettierrc* tsconfig.json ruff.toml mypy.ini pyrightconfig.json \
   .pre-commit-config.yaml .github/workflows/ checkstyle.xml spotbugs* .golangci.yml deny.toml 2>/dev/null

# Instruction files the target agents (Claude Code, GitHub Copilot, Devin) load
ls AGENTS.md CLAUDE.md .claude/CLAUDE.md CLAUDE.local.md .claude/rules .github/copilot-instructions.md \
   .github/instructions .devin/rules .cursor/rules 2>/dev/null
find . -name AGENTS.md -not -path './node_modules/*' -not -path './.git/*' 2>/dev/null | head -20
grep -l '@AGENTS.md' CLAUDE.md .claude/CLAUDE.md 2>/dev/null

# Architecture tool configs, mutation tooling, rules and decisions
ls .dependency-cruiser.cjs .dependency-cruiser.js .importlinter stryker.conf.* mutmut_config.py \
   docs/architecture.md docs/conventions.md docs/testing.md docs/adr doc/adr docs/decisions .husky lefthook.yml 2>/dev/null
grep -lE 'archunit|pitest|info.solidsoft.pitest' pom.xml build.gradle build.gradle.kts 2>/dev/null
```

Also infer the **mode**: `greenfield` when no tracked source files exist in the stack's source
roots, `brownfield` otherwise. State the evidence as an inference for the user to confirm; never
record it as fact.

## 3. Scoring

Read `references/rubric.md` and classify each of the seven axes — `Bootstrap`, `Guides`,
`Fast sensors`, `Slow sensors`, `Enforcement`, `Context`, `Rules` — as `present`, `partial`, or `absent`,
per the table there. For every axis, record the repo-relative file that proves the classification
(a lockfile, a config file, a workflow file, `AGENTS.md` itself). If nothing proves it, there is no
evidence, and the axis cannot be `present`.

## 4. Cost

For each axis that is not `present`, state the cost of closing the gap in **estimated setup
minutes** — how long `build` (or `rules`, for the `Rules` axis) would take, confirmations included.
It is an estimate: it cannot be measured before the skill runs. **Enforcement** (pre-commit, CI) is
closed by `build`, which proposes both layers (a CI workflow and a pre-commit hook), so quote its setup
minutes like any other axis. For a missing or non-running fast sensor, also
state the **seconds it would add to the gate**, measured by actually running the tool once if it
is installed. If the tool is not installed, write `not measured` — never guess or estimate a
number. See `references/rubric.md` for the full cost-unit definitions and the three-confidence
inference table used when a judgment call is needed.

## 5. The report

Emit the mode inference above the table, then exactly this Markdown table, one row per axis, in the fixed axis order above:

```
| Axis | State | Evidence | Cost to close |
```

- **Evidence** is a backtick-quoted repo-relative path, or `—` when there is none.
- **Cost to close** is `N estimated setup minutes`, `+N.Ns gate`, `not measured`, or `—` (for a `present`
  axis, which has nothing to close).

After the table, add a short paragraph per `absent` axis naming what is missing and the cheapest
next step to close it. Say nothing about `present` or `partial` axes beyond the table row.

**Never emit a total, an overall grade, or an aggregate score.** There is no aggregate score —
see `references/rubric.md` for why.

## 6. Run the validator (health)

There is one implementation of the checks, the validator `harness-check.sh`. Run the plugin's latest
copy from the repository root:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/assets/core/harness-check.sh"
```

It prints one line per warning, `warn<TAB><check-id><TAB><file><TAB><message><TAB><fix>`, then
`harness-check: N warning(s)` or `harness-check: harness is clean`. Exit 0 clean, 1 warnings, 2 no
harness. Exit 2 means `.agents/state.yml` is missing, so this is the readiness question: say so, point
at `/keel-harness:build` and continue with section 2; that is a precondition, not a warning. Exit 3
means no writable temp directory (`TMPDIR`, else `.agents/run/tmp/`): report it, never guess the checks.

## 7. Explain each warning (health)

The fifteen checks, what each one means and where its fix goes are in `references/checks.md`. For
each warning the validator prints, say in plain words what is wrong, name the file, and propose the
fix through `/keel-harness:build` or `/keel-harness:rules` as that table says. **One broken condition
produces exactly one warning.** Stay silent about checks that found nothing: a clean harness is a valid
answer, and this skill never manufactures a warning.

Two more things to do every time:

- **Validator drift.** Compare the repository's copy with the plugin's:
  `cmp scripts/harness-check.sh "${CLAUDE_PLUGIN_ROOT}/assets/core/harness-check.sh"`. When they
  differ, propose updating the installed copy through `build` (the plugin's copy is the latest).
- **Contradictions between instruction files.** The validator does not read prose. Point the user
  at Claude Code's `/doctor prompt-audit` for contradictions across `AGENTS.md`, `CLAUDE.md` and
  the rest.

## 8. The health report

List the warnings (check id, file, what is wrong, the proposed fix), then the validator drift line.
Report and propose, then stop. The health check looks once, not across time: checks that need run
history (how often a sensor's failures are real) are not part of it.

Last, run `${CLAUDE_PLUGIN_ROOT}/scripts/keel verify assess <token>`. It exits 1 when the repository's status
differs from the snapshot, which means this run wrote something: say so and name what changed.
