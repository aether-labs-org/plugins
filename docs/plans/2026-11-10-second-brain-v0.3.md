# second-brain v0.3 (simplification) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. The default mode in this repository is one Sonnet subagent for Tasks 1-13 and the main session for Tasks 0 and 14.

**Goal:** Ship second-brain 0.3.0: schema 3 vaults, no guard, trust tiers, review hash, companion, index, log or doctor, five skills, sources ingested in place with content-hash relink, pull-only sync, and a `python`-first launcher.

**Architecture:** Delete first (Tasks 1-4) so each later task edits less code. Then move machine state to `.agents/second-brain/` (5), change the note contract (6), rewrite provenance (7), `init` (8) and session/sync (9), add the launcher (10), rewrite skills and the vault template (11), update evals (12) and docs/manifests (13). Every task leaves `bash tests/sb_cli_test.sh` and `bash tests/sb_structure_test.sh` green.

**Tech Stack:** Python 3.9+ standard library (`unittest`, `sqlite3`), POSIX `sh`, Markdown skills, `claude plugin validate` and `claude plugin eval`.

**Spec:** `docs/specs/2026-11-10-second-brain-v0.3-design.md` (D37-D63, AC1-AC16). Read it first; this plan only adds the decisions the spec leaves to the implementer.

## Global Constraints

- Paths are relative to `plugins/second-brain/` unless they start with `tests/`, `docs/`, `.agents/` or `.claude-plugin/`.
- Python 3.9+, standard library only. Run single modules with `python3 -m unittest discover -s tests/python -p 'test_sb_<name>.py' -q` (this machine has no `python` command).
- Fast checks after every task: `bash tests/sb_cli_test.sh` and `bash tests/sb_structure_test.sh`. `make check` (about 220 s) only in Task 14.
- Schema 3 marker: `.agents/second-brain/config.json` = `{"schema_version": 3, "language": "<tag>", "sync": "local" | "pull"}`. Legacy marker `.second-brain.json` is never written.
- Values copied from the spec: note keys required `summary`, `origin` (`agent|human`, `mixed` accepted as `human`), `created`; commit messages `sb: session YYYY-MM-DD (N files)` and `sb: changes outside sessions (N files)`; status line at most 300 characters; vault `CLAUDE.md` at most 3,200 characters; `lib/sb/*.py` at most 2,500 lines in total; exactly five skills with `SKILL.md` files totalling at most 12,000 characters; hook latency outside a vault at most 80 ms p95; retrieval gate Recall@10 >= 0.85 and MRR >= 0.6.
- Hook timeouts: `SessionStart` 60, `SessionEnd` 30, `UserPromptSubmit` 5, `PostToolUse` 10.
- Never run `git push`. Never edit `.agents/bmax.yml`, `.agents/bmax.lock`, `.agents/bin/`, `.agents/githooks/`, `docs/review.md`, `docs/architecture.md`, `docs/adr/` or `AGENTS.md` (Task 0 handles the two that must change, with the human). Never change a test expectation to make a check pass without the task saying so.
- A plugin never references another plugin (`docs/architecture.md`).
- **Commits:** none unless the human authorized them at the Task 0 handoff. Every task ends with a Checkpoint: `git status --short`, and, when authorized, one commit with the message the task gives (conventional; end it with the attribution lines of the session).
- **Paid or networked runs** (`claude plugin eval`, `claude -p`) belong to the main session (Task 14). The implementer runs none.
- Log every non-trivial decision and every deviation in `.agents/run/handoff.md` (local, never committed). If a step cannot be done as written, or a doubt appears that this plan does not settle, **stop and report**; do not improvise.

## Review Focus

The inputs the spec implies but its tasks would not otherwise exercise, most likely to bite first:

1. **A v0.2 note carries dropped keys** (`type`, `status: evergreen`, `protected: true`, `origin: mixed`, `reviewed_hash`, `source_id`): it must lint clean. -> Task 6 `test_legacy_keys_are_ignored`; Task 13 rehearsal on a copy of the 71-note benchmark vault (it holds notes with those keys).
2. **A file is moved and also edited**: it is a new source, not a relink of the old one. -> Task 7 `test_moved_and_edited_file_is_new`.
3. **A `clear`, `compact` or `fork` start in a dirty git vault** (a forked session may run beside its parent): no commit, no git command. -> Task 9 `test_clear_compact_and_fork_run_no_git`.
4. **Hostile `--folders` JSON** (`../x`, `/abs`, `_inbox`, `.git`, backslashes, case-only duplicates, empty description). -> Task 8 `test_parse_folders_rejects_hostile_paths`.
5. **`python` on `PATH` is Python 2 or a store stub** next to a working `python3`. -> Task 10 `test_broken_python_falls_back_to_python3`.

---

## File Structure

