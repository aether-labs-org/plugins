# Rule env file

`.agents/rules/<rule-id>.env` holds the rule's metadata and its machine parameters; the prose stays
in the topic file. It is plain `KEY=value`, read by `scripts/lib/envparse.sh` and never sourced or
executed (CRLF is tolerated; `$VAR` stays literal; a value with `$(` or a backtick fails), committed, and every
rule has one, inferential rules included. Multi-line values (`INCLUDE`, `ALLOWED`, `LAYERS`,
`FORBIDDEN`, `MAPPINGS`) are quoted strings, one item per line.

```sh
# Managed by keel-harness - see .agents/README.md
RULE_ID=file-size
KIND=metric                       # metric | structure | convention | pattern | testing
ORIGIN=proposed                   # discovered | proposed | user
APPROVED_AT=2026-10-20
ENFORCEMENT=sensor:file-size      # sensor:<id>[,sensor:<id>] | inferential
DOC=docs/conventions.md#file-size
DECISION=docs/adr/0003-file-size-limit.md         # optional; in adr_dir
PLAN=.agents/plans/2026-10-20-file-size.md        # optional; committed, removed when the plan is closed
LIMIT=300
INCLUDE='src/'
```

Parameters per sensor: `file-size` (`LIMIT`, `INCLUDE`, `EXCLUDE`), `folder-layout` (`INCLUDE`,
`ALLOWED`), `architecture` (`STYLE`, `LANG`, `BASE`, `LAYERS`, `FORBIDDEN`, `FREEZE`, and in brownfield Python
`IGNORE_IMPORTS`: one `importer -> imported` per line, import-linter's native baseline),
`code-language` (`INCLUDE`, `STOPLIST`), `testing-strategy` (`INCLUDE`, `MAPPINGS`,
`MUTATION_MIN_SCORE`, `DIFF_COVERAGE_MIN`). A sensor skips (exit 2) when its env file is missing.
Keys are UPPER_CASE. `guard` treats a `*MIN*` key that goes down, a `*LIMIT*`/`*MAX*` key that goes up,
a longer `ALLOWED`/`EXCLUDE`/`IGNORE_IMPORTS`, a shorter `INCLUDE`/`FORBIDDEN`, a changed `ENFORCEMENT`
or a deleted env file as a loosening that needs an ADR in the same change. It also compares the type-checker
configuration with the base (`type-strictness`, D44): a `tsconfig*.json` `strict` (or a flag it implies, or
`noUncheckedIndexedAccess`) that was on and is off or gone, mypy `strict`/`disallow_untyped_defs` turned off,
or a lower pyright `typeCheckingMode` is a loosening that needs an ADR naming that file. The rule has no env
file of its own.

## Exemplar and legacy zones (any rule)

Two optional keys in any rule env file point agents at the canonical example (C1b):

```sh
EXEMPLAR=src/orders/OrderService.ts      # the one file to copy for this rule
LEGACY='src/billing/
src/old-*.ts'                            # pathspecs, one per line, where the rule is not met yet
```

- `EXEMPLAR` is a repository path. `rules` proposes it only when the measurement shows a clear best
  file and writes it only after the user confirms it. `harness-check` warns (`exemplar-missing`) when
  the path no longer exists.
- `LEGACY` lists the zones that still break the rule. The nested `AGENTS.md` of those directories says
  `Follow <EXEMPLAR>, not <legacy path>` and `Legacy zone:` with a pointer to the rule's plan. Neither
  key changes what a sensor checks, so `guard` leaves them alone.

## The `pattern` sensor

`assets/core/sensors/rules/pattern.sh` is a generic, TSV-baselined sensor for a team's own approved
syntactic rule. It is copied as `scripts/sensors/<rule-id>.sh` with `id=<rule-id>` set inside its
`keel:repo-specific` block, so each pattern rule has its own env file and baseline.

| Key | Meaning |
| --- | --- |
| `PATTERN` | an ERE for `grep -E`; required when `ENGINE=grep` |
| `ENGINE` | `grep` (default), `ast-grep` or `semgrep`; the last two run only when installed, else the sensor skips |
| `RULE_FILE` | for `ast-grep` and `semgrep`: the committed rule file |
| `INCLUDE`, `EXCLUDE` | git pathspecs, one per line; `INCLUDE` empty means every tracked file |
| `CLASS` | `heuristic` (default) or `correctness` |
| `MESSAGE`, `FIX` | what is wrong, and the right fix in the repository's terms; both go into the guidance |

The count is per file (matching lines for `grep`, findings for the other engines) and is compared with
`.agents/baselines/<rule-id>.tsv`. `guard` treats a changed `PATTERN` or `RULE_FILE` (or an edited
rule file) as a loosening, because it changes what is caught.

## Catalog presets (D44)

Four catalog entries have no common linter rule behind them, so each is a `pattern.sh` rule: copy the
sensor as `scripts/sensors/<name>.sh` with `id=<name>`, write the block below as
`.agents/rules/<name>.env`, replace `INCLUDE` with the repository's source roots (no trailing `/`: git ignores an `EXCLUDE` pathspec
next to an `INCLUDE` that ends in `/`), and baseline the matches
that exist (`KEEL_MEASURE=1`). `tests/keel_rule_sensors_test.sh` runs each block against lines that must and
must not match. The sensor matches one line at a time: a multi-line form needs `ENGINE=ast-grep` or the
project's linter, which the catalog names per entry. All four are ratchet rules (`KIND=pattern`), and the
status of every one is *unproven* (D50).

