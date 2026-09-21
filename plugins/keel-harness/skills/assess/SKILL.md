---
name: assess
description: >
  Diagnoses how ready a repository is for AI coding agents. Scans the repo against a
  six-axis rubric — bootstrap, guides, fast sensors, slow sensors, enforcement, context —
  reporting each axis as absent, partial or present with the file that proves it, plus the
  cost of closing each gap in setup minutes and seconds added to the gate. Writes nothing.
  Use when someone asks whether their repository is ready for AI agents, what is missing to
  work with coding agents, for an agent-readiness assessment or a harness diagnosis — and
  always before the build skill.
---

# Assess

Report how ready this repository is for AI coding agents.

## 1. The single rule

**This skill writes nothing.** No `Write`, no `Edit`, no shell command that modifies the
repository — no `touch`, no `mkdir`, no `git add`/`commit`, no formatter or fixer run "just to
check". Discovery is read-only: `cat`, `ls`, `find`, `grep`, and commands that only report (`--dry-run`,
`--check`, a linter or type checker's default read-only invocation). If a command would change a
file, or you are not sure whether it would, do not run it. When a sensor's cost can only be
measured by running it, running it to measure is fine as long as it does not persist output the
repository would otherwise not have (e.g. do not let it write a cache file into a tracked
directory — redirect elsewhere or discard).

## 2. Discovery

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

# Context: pointers and connector declarations
ls AGENTS.md .mcp.json 2>/dev/null
```

## 3. Scoring

Read `references/rubric.md` and classify each of the six axes — `Bootstrap`, `Guides`,
`Fast sensors`, `Slow sensors`, `Enforcement`, `Context` — as `present`, `partial`, or `absent`,
per the table there. For every axis, record the repo-relative file that proves the classification
(a lockfile, a config file, a workflow file, `AGENTS.md` itself). If nothing proves it, there is no
evidence, and the axis cannot be `present`.

## 4. Cost

For each axis that is not `present`, state the cost of closing the gap in **setup minutes** — how
long `build` would take, confirmations included. Two axes are not closed by `build` in this
version: **Enforcement** (v0.1 never installs blocking hooks, only PostToolUse) and **Slow
sensors** (mutation testing and nightly runs are out of scope for v0.1). For those two, report the
gap plainly and do not quote setup minutes — there is no build step yet that would close them. For
a missing or non-running fast sensor, also
state the **seconds it would add to the gate**, measured by actually running the tool once if it
is installed. If the tool is not installed, write `not measured` — never guess or estimate a
number. See `references/rubric.md` for the full cost-unit definitions and the three-confidence
inference table used when a judgment call is needed.

## 5. The report

Emit exactly this Markdown table, one row per axis, in the fixed axis order above:

```
| Axis | State | Evidence | Cost to close |
```

- **Evidence** is a backtick-quoted repo-relative path, or `—` when there is none.
- **Cost to close** is `N setup minutes`, `+N.Ns gate`, `not measured`, or `—` (for a `present`
  axis, which has nothing to close).

After the table, add a short paragraph per `absent` axis naming what is missing and the cheapest
next step to close it. Say nothing about `present` or `partial` axes beyond the table row.

**Never emit a total, an overall grade, or an aggregate score.** There is no aggregate score —
see `references/rubric.md` for why.
