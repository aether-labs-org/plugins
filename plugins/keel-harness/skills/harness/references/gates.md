# Scripts and gates (`.agents/keel.yml`)

`kh schema keel` prints the JSON Schema; `kh validate` is the authority. This page is the writer's guide.

## The shape

```yaml
version: 1
guides: [AGENTS.md, CLAUDE.md, docs/review.md]
githooks: { mode: native, pre-commit: commit, pre-push: slow, commit-msg: commit-message }
scripts:
  test:
    run: npx vitest run --reporter=junit --outputFile={report}
    format: junit
    reports: "{report}"
    class: correctness
gates:
  fast:   { scripts: [guard, secrets, typecheck, lint], changes: worktree, ceiling: 30s }
  commit: { scripts: [guard, secrets, memory, lint], changes: staged, ceiling: 30s }
  slow:   { scripts: [guard, test, merge-check], changes: branch, ceiling: 10m }
```

One entity, the **script**: a plain command (the exit code is the verdict) or the expanded form. A **gate** is an ordered list of
scripts. `fast`, `commit` and `slow` are required, and each must list `guard` (`guard` is reserved: it is the guard builtin and
cannot be redeclared).

## Fields that matter

- `run` is a shell string run with `bash -o pipefail -c` from the repository root; `{report}` expands to a fresh path in the
  run's evidence directory. A `run:` that contains `{report}` inside a flow mapping `{ ... }` must be quoted, or use the block
  form: an unquoted `{` there breaks the YAML.
- `files: "*.{ts,tsx}"` globs the changed files; matches are appended as arguments (`pass_files: true` by default). No match is a
  `skip` ("no changed files in scope"), never a silent pass. `pass_files: false` runs the command once without file arguments
  (tools that must see the whole project: `tsc`, `mypy`).
- `format`: `junit`, `sarif`, `checkstyle`, `eslint-json` or `errorformat` (one regular expression with the named groups `file`,
  `line`, `col`, `rule`, `severity`, `message`; indented lines after a match continue its message). A parser enriches a failure;
  it never turns a non-zero exit into a pass. No format means only the exit code and a generic reduction.
- `reports`: where a report file lands, when the tool does not write to stdout. A declared report that is missing, or older than
  the run, is an error. Gradle skips up-to-date tasks, so clean the task first.
- `class`: `security` (never a baseline; a skipped one fails the gate), `correctness`, `heuristic` (the only class that takes a TSV
  baseline).
- `baseline`: a TSV baseline makes the script a ratchet: findings per file may only shrink, and the tool's exit code is ignored in
  favour of the comparison. A script without one is strict.
- `requires`: executables that must be on the PATH; absent means `skip` naming the tool. Exit 127 without `requires` is the same.
- `timeout` (default 10m), `retries` (0 to 3, on `fail` only; `error` is never retried; a pass after a retry is `pass (flaky: k/n)`).
- `config`: files whose change is a loosening (the linter configuration, the architecture tool configuration, a mutation
  threshold file). They are protected and `guard` reports any change.
- `decision`, `doc`, `guidance`, `exemplar`, `legacy`, `exceptions: [{path, until}]` (a deadline that can only shrink).
- `builtin` + `with`: `file-size`, `code-language`, `folder-layout`, `pattern`, `architecture-grep`, `test-presence`,
  `dependencies`, `memory`, `scope`, `merge-check`, `commit-message`, `branch-name`, `guard`. `with` is decoded strictly: an
  unknown key is an error. `exec: file.sh` is the escape hatch (line 1 of its output is `id<TAB>class<TAB>status<TAB>summary`).

## Builtins and their `with:` keys

`with` is decoded strictly: an unknown key or a wrong type is a `kh validate` error. `sh .agents/bin/kh schema keel` prints the same
table as JSON Schema (`$defs.with.<builtin>`: keys, types, defaults, one example), generated from the code, so it never drifts.
`include` and `exclude` take a directory (`src`), a file or a glob (`*.ts` matches the base name at any depth, `src/**/*.py` the
whole path). Counting builtins feed a TSV baseline (class `heuristic`); the others are strict.