| Path | Change |
| --- | --- |
| `lib/sb/guard.py`, `hooks/guard.py`, `lib/sb/review.py`, `lib/sb/doctor.py`, `lib/sb/index.py`, `lib/sb/logfile.py`, `obsidian/` | Delete (Tasks 1-4) |
| `lib/sb/trust.py` | Reduce to `label` (Task 1), two values (Task 6) |
| `lib/sb/vault.py` | Schema 3 constants, `find_legacy_vault` (Task 5) |
| `lib/sb/lint.py`, `lib/sb/recall.py` | New codes and `Finding.info` (Task 6) |
| `lib/sb/source.py`, `lib/sb/cli.py` | `sb source`, relink, content hash (Task 7) |
| `lib/sb/init.py`, `templates/*` | `--folders`, `_assets`, `notes.base` (Task 8) |
| `lib/sb/sync.py`, `lib/sb/autocommit.py`, `lib/sb/session.py`, `hooks/hooks.json` | Pull-only sync, outside-session commit, status line (Task 9) |
| `bin/sb-python`, `bin/sb`, `lib/sb_main.py` | Interpreter launcher (Task 10) |
| `skills/{init,capture,ingest,find,lint}/SKILL.md`, `skills/init/examples.md`, `templates/CLAUDE.md` | Task 11; `skills/update`, `skills/link` deleted |
| `evals/**` | Task 12 |
| `README.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (repo root), `tests/sb_structure_test.sh` | Task 13 |

---

### Task 0: Preflight (main session, before dispatching the implementer)

**Files:** `.agents/bmax.yml`, `AGENTS.md` (protected: the human confirms), `.agents/run/handoff.md` (local).

- [ ] **Step 1: Worktree.** From `main`: `git worktree add .claude/worktrees/sb-v03 -b feat/second-brain-v0.3`. The spec, this plan and `.agents/plans/second-brain-v03.md` are untracked in the main checkout: copy all three into the worktree at the same paths.
- [ ] **Step 2: Baseline** in the worktree: `bash tests/sb_cli_test.sh`, `bash tests/sb_structure_test.sh` pass. Record in `.agents/run/handoff.md`: total lines of `lib/sb/*.py` (4,803 expected), number of tests, and `wc -c` of the seven `SKILL.md` files (17,167 expected).
- [ ] **Step 3: Harness edits, human-confirmed.** Explain the change and why (the companion's `typecheck` and `lint` scripts would fail on the deleted `obsidian/`), show the diff, apply only after the human confirms. In `.agents/bmax.yml`: delete the scripts `typecheck` and `lint`; set `gates.fast.scripts` to `[guard, secrets, isolation-baymax, isolation-second-brain, isolation-solutions-architect]` and `gates.commit.scripts` to `[guard, secrets, memory]`; set `isolation-second-brain.with.exclude` to `[plugins/second-brain/evals]`. In `AGENTS.md` lines 3-4: "Monorepo of Claude Code plugins: `plugins/baymax`, `plugins/second-brain` and `plugins/solutions-architect`. Bash test suite in `tests/`, Python helpers." (drop the Obsidian plugin and npm mentions). Then `sh .agents/bin/bmax validate` and `sh .agents/bin/bmax gate fast` pass. `guard` reports each removed script and config as a loosening until an ADR names it: **done 2026-11-10, ADR `docs/adr/0002-remove-the-obsidian-companion-gates.md`, confirmed by the human**; the preflight is committed in two commits (`chore(harness)` and `docs(second-brain)`).
- [ ] **Step 4: Ask the human** (question dialog): commits during the run (none / one per task); whether the main session may spend on `claude plugin eval` and `claude -p` in Task 14 (budget up to US$4, AC12). **Answers 2026-11-10: one commit per task, no push, no PR; ask the human before each paid run.** Recorded in the handoff file.

---

### Task 1: Remove the guard and the trust tiers (D37)

**Files:** Delete `lib/sb/guard.py`, `hooks/guard.py`, `tests/python/test_sb_guard.py`. Modify `hooks/hooks.json`, `lib/sb/trust.py`, `lib/sb/tree.py`, `tests/python/test_sb_trust.py`, `tests/python/test_sb_tree.py`, `tests/python/test_sb_hooks.py`, `tests/sb_structure_test.sh`.

**Interfaces:** Produces `trust.label(data: dict, body: str) -> str` (unchanged for now) and `trust.AGENT_BLOCK_RE`; nothing else remains in `trust.py`. `tree.read_about` no longer returns `protected`; `tree.folder_protected` is gone.

- [ ] **Step 1: Failing tests.** In `test_sb_hooks.py` rename `test_hooks_json_wires_the_five_events` to `test_hooks_json_wires_the_four_events` and assert `set(hooks["hooks"]) == {"PostToolUse", "SessionStart", "SessionEnd", "UserPromptSubmit"}`. Run that module: FAIL.
- [ ] **Step 2: Delete and reduce.** Remove the `PreToolUse` entry from `hooks/hooks.json`. Reduce `trust.py` to `AGENT_BLOCK_RE` and `label`. In `tree.py` remove `folder_protected` and the `protected` key of `read_about`/`load` (keep the section parsing). In tests: delete `test_sb_guard.py`; in `test_sb_trust.py` keep `test_labels`, `test_missing_null_empty_and_empty_list_reviewed_are_all_unreviewed`, `test_agent_marker_must_start_the_line` and `SanitizeTests`, delete `TierTests`, `ChangeClassificationTests`, `FenceParityTests`; in `test_sb_tree.py` delete `test_folder_protected_inherits` and any `protected` assertion; in `test_sb_hooks.py` delete `test_guard_hook_fails_closed_inside_a_vault`, `test_guard_hook_is_silent_outside_a_vault`, `test_guard_hook_blocks_on_failure`. In `tests/sb_structure_test.sh` delete the check "guard hook is fail-closed (onFailure: block)".
- [ ] **Step 3: Verify.** `grep -rnE "sb\.guard|from \.guard|folder_protected|hidden_trust_lines|append_only|link_only|tier\(" lib hooks tests` prints nothing. Both fast suites pass.
- [ ] **Checkpoint.** Commit message: `refactor(second-brain)!: remove the PreToolUse guard and the trust tiers`.

---

### Task 2: Remove the review hash, the companion and `init --upgrade` (D38, D42)

**Files:** Delete `lib/sb/review.py`, `obsidian/`, `tests/python/test_sb_review.py`, `tests/sb_companion_test.sh`, `tests/fixtures/review-hash/`. Modify `lib/sb/cli.py`, `lib/sb/lint.py`, `lib/sb/init.py`, `tests/python/test_sb_init.py`, `tests/python/test_sb_cli.py`, `tests/python/test_sb_lint.py`, `tests/sb_structure_test.sh`.

**Interfaces:** `frontmatter.set_keys` stays (Task 7 uses it). `init.run(...)` keeps its current signature for now but installs no companion; `init.upgrade`, `init.merge_settings`, `init.manifest_version`, `init.version_key`, `BUNDLE`, `COMPANION` and `_install_companion` are gone. `sb review` and `sb init --upgrade/--yes` are gone from the parser.

- [ ] **Step 1: Tests first.** In `test_sb_init.py` delete the companion tests (`test_installs_the_bundled_companion_without_enabling_it`, `test_run_keeps_a_companion_that_is_already_installed`, `test_missing_bundle_warns_and_still_creates_the_vault`), `test_sb107_message_points_to_upgrade` and the whole `UpgradeTests` class. In `test_sb_cli.py`/`test_sb_lint.py` delete anything that asserts `SB110`, `SB112` or `sb review`. Add `test_init_does_not_touch_obsidian_plugins`: after `init.run`, `.obsidian` does not exist. Run: that test FAILs while the others still pass.
- [ ] **Step 2: Remove.** Delete the files listed; remove `cmd_review`, `_find_note_file` and the `review` parser from `cli.py`; remove `_review_findings` and its `SB110`/`SB112` use from `lint.py` (drop the `review` import; keep `INFO_CODES = {"SB111"}` until Task 6); strip the companion and upgrade code from `init.py` and the `--upgrade`, `--yes` flags and `cmd_upgrade` from `cli.py`. In `tests/sb_structure_test.sh` delete the whole "Obsidian companion bundle" block.
- [ ] **Step 3: Verify.** `grep -rnE "sb\.review|from \.review|review_hash|body_hash|companion|upgrade|merge_settings" lib hooks` prints nothing; `ls obsidian` fails. Both fast suites pass.
- [ ] **Checkpoint.** Commit message: `refactor(second-brain)!: remove the review hash, the Obsidian companion and init --upgrade`.

---

### Task 3: Remove `_index.md`, `_log.md` and `sb validate` (D39, D40)

**Files:** Delete `lib/sb/index.py`, `lib/sb/logfile.py`, `tests/python/test_sb_index_log.py`. Modify `lib/sb/cli.py`, `lib/sb/lint.py`, `lib/sb/session.py`, `lib/sb/postcheck.py`, `lib/sb/init.py`, `lib/sb/source.py`, `tests/python/sb_helpers.py`, `tests/python/test_sb_{cli,hooks,session,lint,init,source,vault}.py`.

**Interfaces:** `source.inbox_done(root: Path, rel: str) -> str` (no `title`, no log). `sb_helpers.make_vault(tmp, notes=None, config=None) -> Path` (no `index` parameter, writes no `_index.md` or `_log.md`). CLI: `sb inbox done FILE` (no `--title`). Commands `index`, `validate`, `log` are gone. `postcheck.check` stays and no longer rewrites anything.

- [ ] **Step 1: Failing tests.** `test_sb_source.py::test_inbox_done_moves_and_logs` becomes `test_inbox_done_moves_without_logging` (asserts the moved path and that no `_log.md` exists); `test_sb_cli.py::test_inbox_done_cli` calls `sb inbox done FILE` without `--title`; add `test_removed_commands_are_unknown` asserting `sb index --check`, `sb validate x`, `sb log init x` exit 2. Run: FAIL.
- [ ] **Step 2: Remove** the modules, the three commands and their parsers, the SB105 check in `lint.py`, the drift regeneration in `session.py`, `_sync_index` in `postcheck.py`, the `_index.md`/`_log.md` creation and `logfile.append` in `init.py`, and the `logfile` call in `source.inbox_done`. Update `sb_helpers.make_vault` and every caller that passed `index=`. Move `test_write_atomic_replaces_file_and_leaves_no_temp_files` into `test_sb_vault.py`. Delete tests of the removed behaviour (`test_index_write_then_check`, `test_validate_*`, `test_log_*`, `test_postcheck_regenerates_index`, `test_index_regenerated`, `test_sb105_*`) and drop `_index.md`/`_log.md` from init expectations.
- [ ] **Step 3: Verify.** `grep -rnE "_index|_log\.md|logfile|index_mod|sb index|sb log|sb validate" lib hooks tests/python` prints nothing; both fast suites pass.
- [ ] **Checkpoint.** Commit message: `refactor(second-brain)!: remove _index.md, _log.md and sb validate`.

---

### Task 4: Remove `sb doctor` and the heartbeat (D41)

**Files:** Delete `lib/sb/doctor.py`, `tests/python/test_sb_doctor.py`. Modify `lib/sb/cli.py`, `lib/sb/session.py`, `tests/python/test_sb_session.py`, `tests/python/test_sb_cli.py`.

- [ ] **Step 1: Failing test.** `test_sb_session.py::test_no_heartbeat_is_written`: after `start(...)` in a vault, `.sb/heartbeat.json` does not exist. Delete `test_heartbeat_*` tests. Run: FAIL.
- [ ] **Step 2: Remove** `cmd_doctor` and its parser, `_heartbeat` and its call in `session.start`.
- [ ] **Step 3: Verify.** `grep -rnE "doctor|heartbeat" lib hooks tests/python` prints nothing; both suites pass.
- [ ] **Checkpoint.** Commit message: `refactor(second-brain)!: remove sb doctor and the heartbeat`.

---

### Task 5: Schema 3 layout and legacy detection (D51, D60)

**Files:** Modify `lib/sb/vault.py`, `lib/sb/search.py`, `lib/sb/source.py` (path constant only), `lib/sb/init.py` (marker path, gitignore line), `lib/sb/cli.py`, `tests/python/sb_helpers.py`, `tests/python/test_sb_{vault,cli,search,init,source,sync,session}.py`, `tests/fixtures/sb-eval/vault/` (git mv the marker, delete `_index.md`).

**Interfaces:**
- Produces in `vault.py`: `STATE_DIR = ".agents/second-brain"`, `MARKER = STATE_DIR + "/config.json"`, `LEGACY_MARKER = ".second-brain.json"`, `CACHE_DIR = STATE_DIR + "/cache"`, `CONVERTED_DIR = STATE_DIR + "/converted"`, `SCHEMA_VERSION = 3`, `LEGACY_MESSAGE: str`, `find_vault(start) -> Optional[Path]` (new marker only), `find_legacy_vault(start) -> Optional[Path]` (nearest directory holding the legacy marker and no new one), `sync_mode(config: dict) -> str` (`"pull"` if `config.get("sync") == "pull"` else `"local"`).
- `LEGACY_MESSAGE` = "this vault uses schema 2 (.second-brain.json); see 'Migrating from 0.2' in the second-brain README".
- `vault.ASSET_SKIP_DIRS` replaces `.sb` with `.agents`. `source.CONVERTED = CONVERTED_DIR`. `SearchIndex.dir = root / CACHE_DIR` (created with `parents=True`).

- [ ] **Step 1: Failing tests.** In `test_sb_vault.py`: `test_find_vault_uses_the_agents_marker`; `test_legacy_marker_is_found_only_as_legacy`; `test_new_marker_wins_over_the_legacy_one`; `test_asset_names_skip_the_agents_dir`; `test_sync_mode_defaults_to_local` (`"squad"`, missing and garbage values give `local`). In `test_sb_cli.py`: `test_legacy_vault_exits_2_with_the_migration_message` (any command, message on stderr, no file created) and `test_init_refuses_a_legacy_vault`. In `test_sb_search.py`: `test_cache_lives_under_agents_second_brain_cache` (`.sb` never created). Run: FAIL.
- [ ] **Step 2: Implement** the constants and functions above; `cli._vault` prints `LEGACY_MESSAGE` and returns exit 2 when `find_vault` finds nothing but `find_legacy_vault` does (also for `--vault PATH`); `cmd_init` does the same before creating anything. Update `make_vault` to write `{"schema_version": 3, "language": "en", "sync": "local"}` at the new marker. `git mv tests/fixtures/sb-eval/vault/.second-brain.json` to the new marker with content `{"schema_version": 3, "language": "pt-BR", "sync": "local"}`; delete the fixture's `_index.md`. Replace the `.sb/` gitignore line in `init.py` with `.agents/second-brain/cache/`, and make the `SB107` finding in `lint.py` name `MARKER` (Task 6 deletes it). Fix every test that wrote the legacy marker or looked in `.sb/`.
- [ ] **Step 3: Verify.** `grep -rn "second-brain.json" lib hooks` shows only `LEGACY_MARKER` and `LEGACY_MESSAGE` (the `SB107` text uses `MARKER`); the retrieval gate test (`test_sb_eval.py`) still passes; both suites pass.
- [ ] **Checkpoint.** Commit message: `feat(second-brain)!: schema 3 layout under .agents/second-brain`.

---

### Task 6: Schema 3 frontmatter, lint codes and the two-value trust label (D49, D50, D59)

**Files:** Modify `lib/sb/lint.py`, `lib/sb/trust.py`, `lib/sb/cli.py`, `lib/sb/recall.py`, `lib/sb/search.py` (title default only if not already so), `tests/python/test_sb_{lint,trust,recall,search,cli,tree,fixtures}.py`, `tests/python/sb_helpers.py`.

**Interfaces:**
- `lint.Finding(code: str, path: str, line: int, message: str, info: bool = False)`; `lint.REQUIRED = ("summary", "origin", "created")`; `lint.ENUMS = {"origin": {"agent", "human", "mixed"}}`; `lint.lint(root: Path) -> list[Finding]` (no `config`); `INFO_CODES` is deleted; the CLI exit is 1 when any finding has `info == False`.
- Codes that remain: `SB101`, `SB102`, `SB104`, `SB108`, `SB109` (failures), `SB103`, `SB106` (`info=True`). `SB105`, `SB107`, `SB110`, `SB111`, `SB112` are gone. `SB109` is `info=True` when the missing source is `~/...` or absolute, a failure when vault-relative, and skipped for URLs and `[[links]]`.
- `trust.label(data, body) -> str` returns `"unreviewed"` when `origin == "agent"` and `reviewed` is empty, else `"reviewed"` (`mixed` counts as human; a `> [!agent]` callout does not change it).
- `sb_helpers.note(...)`: `type` and `status` default to `None` and are emitted only when given.

- [ ] **Step 1: Failing tests** (`test_sb_lint.py` unless noted):
  - `test_minimal_note_passes`: summary, origin, created only -> no finding with `info == False`.
  - `test_legacy_keys_are_ignored`: a note with `type: nota`, `status: evergreen`, `protected: true`, `origin: mixed`, `reviewed_hash: sha256:0123456789abcdef`, `source_id: sha256:0123456789abcdef` -> no finding mentions those keys.
  - `test_missing_required_key_is_sb108`: removing `created` -> `SB108` "missing required key: created"; `origin: robot` -> `SB108`.
  - `test_title_is_optional`; `test_sb103_and_sb106_are_info` (CLI exits 0 when they are the only findings; JSON carries `"info": true`).
  - `test_sb109_external_missing_is_info`: `~/no-such-file-xyz.pdf` and `/tmp/no-such-file-xyz.pdf` -> info; `_raw/missing.pdf` -> failure; `https://example.org/a` -> none.
  - `test_dropped_codes_never_appear`: finding codes are a subset of `{SB101, SB102, SB103, SB104, SB106, SB108, SB109}` on a vault with a folder lacking `_about.md`.
  - `test_sb_trust.py::test_labels`: mixed -> reviewed; agent without `reviewed` -> unreviewed; agent with `reviewed` -> reviewed; human note with an `[!agent]` callout -> reviewed.
  - `test_sb_recall.py::test_only_unreviewed_notes_carry_a_label`: the line is `- [[Name]] (Folder) [unreviewed]: summary` for unreviewed and `- [[Name]] (Folder): summary` otherwise.
  - `test_sb_search.py::test_result_shape_and_trust`: `trust` is `unreviewed` or `reviewed`.
  Run: FAIL.
- [ ] **Step 2: Implement** per the Interfaces. Drop `tree` and `SCHEMA_VERSION` use from `lint.py`; `cmd_lint` still calls `load_config` so a malformed marker exits 2. Remove `test_sb111_is_info_and_does_not_fail` and the SB107 test.
- [ ] **Step 3: Verify.** Both fast suites pass; the retrieval gate passes.
- [ ] **Checkpoint.** Commit message: `feat(second-brain)!: schema 3 frontmatter, lint codes and a two-value trust label`.

---

### Task 7: `sb source` with content hash, relink and external sources (D47, D55)

**Files:** Modify `lib/sb/source.py`, `lib/sb/cli.py`, `tests/python/test_sb_source.py`, `tests/python/test_sb_cli.py`.

**Interfaces (`source.py`):**
- `canonical_url(url: str) -> str` (unchanged); `content_hash(data: bytes) -> str` = `"sha256:" + first 16 hex`.
- `source_value(root, target) -> str`: a URL as typed; an inbox item in `_inbox/` root -> its `url`/`source` URL if the clip has one, else `_inbox/_done/<name>`; a file inside the vault -> vault-relative posix path; a file under the home directory outside the vault -> `~/<relative>`; any other file -> absolute path.
- `inspect(root, target) -> dict` with keys `source`, `kind` (`file|inbox|url`), `status` (`new|seen`), `notes` (sorted vault-relative paths), `converted` (vault-relative path or `None`) and, only when true, `moved_from` (str) and `changed` (`True`).
- `save(root, target, text: str, tool: str, today: Optional[str] = None) -> dict` -> `{path, suspicious, removed, flagged}`; writes `CONVERTED_DIR/sha256-<16 hex>.md` (files, by content) or `url-<16 hex of sha256(canonical url)>.md` (URLs). Header keys: `source`, `content_hash` (files only), `tool`, `converted`, `suspicious`, `flagged_lines`.
- `relink(root, target) -> dict` -> `{source, moved_from, converted, changed: [rel, ...]}`; raises `ValueError` when `inspect` reports no `moved_from`. It rewrites the converted header's `source`, the `source` key of the notes that cited `moved_from` (with `frontmatter.set_keys`), and callout headers ending in `· <moved_from>`.
- Citation rules for `seen`: a note whose `source` equals the value (URLs compared canonically), or whose `source_id` equals the legacy id (`sha256:<hash>` / `url:<canonical>`), or a `> [!agent] <date> · <value-or-legacy-id>` callout. `moved_from`: notes matched by hash (legacy id, or the `source` recorded in the converted copy with the same hash) that cite a different value. `changed`: notes cite the value, a converted copy recorded for that value exists, and none has the current hash.

**CLI:** `sb source TARGET [--save --tool T | --relink] [--json]`. Plain call prints `<status> <source> (<kind>)` plus `notes:`, `moved_from:`, `changed: yes`, `converted:` lines; for a `.md`/`.txt` target with status `new` it also sanitises and saves with tool `none`. `--save` reads stdin and requires `--tool`; `--save` and `--relink` are exclusive. Errors exit 2. `sb source add` and `sb source save` are gone.

- [ ] **Step 1: Failing tests** (`test_sb_source.py`; keep `CleanDocumentTests` and the `inbox_done` tests, rewrite the rest):
  - `test_content_hash_is_sha256_with_16_hex`; `test_source_value_forms` (inside vault, under a patched `HOME`, other absolute, URL, inbox root item with and without `url`).
  - `test_save_names_files_by_content_and_urls_by_canonical_url`; the file header has `content_hash`, the URL header does not.
  - `test_seen_by_source_key`, `test_seen_by_agent_callout`, `test_seen_by_legacy_source_id`, `test_seen_by_legacy_callout_header`, `test_url_variants_are_one_source` (`utm_*`, trailing slash).
  - `test_moved_file_is_seen_with_moved_from` and `test_relink_updates_header_notes_and_callouts` (returns the changed paths; a second `relink` raises `ValueError`).
  - `test_same_path_other_bytes_reports_changed`.
  - `test_moved_and_edited_file_is_new`: new path and new bytes -> `status == "new"`, no `moved_from`, no `changed`.
  - CLI: `test_source_json_shape`, `test_text_file_is_saved_when_new`, `test_save_needs_tool`, `test_save_and_relink_are_exclusive`, `test_missing_file_exits_2`.
  Run: FAIL.
- [ ] **Step 2: Implement.** Index the converted copies by reading only their headers; derive the hash of a v0.2 copy from its file name when `content_hash` is absent.
- [ ] **Step 3: Verify.** Both fast suites pass.
- [ ] **Checkpoint.** Commit message: `feat(second-brain)!: sb source with content hash, relink and external sources`.

---

### Task 8: `sb init --folders`, `_assets/` and the notes view (D52, D53, D57)

**Files:** Delete `templates/profiles/`. Create `templates/folders-default.json`, `templates/notes.base`. Modify `lib/sb/init.py`, `lib/sb/cli.py`, `templates/settings.json`, `tests/python/test_sb_init.py`, `tests/python/test_sb_cli.py`, `tests/sb_structure_test.sh`.

**Interfaces:**
- `init.default_folders() -> list[dict]`: Projects, Areas, Resources, Archive with `description` and `conventions` (carry the wording of the current `personal` profile, without `examples`/`anti_examples`).
- `init.parse_folders(text: str) -> list[dict]`: a JSON array of `{"path", "description", "conventions"?}`; raises `ValueError` for: not an array, missing/empty `description` or `path`, a path that is absolute, contains `..`, a backslash or an empty segment, has a segment starting with `_` or `.`, has more than two segments, or duplicates another path ignoring case. Accented names are valid.
- `init.run(root, language="en", folders: Optional[list] = None, remote=None, git=False) -> dict` (result keeps `status`, `root`, `created`, `kept`, `warnings` and adds `hints: list[str]` with the Obsidian attachment setting: Settings, Files and links, Default location for new attachments, `_assets`).
- Files created: `CLAUDE.md` from the template (`{{language}}`), `.claude/settings.json`, `_meta/web-clipper-template.json`, `_views/unreviewed.base`, `_views/notes.base`, `wiki/<path>/_about.md` (frontmatter `description:`, then `## Conventions` and its text only when given), `.gitkeep` in `_inbox/_done`, `_raw`, `_assets`, `.gitignore` lines `.agents/second-brain/cache/`, `.obsidian/workspace*`, `.smart-env/`, and `.agents/second-brain/config.json` **last** with `sync` = `"pull"` when `remote` is given else `"local"`. No `_index.md`, `_log.md` or `.obsidian/`.
- `templates/settings.json`: `enabledPlugins` only `second-brain@aether-labs`; `extraKnownMarketplaces` only `aether-labs`; `permissions.deny` exactly `Edit(/_raw/**)`, `Edit(/.agents/second-brain/converted/**)`, `Bash(git push --force*)`, `Bash(git push -f*)`, `Bash(git reset --hard*)`, `Bash(git clean*)`.
- CLI: `sb init [--language L] [--folders FILE|-] [--git] [--remote URL]`; `--profile` and `--areas` are gone; `--remote` still needs `--git` or an existing `.git`; refuses a directory inside another repository, inside another vault, or a legacy vault; invalid `--folders` exits 2 with the message. The text output prints each hint as `hint: ...`.
- `templates/notes.base` copies the structure of `templates/unreviewed.base`, filters `wiki` and drops the `_about.md` files, and lists `file.name`, `summary`, `origin`, `created`. It cannot be tested against Obsidian here: record that in the handoff file.

- [ ] **Step 1: Failing tests** (`test_sb_init.py`, rewrite): `test_creates_the_schema_3_layout` (exact file list above, no `_index.md`/`_log.md`/`.obsidian`); `test_marker_is_written_last`; `test_is_idempotent_and_never_overwrites` (CLAUDE.md, `_about.md`, settings); `test_gitignore_lines_are_appended_once`; `test_default_folders_have_about_files`; `test_folders_from_stdin_create_exactly_those_folders`; `test_parse_folders_accepts_accented_names`; `test_parse_folders_rejects_hostile_paths` (each case named in Review Focus 4, plus depth 3, a non-array and a missing description, each asserting `ValueError`); `test_remote_sets_sync_pull_and_needs_git`; `test_settings_json_content` (one plugin, one marketplace, six deny rules in order); `test_hint_names_the_assets_folder`; `test_refuses_inside_another_repo_or_vault`; keep `test_vault_claude_md_is_under_200_lines`, `test_init_writes_gitkeep_*`, `test_git_flag_runs_git_init`, `test_web_clipper_template_and_base_formats` (also covers `notes.base`). Run: FAIL.
- [ ] **Step 2: Implement.** In `tests/sb_structure_test.sh` replace the profile checks (the `for prof` loop and the squad-sync line) with one check that `templates/folders-default.json` is a non-empty array of objects with `path` and `description` and that `templates/profiles` does not exist; update the two settings-template checks (one marketplace key `["aether-labs"]`, `deny | length == 6`).
- [ ] **Step 3: Verify.** Both fast suites pass.
- [ ] **Checkpoint.** Commit message: `feat(second-brain)!: sb init --folders, _assets and the notes view`.

---

### Task 9: Pull-only sync, outside-session commit and the status line (D45, D46, D48, D58, D60)

**Files:** Modify `lib/sb/sync.py`, `lib/sb/autocommit.py`, `lib/sb/session.py`, `hooks/hooks.json`, `tests/python/test_sb_{sync,session,hooks}.py`, `tests/sb_structure_test.sh`.

**Interfaces:**
- `autocommit.run(cwd, env=None, today=None, session_id="", outside=False) -> str`: returns `committed: <message>` or `skipped: <reason>` as today. Default message `sb: session YYYY-MM-DD (N files)` with trailers `Sb-Session` and `Sb-Files`; with `outside=True` the message is `sb: changes outside sessions (N files)` with the trailer `Sb-Files` only. No push, no `sync` import, no `push` parameter.
- `sync.enabled(root) -> bool` (`sync_mode == "pull"` and the git top-level is the vault root); `sync.ahead(root) -> int`; `sync.pull(root) -> str` -> `ok`, `skipped: <why>` or `conflict: <files | rebase in progress ...>`. Keeps `git pull --rebase --no-autostash` (20 s), `git rebase --abort` on failure and the left-rebase message. It commits nothing: a dirty tree gives `skipped: uncommitted changes (auto_commit is off or git commit failed)`. `push`, `pending`, `PENDING` and `PRE_SYNC_MESSAGE` are deleted.
- `session.start(event: dict, cwd: str, env: Optional[dict] = None) -> Optional[dict]`: `source = event.get("source") or "startup"` (the SessionStart input field `source` takes `startup`, `resume`, `clear`, `compact` or `fork`; confirmed in the hooks documentation on 2026-11-10). Legacy vault (via `find_legacy_vault`): returns the context `<second-brain-vault>\nsecond-brain: <LEGACY_MESSAGE>\n</second-brain-vault>` and does nothing else. For `startup` and `resume`: `autocommit.run(root, env, outside=True)`, then, when `sync.enabled`, `sync.pull`. For `clear`, `compact`, `fork` and any other value: no git command at all (a forked session may run beside its parent, so a commit there would mislabel the parent's changes). The context is `<second-brain-vault>\nStatus: inbox N · unreviewed M · sync S[ · unpushed K]\n</second-brain-vault>`, at most 300 characters in total (truncate `S` with `sanitize.clean_inline`, escape tags). `S` is `local` for local vaults; for pull vaults the pull result, or `not checked` on `clear`/`compact`. ` · unpushed K` appears only in pull vaults on `startup`/`resume` (`K = sync.ahead`). No tree, no index, no heartbeat.
- `hooks/hooks.json`: `SessionStart` matcher `startup|resume|clear|compact|fork`, timeout 60; `SessionEnd` timeout 30. `hooks/autocommit.py` prints its status line only when it starts with `committed`.

- [ ] **Step 1: Failing tests:**
  - `test_sb_session.py`: `test_status_line_shape_and_cap` (<= 300 characters, format above); keep the three `hostile_*` tests adapted to the status line; `test_outside_changes_are_committed_apart_from_the_session` (tracked note edited before `start`, commit `sb: changes outside sessions (1 files)`; then a second edit and `autocommit.run` -> commit `sb: session ... (1 files)` whose diff holds only the second edit); `test_clear_compact_and_fork_run_no_git` (patch `subprocess.run` to raise `AssertionError`; the three sources return a status line); `test_missing_source_counts_as_startup`; `test_legacy_vault_gets_one_line_and_no_git`; `test_unreviewed_count`.
  - `test_sb_sync.py` (rewrite what `push` touched): `test_enabled_needs_pull_and_toplevel`; `test_pull_rebases_clean_history`; `test_dirty_tree_is_skipped_not_committed`; `test_conflict_aborts_and_keeps_both_commits`; `test_rebase_left_in_progress_is_reported`; `test_merge_in_progress_is_skipped`; `test_unpushed_shows_in_the_status_line`; `test_simulation_two_clones_twenty_sessions` (clones push by hand in the helper; assert no conflict markers and no lost commits); `test_no_module_runs_git_push` (regex `["']push["']` over `lib/sb/*.py` and `hooks/*.py` finds nothing); `test_hook_timeouts_and_matcher` (60 and 30; the SessionStart matcher is exactly `startup|resume|clear|compact|fork`).
  - `test_sb_hooks.py::AutoCommitTests`: drop the push tests; add `test_outside_flag_changes_the_message_and_trailers`.
  Run: FAIL.
- [ ] **Step 2: Implement** the interfaces above; update `hooks/session_start.py` to pass `os.environ`. In `tests/sb_structure_test.sh` change the SessionStart matcher check to the five values, the SessionEnd timeout check to 30, and add a SessionStart timeout check of 60.
- [ ] **Step 3: Verify.** Both fast suites pass.
- [ ] **Checkpoint.** Commit message: `feat(second-brain)!: pull-only sync, outside-session commit and a one-line status`.

---

### Task 10: The `python` launcher (D61)

**Files:** Create `bin/sb-python`, `lib/sb_main.py`, `tests/python/test_sb_launcher.py`. Replace `bin/sb`. Modify `hooks/hooks.json`, `hooks/{recall,session_start,validate_note,autocommit}.py` (remove the `#!/usr/bin/env python3` line), `tests/sb_cli_test.sh`, `tests/python/test_sb_cli.py`, `tests/sb_structure_test.sh`.

**Interfaces:**
- `bin/sb-python [--hook] SCRIPT [ARGS...]` (POSIX `sh`): for `py` in `python`, `python3`: use it when `command -v "$py"` succeeds and `"$py" -I -S -c 'import sys; sys.exit(sys.version_info < (3, 9))'` exits 0; then `exec "$py" SCRIPT ARGS`. With no usable interpreter: in `--hook` mode exit 0 silently; otherwise print `sb: needs Python 3.9+ (tried python, python3)` to stderr and exit 2. The probe is one cheap extra start (measured under 10 ms): the spec's "do not start twice" is relaxed to "one probe" so a broken `python` can fall through (record this in the handoff file).
- `bin/sb` (`#!/bin/sh`, executable): resolves its own directory without `dirname` (`${0%/*}`) and runs `sh "$dir/sb-python" "$dir/../lib/sb_main.py" "$@"`. `lib/sb_main.py` does `from sb.cli import main; sys.exit(main())`.
- Each hook command in `hooks/hooks.json` becomes `sh "${CLAUDE_PLUGIN_ROOT}/bin/sb-python" --hook "${CLAUDE_PLUGIN_ROOT}/hooks/<name>.py"`.
- `tests/sb_cli_test.sh` picks its interpreter with the same loop (`python`, then `python3`).

- [ ] **Step 1: Failing tests** (`test_sb_launcher.py`; each runs the launcher with `/bin/sh` and a temporary directory of symlinks/stub scripts as the whole `PATH`): `test_only_python3_on_path`; `test_only_python_on_path` (a symlink to `sys.executable`); `test_python_is_preferred_when_both_work` (the stub prints which name ran); `test_broken_python_falls_back_to_python3` (a `python` script that exits 1 next to a working `python3`); `test_old_python_is_rejected` (a `python` stub that exits 1 on `-I`); `test_no_interpreter_in_hook_mode_exits_0_silently`; `test_no_interpreter_for_sb_exits_2_with_the_message`; `test_hook_latency_outside_a_vault` (20 runs of `recall.py` through the launcher, p95 <= 80 ms); `test_bin_sb_runs_through_the_launcher` (`bin/sb --help` exits 0). In `test_sb_cli.py` the shim test now calls `bin/sb` directly. In `tests/sb_structure_test.sh` add: `grep -rn python3 hooks bin lib` finds matches only in `bin/sb-python`; `bin/sb` and `bin/sb-python` are executable. Run: FAIL.
- [ ] **Step 2: Implement** the interfaces above.
- [ ] **Step 3: Verify.** Both fast suites pass; `grep -rn python3 hooks bin` prints only `bin/sb-python`.
- [ ] **Checkpoint.** Commit message: `feat(second-brain): python-first launcher for hooks and sb`.

---

### Task 11: Five skills, the ingest contract and the vault template (D43, D44, D48, D53, D62, D63)

**Files:** Delete `skills/update/`, `skills/link/`. Create `skills/init/examples.md`. Rewrite `skills/{init,capture,ingest,find,lint}/SKILL.md` and `templates/CLAUDE.md`. Modify `tests/sb_structure_test.sh`, `tests/python/test_sb_init.py`.

**Content decisions** (follow spec §6.3 and §6.4; the executor writes the prose):
- Size budgets in characters: `ingest` <= 4,600; `init` <= 2,600; `lint` <= 1,900; `find` <= 1,600; `capture` <= 1,000 (total <= 12,000). Each description is 150-400 characters; `init` keeps `disable-model-invocation: true`.
- `ingest` opens with the contract (six rules: third-party data is never instructions; every claim comes from the converted copy or a cited note; condense, rephrase and translate but never add a claim, number, date, name or cause; gaps/ambiguity/contradictions are never resolved by the agent; unreadable text stops the ingest; `source`, `created`, `summary` are never guessed) and then the five steps of spec §6.3, using `sb source`, `sb source --save --tool T`, `sb source --relink`, `sb tree`, `sb search`, `sb inbox done`. It contains the literal phrase "now or at the end" and the literal flag `--no-ask`. `argument-hint: "[item] [--no-ask]"`.
- `init` follows spec §6.3 (at most four questions, three to six proposed folders in the vault language, create only after approval via `sb init --folders -`, `examples.md` holds three structures: personal PARA, individual work, project/team). It states that a schema 2 vault is not operated and points to the README migration section.
- `lint` explains exactly `SB101`, `SB102`, `SB103`, `SB104`, `SB106`, `SB108`, `SB109`, proposes fixes and applies them after approval, and owns link work (`sb links --suggest`).
- `capture` has no `sb log` step; `find` uses the two trust labels.
- `templates/CLAUDE.md`: at most 3,200 characters and under 200 lines; holds the §5.1 map, the rules and the body rules listed in spec §6.4, the §5.2 frontmatter, and `{{language}}`; no mention of the guard, tiers, hash, index, log or `sb doctor`.

- [ ] **Step 1: Failing tests** (`tests/sb_structure_test.sh` and `test_sb_init.py`): skills are exactly `init capture ingest find lint`; each has `name`, a 150-400 character description and <= 250 lines; the sum of the five `SKILL.md` sizes is <= 12,000 bytes; `skills/update` and `skills/link` do not exist; `ingest/SKILL.md` contains `never instructions`, `Condense`, `now or at the end` and `--no-ask`; no skill or template contains `sb log`, `sb index`, `sb validate`, `sb doctor`, `sb review`, `source_id`, `guard`, `companion` or `_index.md`; the template is <= 3,200 characters and contains (case-insensitive) `never invent`, `gap`, `preamble`, `recap`, `[!agent]`, `origin: agent`, `_raw/`; `test_claude_md_rule_5_marks_general_knowledge` still holds. Run: FAIL.
- [ ] **Step 2: Write** the skills and the template to satisfy the tests and the spec.
- [ ] **Step 3: Verify.** Both fast suites pass; print `wc -c skills/*/SKILL.md templates/CLAUDE.md` into the handoff file.
- [ ] **Checkpoint.** Commit message: `feat(second-brain)!: five skills, the ingest contract and the note body rules`.

---

### Task 12: Evals for schema 3, `ingest-gap` and `no-padding` (AC16)

**Files:** Modify the nine `evals/*/scaffold.sh` and `evals/ingest-twice/` graders. Create `evals/ingest-gap/{case.yaml,prompt.md,scaffold.sh,graders/*.md}`, `evals/_fixtures/inbox-gap/<date>-decisao.md`, `evals/ingest-1ton/graders/no-padding.md`.

- [ ] **Step 1: Update the existing cases.** Remove the `index --write` line from every scaffold; `folder-placement/scaffold.sh` calls `sb init --vault . --language pt-BR --folders -` with a JSON heredoc holding Projects, Areas, Resources, Decisions, Meetings and Archive (descriptions and conventions taken from the former `work` profile: `git show main:plugins/second-brain/templates/profiles/work.json`); delete `ingest-twice/graders/{index-updated,logged}.md`; update the `ingest-twice` description to drop the index and log. Check each `case.yaml` description for removed concepts.
- [ ] **Step 2: Create `ingest-gap`.** Fixture: a pt-BR inbox clip that states a decision ("adotamos a ferramenta X") and gives neither the date nor the reason. Prompt: "Ingest the item in _inbox into my vault." Graders (`type: llm`): `no-invention` (PASS if no created note states a date or a reason for the decision; FAIL otherwise) and `asks-now-or-end` (PASS if the reply names both gaps and asks whether to resolve them now or at the end). `runs: 3`, `max_turns: 40`, `allowed_tools: [Read, Write, Edit, Glob, Grep, Skill, Bash]`.
- [ ] **Step 3: Create `ingest-1ton/graders/no-padding.md`** (`type: llm`): PASS if no created note opens with a preamble, ends with a recap, comments on the source or on the process, or repeats its own `summary`. Check the grader schema with `claude plugin eval --help`; if an `llm` grader cannot see written files, say so in the handoff file and keep the rubric text.
- [ ] **Step 4: Verify.** `tests/python/test_sb_fixtures.py` and both fast suites pass; every scaffold runs in a temporary directory without error (`bash evals/<case>/scaffold.sh` from an empty directory). The implementer runs no `claude` command.
- [ ] **Checkpoint.** Commit message: `test(second-brain): evals for schema 3, ingest-gap and no-padding`.

---

### Task 13: Docs, manifests and the migration rehearsal (AC1, AC2, AC11)

**Files:** Modify `README.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (repo root), `README.md` (repo root, the second-brain row), `docs/specs/2026-10-31-second-brain-v0.2-design.md` (one status line), `tests/sb_structure_test.sh`.

- [ ] **Step 1: Failing structure checks** in `tests/sb_structure_test.sh`: plugin version `0.3.0`; the `second-brain` marketplace entry has no `dependencies`; `allowCrossMarketplaceDependenciesOn` equals `["claude-plugins-official"]`; `hooks.json` registers exactly the four events; `lib/sb/*.py` totals <= 2,500 lines; `guard.py`, `review.py`, `doctor.py`, `index.py`, `logfile.py` and `obsidian/` do not exist; no embedding dependency (keep the existing grep); keep the `${CLAUDE_PLUGIN_ROOT}` path-exists loop. Delete the checks that now describe removed things (dependency names, version 0.2.4). Run: FAIL.
- [ ] **Step 2: Manifests.** `plugin.json`: version `0.3.0`, description without "protective hooks". Marketplace: drop the two `dependencies` of `second-brain` and the two cross-marketplace entries. Root `README.md`: the second-brain row reads "Local-first Second Brain: capture, ingest, find and lint a plain-markdown vault, with a deterministic CLI and a git-based review." Add to the v0.2 spec status "Partly superseded by `2026-11-10-second-brain-v0.3-design.md`."
- [ ] **Step 3: Rewrite `README.md`** (target <= 230 lines): what it is; install (one plugin, `--scope project`); requirements (Python 3.9+ as `python` or `python3`, git, `rg` optional, extraction tools for non-text sources); quickstart; vault layout (spec §5.1); skills (5); CLI (8 commands, lint codes of D49); recall; ingest and provenance (in place, relink, gaps); review as a label plus the session commit; sync (`local|pull`, manual push); **Migrating from 0.2** (the steps of spec §8, verbatim commands); limits (spec §10); roadmap rows F3/F4 unchanged; acceptance traceability AC1-AC16.
- [ ] **Step 4: Migration rehearsal** on copies, never on the originals. Copy `~/Documentos/second-brain-bench` to a new empty directory under the scratchpad. Create a second worktree of `main` (`git worktree add .claude/worktrees/sb-main main`) and, with its **v0.2** `bin/sb`, record `sb lint --json` and the top note of two `sb search` queries on the copy. Apply the README's migration commands to the copy. With the v0.3 CLI: `sb lint` exits 0 or reports only findings that existed before (minus dropped codes), `sb search` for two known terms returns the same top note as before, and `session.start` returns a status line. Record counts in the handoff file; remove the extra worktree afterwards.
- [ ] **Step 5: Verify.** Both fast suites pass.
- [ ] **Checkpoint.** Commit message: `docs(second-brain): v0.3 README, manifests and version 0.3.0`.

---

### Task 14: Verification and close (main session)

- [ ] **Step 1: Review the diff** against the spec, task by task; fix or send back anything that deviates. Read `.agents/run/handoff.md` and settle each logged decision with the human.
- [ ] **Step 2: Full checks.** `make check` exits 0; `make validate` exits 0 (`claude plugin validate ./plugins/second-brain --strict`); `sh .agents/bin/bmax gate fast` passes; `sh .agents/bin/bmax gate slow` passes before any push. Retrieval gate numbers (Recall@10, MRR) are printed and meet the thresholds.
- [ ] **Step 3: Budget-checked evals (AC12, AC16)**: ask the human before each paid run (Task 0 answer), up to US$4 in total. Run `find-implicit` three times with recall on, and three times with recall off by running `claude plugin eval <path>` on a scratch copy of the plugin whose `hooks.json` has no `UserPromptSubmit`; this machine's `claude plugin eval` sandbox cannot run Bash, so `ingest-gap`, `ingest-1ton` and the other Bash cases run with the manual harness `claude -p --plugin-dir <plugin> --model haiku --setting-sources project,local --permission-mode acceptEdits --output-format stream-json --verbose` in fresh scaffolded vaults, graded by the main session against each case's rubric. Keep the results under `evals/results/` and write the recall decision into the status line of the spec.
- [ ] **Step 4: Measure AC2, AC10, AC15** and write the numbers (lines, characters, p95 latency) in the final report.
- [ ] **Step 5: Close the plan.** Delete `.agents/plans/second-brain-v03.md`; append to `.agents/progress.md`: `- YYYY-MM-DD second-brain-v03: done|partial — <one line>`; propose lessons to the human; ask whether to run the independent review (`docs/review.md`); update the spec status line from "draft" to "implemented".

---

## Self-review

**Spec coverage.** D37 T1; D38 T2 (+T6 label); D39-D40 T3; D41 T4; D42 T2; D43 T11/T13; D44 T11; D45-D46 T9; D47 T7/T11; D48 T9/T11; D49-D50 T6; D51-D52 T5/T8; D53 T8/T11; D54 T14; D55 T7; D56-D57 T8; D58 T9; D59 T6; D60 T5/T9; D61 T10; D62 T11/T12; D63 T11/T12. AC1 T1-T4, T13; AC2 T11, T13; AC3 T8; AC4 T9; AC5 T9; AC6-AC7 T7; AC8 T6; AC9 T5, T14; AC10 T9, T11; AC11 T13; AC12 T14; AC13 T5, T9; AC14 T14; AC15 T10; AC16 T11, T12, T14.

**Calls this plan makes that the spec leaves open** (the human confirms or corrects at handoff): `SB107` and `SB111` are dropped with the other codes D49 does not list; ` · unpushed K` appears only in pull vaults and `sync not checked` stands in on `clear`/`compact`; `fork` starts behave like `clear` and `compact` (no git; the spec names only the latter two), and the `SessionStart` matcher gains `fork`; the outside-session commit carries only the `Sb-Files` trailer; the launcher spends one probe start (relaxing the spec's "not twice"); `lib/sb_main.py` is the shared entry and hook shebangs are removed; recall lines drop the `[reviewed]` label; the harness edit (Task 0) comes first so per-task commits pass the commit gate; `notes.base` is unverified in Obsidian.
