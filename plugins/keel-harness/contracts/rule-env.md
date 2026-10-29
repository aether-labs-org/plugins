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
or a deleted env file as a loosening that needs an ADR in the same change.

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