| Builtin | What it checks | `with:` keys (default) | Example |
| --- | --- | --- | --- |
| `file-size` | Lines per file over a limit | `limit` (300), `include`, `exclude` | `builtin: file-size`, `with: { limit: 300, include: [src] }` |
| `code-language` | Identifier and comment words outside the code language | `include`, `exclude`, `stoplist` (`pt`, or a repository path) | `builtin: code-language`, `with: { include: [src], stoplist: pt }` |
| `folder-layout` | Every file under `include` matches an allowed pattern | `include`, `exclude`, `allowed` (required; shell patterns where `*` crosses `/`) | `builtin: folder-layout`, `with: { include: [src], allowed: ["src/app/*", "src/domain/*"] }` |
| `pattern` | Lines matching a regular expression, per file | `pattern` (required, RE2), `include`, `exclude`, `message`, `fix` | `builtin: pattern`, `with: { pattern: 'console\.log\(', include: [src] }` |
| `test-presence` | A changed main file has a test at a mapped path | `mappings` (required; see below), `include`, `exclude` | `builtin: test-presence`, `with: { include: [src], mappings: [see below] }` |
| `architecture-grep` | Imports across layer boundaries (Java, Kotlin, Python) | `lang`, `layers` (`name`, `path`, `import`, `allowed`), `forbidden` (`layer`, `prefix`) | `builtin: architecture-grep`, `with: { lang: java, layers: [...] }` |
| `dependencies` | A new direct dependency with no ADR naming the manifest | `include`, `exclude` | `builtin: dependencies` |
| `guard` | The harness was loosened since the base (reserved id) | none | `builtin: guard` |
| `memory` | Plans, progress and lessons: format and leaks | none | `builtin: memory` |
| `scope` | Changed files outside the active plan's `Scope` | none | `builtin: scope` |
| `merge-check` | Conflicts with the upstream, commits behind | none | `builtin: merge-check` |
| `commit-message` | The commit message's first line matches | `pattern` (required, RE2) | `builtin: commit-message`, `with: { pattern: '^(feat\|fix): .+' }` |
| `branch-name` | The branch name matches | `pattern` (required, RE2) | `builtin: branch-name`, `with: { pattern: '^(feat\|fix)/[a-z0-9-]+$' }` |

**`test-presence` mappings** are not globs. Each line is `'<regex>|<replacement>'`: an RE2 regular expression matched against the main
file's path, a pipe, and the test path it maps to, with `$1`, `$2` (or `\1`) for the groups. Several lines are tried in order; a file
no line matches is not covered by the rule.

```yaml
test-presence:
  builtin: test-presence
  class: heuristic
  with:
    include: [src]
    mappings:
      - '^src/(.*)\.ts$|test/$1.test.ts'     # src/a/b.ts is expected to have test/a/b.test.ts
```

## Choosing the gate of a script

| Gate | Runs | Put here | Keep out |
| --- | --- | --- | --- |
| `fast` (Stop hook, `changes: worktree`) | at the end of each agent turn | types, lint, secrets, cheap builtins; inside 30 seconds | anything that needs a network, a database, a browser |
| `commit` (pre-commit, `changes: staged`) | before each commit | secrets, memory, lint on staged files | the test suite |
| `slow` (pre-push, `changes: branch`) | before a push | the test suite, mutation, coverage, SCA, SAST, `merge-check` | nothing: this is where the cost goes |

`staged` narrows the file list only; tools read content from disk. A tool-native "affected" selection (`vitest --changed`, `nx
affected`) is preferred over a file list when it exists.

## Ratchet or strict

Brownfield findings become a baseline (`kh measure <script>` prints it; the agent writes it with the human's confirmation) so the
count can only shrink. Greenfield scripts are strict. Never baseline a `security` or `correctness` script: for correctness use
the tool's own baseline (ArchUnit `FreezingArchRule`, `depcruise-baseline`), for security fix or `exceptions:` with a deadline.

## Check it

`sh .agents/bin/kh validate` must be silent. Then run each new script once (`kh run <id>`) and read its output before trusting it:
an errorformat pattern that matches nothing reports a clean run. See [verify](verify.md).
