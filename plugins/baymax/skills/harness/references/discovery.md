# Discovery

Before any question, gather facts. Everything here is read-only; nothing is written until the decisions are confirmed.

## The three sources

1. `bash <skill>/scripts/discover.sh` prints `key<TAB>value[<TAB>detail]` lines: languages, package managers, test runners, linters,
   formatters, type checkers, architecture tools, git hook managers, instruction files, agent hooks, the commit convention seen in
   the last 100 subjects, branch prefixes, CI files (informational only) and what is under `.agents/`. `<skill>` is the directory
   of this skill (`${CLAUDE_SKILL_DIR}` in Claude Code).
2. `sh .agents/bin/bmax measure <script>` prints the per-file counts of a script that is also a gate (file size, code language,
   patterns, dependencies, any linter-backed script), as a TSV baseline on stdout. It never writes a file. It needs a `bmax.yml`
   that declares the script, so before the first one exists measure with the tool itself or with `scripts/measure.sh`; once the
   user has confirmed the `bmax.yml` write, use `bmax measure` to produce the baselines.
3. `bash <skill>/scripts/measure.sh <subcommand>` prints proposal-only metrics no gate computes: `tree`, `imports`,
   `framework-imports`, `tests`, `commits`. It never duplicates a gate metric: B2 of the design says one implementation per metric.

In review or update mode (an `.agents/bmax.yml` exists) also run `sh .agents/bin/bmax validate` and `sh .agents/bin/bmax check`; their
output is the drift report. Explain each warning and propose the fix; do not repeat the check's logic.

## Runtime and install side effects

`discover.sh` prints `runtime node <version> <pin>`. Some tools exclude odd Node versions in their `engines` (dependency-cruiser:
`^22 || ^24 || >=26`), so compare the version with the `engines` of every tool you are about to propose and, when no `.nvmrc` or
`engines.node` pins a version, propose one. Recent pnpm installs dependencies by itself on `pnpm exec` and may write
`pnpm-workspace.yaml` (a real run added a supply-chain exemption nobody chose): say so in the proposal and check `git diff` after
the first run.

## Ignore rules

`discover.sh` prints two kinds of lines about `.gitignore`:

- `ignored <path>` for each harness path the current rules would hide (`.claude/settings.json`, `.claude/agents/baymax-reviewer.md`,
  `.github/agents/baymax-reviewer.agent.md`, `.agents/bmax.yml`, `.agents/bin/bmax`, `.agents/githooks/pre-commit`, `AGENTS.md`,
  `CLAUDE.md`). A hidden harness file is not versioned: nobody gets it on a clone. It answers for files not written yet too.
  Raise it before proposing any file; the fix is in [rounds](rounds.md) (write order, `.gitignore`).
- `ignored-dir <dir>` for each ignored directory of the repository (the top-most of each tree; at most 50, then one
  `ignored-dir-truncated <n>` line says how many were left out). The secrets scan needs them: see `.gitleaks.toml` in
  [rounds](rounds.md). Drop any directory that holds tracked files or harness files before you use the list.

## What to read besides the scripts

- The build files and the Makefile: the real commands (read them, do not run an install).
- The test and lint configuration, to see strictness and existing thresholds.
- `AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md`, `.devin/`: what the agents already receive, and what is stale.
- Existing git hooks and hook managers; the CI files only as information (Baymax generates no CI).
- Recent history (`git log`), for conventions and for what changes together.
- The ADR folder, if any: decisions already taken are not reopened.

## Facts vs. inferences

State a fact with its file ("`.dependency-cruiser.cjs` exists"). State an inference as an inference with its confidence (see the
[rubric](rubric.md)). A number comes from a script; if no script produced it, say "not measured".

## What discovery never does

- It never runs an install, a build or a test that writes, without the user's agreement.
- It never edits a file to "see what happens".
- It never calls a model from a script: an inferential question is yours to ask, in a round (see [rounds](rounds.md)).
- It never installs a tool: a missing tool is reported with the fix, and the script that needs it will `skip` with that message
  (a skipped `class: security` script fails the gate, which is the point).
