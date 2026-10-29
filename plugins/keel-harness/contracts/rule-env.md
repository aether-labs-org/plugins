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
PLAN=.agents/plans/2026-10-20-file-size.md        # optional; local, may be absent on other clones
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
