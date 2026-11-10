# second-brain v0.3 (simplification)

Status: active
Scope: plugins/second-brain/**, tests/python/**, tests/sb_*_test.sh, tests/fixtures/sb-eval/**, tests/fixtures/review-hash/**, docs/plans/2026-11-10-second-brain-v0.3.md, docs/specs/2026-10-31-second-brain-v0.2-design.md, docs/specs/2026-11-10-second-brain-v0.3-design.md, .claude-plugin/marketplace.json, README.md, .agents/bmax.yml, AGENTS.md

Full plan: `docs/plans/2026-11-10-second-brain-v0.3.md`. Spec: `docs/specs/2026-11-10-second-brain-v0.3-design.md`.
`.agents/bmax.yml` and `AGENTS.md` are protected: they change only in Task 0, after the human confirms.

## Acceptance

- [ ] AC1 four hooks; guard, review, doctor, index, log and the companion are gone
- [ ] AC2 `lib/sb` <= 2,500 lines; five skills <= 12,000 characters
- [ ] AC3 `sb init` default and `--folders`, idempotent, marker last
- [ ] AC4 outside-session commit apart from the session commit; no git on clear/compact
- [ ] AC5 pull-only sync; no code path runs `git push`
- [ ] AC6 second `sb source` of the same source is `seen`
- [ ] AC7 external sources: no copy, `moved_from`, `--relink`, `changed`, legacy citations
- [ ] AC8 minimal note lints clean; legacy keys ignored
- [ ] AC9 retrieval gate unchanged
- [ ] AC10 template <= 3,200 characters; status line <= 300
- [ ] AC11 `claude plugin validate --strict`; no marketplace dependencies
- [ ] AC12 evals run once on 0.3.0; recall on/off decided
- [ ] AC13 schema 2 vault: `sb` exits 2, SessionStart one line
- [ ] AC14 `make check` and both gates
- [ ] AC15 launcher: python, python3, broken python, neither; p95 <= 80 ms
- [ ] AC16 `ingest-gap` and `no-padding` pass 2 of 3 runs