### comments

A `TODO`, `FIXME` or `XXX` is allowed only with an issue reference right after the marker: `TODO(#123)`,
`TODO #123`, `TODO: https://tracker.example/1`. Any other form counts.

```sh
RULE_ID=comments
KIND=pattern
ORIGIN=proposed
ENFORCEMENT=sensor:comments
DOC=docs/conventions.md#comments
PATTERN='(^|[^A-Za-z0-9_])(TODO|FIXME|XXX)($|#([^0-9]|$)|[^A-Za-z0-9_#][: (]*([^#h: (]|#([^0-9]|$)|h([^t]|$)|ht([^t]|$)|htt([^p]|$)|$))'
INCLUDE='src'
MESSAGE='A TODO, FIXME or XXX comment has no issue reference.'
FIX='Write the reference right after the marker, as TODO(#123) or TODO: https://tracker.example/123, or do the work now.'
```

### suppressions

Counts the comments that switch a check off. A file keeps the count it had in the baseline, so suppressions
can only shrink. `@ts-expect-error` is left out on purpose: it fails once the error is gone.

```sh
RULE_ID=suppressions
KIND=pattern
ORIGIN=proposed
ENFORCEMENT=sensor:suppressions
DOC=docs/conventions.md#suppressions
PATTERN='eslint-disable|@ts-ignore|#[[:space:]]*(noqa|type:[[:space:]]*ignore)|@SuppressWarnings'
INCLUDE='src'
MESSAGE='A new lint or type-check suppression was added.'
FIX='Fix the finding the suppression hides. If it is a false positive, say so in a comment and ask for the baseline to be raised through an ADR.'
```

### error-handling

Empty `catch` blocks and `except ...: pass`, written on one line.

```sh
RULE_ID=error-handling
KIND=pattern
ORIGIN=proposed
ENFORCEMENT=sensor:error-handling
DOC=docs/conventions.md#error-handling
PATTERN='(^|[^A-Za-z0-9_])catch[[:space:]]*(\([^)]*\))?[[:space:]]*\{[[:space:]]*\}|(^|[^A-Za-z0-9_])except[^:]*:[[:space:]]*pass([[:space:]]|$)'
INCLUDE='src'
MESSAGE='An error is caught and ignored.'
FIX='Handle it, log it with context, or let it propagate. If ignoring it is right, say why in a comment and handle the one exception type that is expected.'
```

### logging

Direct console output under the source roots; tests and scripts are excluded. `EXCLUDE` is a list of git
pathspecs, where `*` also matches `/`.

```sh
RULE_ID=logging
KIND=pattern
ORIGIN=proposed
ENFORCEMENT=sensor:logging
DOC=docs/conventions.md#logging
PATTERN='console\.log|(^|[^A-Za-z0-9_.])print(ln)?[[:space:]]*\(|System\.out\.print'
INCLUDE='src'
EXCLUDE='*/test/*
*/tests/*
*.test.*
*.spec.*
*/scripts/*'
MESSAGE='Direct console output was added to application code.'
FIX='Use the repository logger instead (name it here), at the level the message deserves.'
```

## The `dependencies` sensor (D44)

`assets/core/sensors/rules/dependencies.sh` (class `security`, installed as `scripts/sensors/dependencies.sh`)
fails when a manifest gained a direct dependency since the base commit (`KEEL_GUARD_BASE`, else the merge-base
with `origin/HEAD`, else `HEAD`) and no ADR added in the same change names that manifest by its whole path.
There is no baseline. Its env file holds `INCLUDE` and `EXCLUDE` (git pathspecs limiting the manifests; empty
means every manifest outside `node_modules`). The manifests read are `package.json`, `pyproject.toml`,
`pom.xml` and `build.gradle`/`build.gradle.kts`; `requirements*.txt`, `Cargo.toml`, `go.mod` and Gradle version
catalogs are not read. A version change, a removal, a dependency already present in another section of the
same manifest, Maven `dependencyManagement`, plugin dependencies and Gradle `project()` are not new
dependencies. `measure.sh deps [pathspec...]` prints the direct dependencies per manifest.

## Enforcement level: `mandatory` or `ratchet` (D43)

`ENFORCEMENT_LEVEL=mandatory|ratchet` is in every rule env file; absent means `ratchet`. It is a property
of the rule and is distinct from `ENFORCEMENT=`, which names the sensor (or `inferential`); keep both.
Any other value is read as `ratchet` by every tool, and `harness-check` warns (`mandatory-unsensored`).

| | `ratchet` (default) | `mandatory` |
| --- | --- | --- |
| Legacy violations | a TSV baseline that can only shrink | no baseline; the `EXCEPTIONS` list below |
| Sensor | optional (`ENFORCEMENT=inferential` is allowed) | a computational sensor is required |
| Loosening | an ADR added in the same change that names the file | only a superseding ADR |

```sh
ENFORCEMENT=sensor:file-size
ENFORCEMENT_LEVEL=mandatory
EXCEPTIONS='src/legacy/Big.java 2027-03-01
src/legacy/Other.java 2026-12-15'
```

- **`EXCEPTIONS`** is a quoted multi-line value, one `<path> <YYYY-MM-DD>` per line (the date is the last word,
  so a path may contain spaces). The rule's sensor (`file-size`, `folder-layout`, `test-presence`,
  `code-language`, `architecture-grep`) skips a listed path through its deadline day and fails it from the next
  day, saying `exception expired on <date>`. A mandatory rule's sensor ignores `.agents/baselines/<id>.tsv`:
  there is no baseline. A line without a valid date excepts nothing. `ratchet` rules ignore `EXCEPTIONS`.
- **`harness-check`** warns `mandatory-unsensored` (a mandatory rule with `ENFORCEMENT=inferential`, no
  `sensor:<id>`, or a sensor with no file under `scripts/sensors/`) and `exception-expired` (an exception past its date).
- **`guard`** rejects every loosening of a mandatory rule even when an ADR names the file. Loosening means
  everything `guard` already rejects (above), plus: an `EXCEPTIONS` line added, a deadline moved later, a TSV
  baseline row for the rule's sensor appearing or growing, `ENFORCEMENT_LEVEL` going `mandatory` to `ratchet`
  or being deleted, and the rule's env file or sensor being deleted or disabled. Tightening passes: removing an
  exception, moving a deadline earlier, ratchet to mandatory.
- **Superseding ADR.** The one way through is an ADR added in the same change that names the file and has a line
  `Supersedes: <path>` (for example `Supersedes: docs/adr/0003-file-size-limit.md`) pointing at an ADR that
  already exists in `adr_dir` at the base commit. The approval itself is CODEOWNERS plus branch protection on the
  `keel` check; keel cannot verify it locally, so `guard` checks the shape of the ADR only.
- **Protection.** `.agents/rules/*.env` is in the `harness` category of the consequence map
  (`contracts/consequence.md`): the PreToolUse hook denies edits outside an approved `rules` flow.
- **Order in `AGENTS.md`.** Mandatory rules come first in `## Rules`, each line starting `[mandatory]`.
- **No `constitution.md`.** Non-negotiable is a property of the rule. A principle without a sensor goes in
  `docs/architecture.md` under `## Principles` as `- <principle> → review:<owner>`; an existing Spec Kit
  `.specify/memory/constitution.md` is read by `rules` and each principle is linked to a rule or to such a line.
  A single document for audit is generated from the rules, never written by hand.
