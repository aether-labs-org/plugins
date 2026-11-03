# second-brain v0.2.2 (Milestone C: folders, profiles, squad) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The agent knows what each folder is for; a vault is created from one of four profiles with its Claude Code settings; existing v0.1 vaults upgrade in place; 2–5 people share a vault through git without losing work; `sb doctor` explains what is missing.

**Architecture:** Folder descriptions live in per-folder `_about.md`; `lib/sb/tree.py` derives the tree. A new `SessionStart` hook injects the compact tree and vault status and, in squad vaults, pulls. Profiles are JSON files consumed by `lib/sb/init.py`. Git sync lives in `lib/sb/sync.py`, used by the SessionStart and SessionEnd hooks.

**Tech Stack:** Python 3.9+ standard library, git ≥ 2.30, Claude Code project settings, Obsidian Web Clipper and Bases file formats.

**Spec:** `docs/specs/2026-10-31-second-brain-v0.2-design.md` (§6, §8, §9, D16, D23, D24, D30, D32). Requires milestones A and B.

## Global Constraints

- Python **3.9+, standard library only**.
- Compact tree ≤ **2,000** characters (spec §6.1). SessionStart context = tree + one status line.
- Profiles (spec §6.3): `personal` → Projects, Areas, Resources, Archive; `work` → Projects, Areas, Resources, Decisions, Meetings, Archive; `project` → Context, Decisions, Meetings, References, Glossary, Archive; `squad` → as `project` with `sync: squad`. Folder names and `_about.md` texts in English (D24).
- `.second-brain.json`: `schema_version: 2`, `language`, `profile`, `sync` (`local` | `squad`) (D23).
- Squad pull: never `--autostash`; commit a dirty tree first with message `sb: local changes before sync`; `git pull --rebase` with 20 s timeout; on failure `git rebase --abort` (D30). Push 45 s; failure writes `.sb/push-pending`. SessionEnd hook `timeout: 60`.
- Commit trailers exactly `Sb-Session: <session_id>` and `Sb-Files: <n>`.
- A vault is its own repository: git top-level must equal the vault root (D32).
- `.claude/settings.json` deny rules exactly: `Edit(/_raw/**)`, `Bash(git push --force*)`, `Bash(git push -f*)`, `Bash(git reset --hard*)`, `Bash(git clean*)`.
- Plugin version becomes `0.2.2`.
- **Never commit or push without asking the user** (the plugin's own squad push is product behaviour, exercised only in temp repos by tests). Checkpoint steps: stop, show `git status --short`.

## Review Focus

1. **Same note edited in two clones between syncs**: rebase aborts, both commits survive, the user is told which file conflicts, nothing left in `git stash list`. → Task 5 `test_conflict_aborts_and_keeps_both_commits`.
2. **No network / unreachable remote at SessionEnd**: commit stays local, `.sb/push-pending` written, next SessionStart retries. → Task 5 `test_push_failure_is_retried_next_session`.
3. **v0.1 vault with hand-made folders and an existing `.claude/settings.json`**: upgrade never overwrites user files; it reports what it kept. → Task 4 `test_upgrade_keeps_user_files`.
4. **`_about.md` with block lists or missing `description`**: the tree still renders, the folder shows `(no description)`. → Task 1 `test_about_without_description`.
5. **Vault initialised inside another git repository**: `sb init` refuses with exit 2; `sb doctor` fails check 5 for an existing one. → Tasks 3, 6.

---

## File Structure

| Path | Responsibility |
| --- | --- |
| `plugins/second-brain/lib/sb/tree.py` | Create: `_about.md` model, tree, compact render, folder protection |
| `plugins/second-brain/lib/sb/lint.py` | Modify: `SB111` (info), info codes do not fail |
| `plugins/second-brain/lib/sb/guard.py` | Modify: folder-protected T2 |
| `plugins/second-brain/lib/sb/session.py` | Create: SessionStart logic |
| `plugins/second-brain/hooks/session_start.py` | Create: entry point |
| `plugins/second-brain/templates/profiles/{personal,work,project,squad}.json` | Create |
| `plugins/second-brain/templates/{settings.json,web-clipper-template.json,unreviewed.base}` | Create |
| `plugins/second-brain/lib/sb/init.py`, `lib/sb/vault.py` | Modify: profiles, upgrade, schema 2 |
| `plugins/second-brain/lib/sb/sync.py`, `lib/sb/autocommit.py`, `hooks/autocommit.py` | Squad sync, trailers |
| `plugins/second-brain/lib/sb/doctor.py` | Create |
| `plugins/second-brain/lib/sb/cli.py` | `tree`, `doctor`, `init --profile/--remote/--upgrade/--yes` |
| `plugins/second-brain/hooks/hooks.json` | `SessionStart`, SessionEnd timeout 60 |
| `plugins/second-brain/skills/init/SKILL.md`, `templates/CLAUDE.md`, `README.md` | Docs |
| `plugins/second-brain/evals/folder-placement/**` | LLM eval |
| `tests/python/test_sb_{tree,session,init,sync,doctor}.py` | Unit tests |

---

### Task 1: Folder contract and `sb tree`

**Files:**
- Create: `plugins/second-brain/lib/sb/tree.py`, `tests/python/test_sb_tree.py`
- Modify: `plugins/second-brain/lib/sb/lint.py`, `plugins/second-brain/lib/sb/cli.py`

**Interfaces:**
- Produces: `tree.load(root) -> list` of `{"path": "Resources", "description": str, "protected": bool, "conventions": str, "examples": str, "anti_examples": str, "children": [...]}` for every directory under `wiki/` whose name does not start with `_` or `.`, sorted by name; `tree.render_compact(folders, limit=2000) -> str`; `tree.folder_protected(root, note_rel: str) -> bool` (any ancestor folder's `_about.md` has `protected: true`); CLI `sb tree [--compact] [--json]`; lint code `SB111` "folder has no _about.md" with `lint.INFO_CODES = {"SB111"}` — `sb lint` exits `1` only when a non-info finding exists.
- `_about.md` sections are the bodies under `## Conventions`, `## Examples`, `## Anti-examples` (empty string when absent).

- [x] **Step 1: Write the failing tests**

```python
def test_load_and_compact(self):
    # wiki/Resources/_about.md (description "Concepts and references.") and wiki/Resources/Langs/_about.md
    self.assertEqual(render_compact(load(root)),
                     "Resources/ — Concepts and references.\n  Langs/ — Programming languages.")

def test_compact_respects_limit(self):
    # 80 folders with 60-char descriptions -> len(render_compact(...)) <= 2000 and ends with "… (+N more)"

def test_about_without_description(self):
    # _about.md with only "tags:\n  - x" in frontmatter -> description "(no description)"

def test_folder_protected_inherits(self):
    # wiki/Areas/_about.md protected: true -> folder_protected(root, "wiki/Areas/Saude/X.md") is True

def test_sb111_is_info_and_does_not_fail(self):
    # vault with a folder lacking _about.md and otherwise clean -> lint returns SB111, `sb lint` exit 0
```

- [x] **Step 2: Run** `python3 -m unittest tests/python/test_sb_tree.py -v` — Expected: FAIL.
- [x] **Step 3: Implement.** Compact line: `"  " * depth + "<name>/ — <description>"`; descriptions cut by `sanitize.clean_inline(desc, 120)`; when the limit would be exceeded, stop and append `… (+<remaining> more)`.
- [x] **Step 4: Guard.** In `guard.py` note-write branch, pass `folder_protected=tree.folder_protected(vault, rel)` to `trust.tier`. Add `test_folder_protected_note_asks` to `test_sb_guard.py`.
- [x] **Step 5: Run** `bash tests/sb_cli_test.sh` — Expected: PASS. **Step 6: Checkpoint.**

---

### Task 2: SessionStart hook

**Files:**
- Create: `plugins/second-brain/lib/sb/session.py`, `plugins/second-brain/hooks/session_start.py`, `tests/python/test_sb_session.py`
- Modify: `plugins/second-brain/hooks/hooks.json`

**Interfaces:**
- Consumes: `tree`, `trust.label`, `index`, `sync.pull`, `sync.push`, `sync.pending` (Task 5; until then `session.start` calls them only when `sync == "squad"`, so Task 2 tests use local vaults).
- Produces: `session.start(event: dict, cwd: str) -> Optional[dict]` → `{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": str}}`; writes `.sb/heartbeat.json` `{"session_start": "<ISO datetime>", "session_id": str}`; regenerates `_index.md` when it drifts.

Context, exactly:

```
<second-brain-vault>
Folders under wiki/ (from _about.md; follow their conventions when filing notes):
<compact tree>
Status: inbox <n> · unreviewed <m> · sync <local|ok|conflict: <files>|push pending>
</second-brain-vault>
```

- [x] **Step 1: Tests:** `test_context_shape` (exact first/last lines, counts of 2 inbox items and 1 unreviewed note), `test_heartbeat_written`, `test_index_regenerated`, `test_outside_vault_is_none`, `test_hook_entry_point_exit_0_on_garbage`.
- [x] **Step 2: Run** — Expected: FAIL. **Step 3: Implement**; entry point mirrors `hooks/validate_note.py`.
- [x] **Step 4: Register** in `hooks.json`: `"SessionStart": [{"matcher": "startup|resume|clear|compact", "hooks": [{"type": "command", "command": "python3 \"${CLAUDE_PLUGIN_ROOT}/hooks/session_start.py\"", "timeout": 30}]}]`.
- [x] **Step 5: Run** tests and `claude plugin validate ./plugins/second-brain --strict` — Expected: PASS. **Step 6: Checkpoint.**

---

### Task 3: Profiles and `sb init`

**Files:**
- Create: `plugins/second-brain/templates/profiles/{personal,work,project,squad}.json`, `plugins/second-brain/templates/settings.json`, `plugins/second-brain/templates/web-clipper-template.json`, `plugins/second-brain/templates/unreviewed.base`
- Modify: `plugins/second-brain/lib/sb/init.py`, `plugins/second-brain/lib/sb/vault.py` (`SCHEMA_VERSION = 2`), `plugins/second-brain/lib/sb/cli.py`, `tests/python/sb_helpers.py` (`schema_version` default 2)
- Test: `tests/python/test_sb_init.py`

**Interfaces:**
- Produces: `init.load_profile(name: str) -> dict` (`{"name", "sync", "folders": [{"path", "description", "protected", "conventions", "examples", "anti_examples"}]}`); `init.run(root, language="en", profile="personal", remote=None, git=False, areas=()) -> dict` (same result shape as v0.1); CLI `sb init --profile {personal,work,project,squad} [--language L] [--remote URL] [--git] [--areas a,b]`.
- Profile file schema: one JSON object as above; `conventions`, `examples`, `anti_examples` are Markdown strings written under the matching `##` headings of `_about.md`. Example entries for `Decisions`: description "One note per decision: context, options, choice, consequences."; anti-example "Meeting minutes (they go in Meetings/ and link to the decision)."
- Files written: everything in v0.1 `init`; `wiki/<folder>/_about.md` per profile folder; `.claude/settings.json` from the template (only when absent); `_meta/web-clipper-template.json`; `_views/unreviewed.base`; `.gitignore` lines `.sb/`, `.obsidian/workspace*`, `.smart-env/` and, for `sync: squad`, `_index.md`, `_log.md`; with `--remote`, `git remote add origin <url>` (requires `--git` or an existing `.git`).
- `templates/settings.json`: `enabledPlugins` `second-brain@aether-labs`, `document-skills@anthropic-agent-skills`, `obsidian@obsidian-skills` (all `true`); `extraKnownMarketplaces` `aether-labs` (github `aether-labs-org/plugins`), `anthropic-agent-skills` (github `anthropics/skills`), `obsidian-skills` (github `kepano/obsidian-skills`); `permissions.deny` from Global Constraints.

- [x] **Step 1: Tests**

```python
def test_each_profile_creates_a_clean_vault(self):
    for name in ("personal", "work", "project", "squad"):
        root = Path(self.tmp.name) / name
        run(root, language="pt-BR", profile=name, git=True)
        self.assertEqual([f for f in lint(root, load_config(root)) if f.code not in INFO_CODES], [])
        self.assertLessEqual(len(render_compact(load(root))), 2000)
        self.assertEqual(json.loads((root / ".second-brain.json").read_text())["sync"],
                         "squad" if name == "squad" else "local")

def test_settings_json_content(self):
    s = json.loads((root / ".claude/settings.json").read_text())
    self.assertEqual(s["permissions"]["deny"], ["Edit(/_raw/**)", "Bash(git push --force*)", "Bash(git push -f*)",
                                                "Bash(git reset --hard*)", "Bash(git clean*)"])
    self.assertTrue(s["enabledPlugins"]["second-brain@aether-labs"])

def test_squad_gitignores_index_and_log(self): ...
def test_refuses_inside_another_git_repo(self):
    # parent dir is a git repo -> sb init exits 2 with "inside the git repository"
def test_remote_is_added(self):
    # --git --remote /tmp/bare.git -> `git remote get-url origin` equals it
```

- [x] **Step 2: Run** — Expected: FAIL.
- [x] **Step 3: Implement.** Bump `SCHEMA_VERSION` to `2`; `SB107` message becomes `schema_version <n> is older than 2; run sb init --upgrade`. Update `sb_helpers.make_vault` default config to schema 2 and fix fallout in existing tests.
- [ ] **Step 4: Verify the two Obsidian formats by hand:** import `_meta/web-clipper-template.json` in the Web Clipper (Settings → Templates → Import) and confirm a clip lands in `_inbox/` with `url`, `title`, `captured`; open `_views/unreviewed.base` in Obsidian ≥ 1.9 and confirm it lists an `origin: agent` note without `reviewed`. Field names: [Web Clipper templates](https://help.obsidian.md/web-clipper/templates), [Bases syntax](https://help.obsidian.md/bases/syntax). Record both results.  _(open: manual Obsidian check (Web Clipper import, Bases view) not recorded)_
- [x] **Step 5: Run** `bash tests/sb_cli_test.sh` — Expected: PASS. **Step 6: Checkpoint.**

---

### Task 4: `sb init --upgrade`

**Files:**
- Modify: `plugins/second-brain/lib/sb/init.py`, `plugins/second-brain/lib/sb/cli.py`
- Test: `tests/python/test_sb_init.py`

**Interfaces:**
- Produces: `init.upgrade(root, profile=None, yes=False) -> dict` → `{"actions": [str], "kept": [str], "applied": bool}`; CLI `sb init --upgrade [--profile P] [--yes]` prints the actions; without `--yes` it applies nothing and exits `0`.
- Actions: add missing `_about.md` (profile text when the folder name matches a profile folder, else `description: (describe this folder)`); add missing `.claude/settings.json`, `_meta/…`, `_views/…`; add missing `.gitignore` lines; set `schema_version: 2`, `profile`, `sync` (default `local`; `squad` only with `--profile squad`); in squad, `git rm --cached -q _index.md _log.md` when tracked.

- [x] **Step 1: Tests:** `test_upgrade_dry_run_changes_nothing` (file tree hash identical), `test_upgrade_keeps_user_files` (existing `.claude/settings.json` and `CLAUDE.md` byte-identical, listed in `kept`), `test_upgrade_v01_vault_to_squad` (index/log untracked afterwards, notes untouched), `test_upgrade_is_idempotent` (second run: `actions == []`).
- [x] **Step 2: Run** — FAIL. **Step 3: Implement.** **Step 4: Run** — PASS. **Step 5: Checkpoint.**

---

### Task 5: Squad sync and commit trailers

**Files:**
- Create: `plugins/second-brain/lib/sb/sync.py`, `tests/python/test_sb_sync.py`
- Modify: `plugins/second-brain/lib/sb/autocommit.py`, `plugins/second-brain/hooks/autocommit.py`, `plugins/second-brain/lib/sb/session.py`, `plugins/second-brain/hooks/hooks.json`

**Interfaces:**
- Produces: `sync.enabled(root) -> bool` (`sync == "squad"` and git top-level == root); `sync.pull(root) -> str` (`"ok"`, `"skipped: <why>"`, or `"conflict: <comma-separated files>"`); `sync.push(root) -> str` (`"ok"`, `"pending: <stderr first line>"`); `sync.pending(root) -> bool`; `autocommit.run(cwd, env=None, today=None, session_id="", message=None) -> str` (adds trailers, pushes after a commit when `sync.enabled`).
- Commit message body:

```
sb: session 2026-11-02 (3 files)

Sb-Session: <session_id>
Sb-Files: 3
```

- [x] **Step 1: Tests** with a bare remote and two clones (`git init --bare`, `git clone`, `user.name/email` set per clone):

```python
def test_trailers(self): ...                      # git log -1 --format=%B contains both trailers
def test_pull_rebases_clean_history(self): ...    # A commits+pushes, B pull -> B has A's commit, linear history
def test_dirty_tree_is_committed_before_pull(self):
    # B has an uncommitted edit; pull -> a commit "sb: local changes before sync" exists, `git stash list` empty
def test_conflict_aborts_and_keeps_both_commits(self):
    # A and B edit the same line of wiki/Resources/X.md; A pushes; B pull -> "conflict: wiki/Resources/X.md",
    # no rebase in progress, B's commit still on B's branch, `git stash list` empty
def test_push_failure_is_retried_next_session(self):
    # remote path renamed -> push returns "pending: ..." and .sb/push-pending exists;
    # restore remote, session.start -> push retried, marker removed, status line "sync ok"
def test_skipped_when_local_or_not_toplevel(self): ...
def test_simulation_two_clones_twenty_sessions(self):
    # 20 alternating sessions (start -> edit a different note -> end) per clone, plus 3 same-note conflicts;
    # assert: no rebase dir in .git, stash empty, every non-conflicting edit present on the remote,
    # `git ls-files` never lists _index.md or _log.md, every sb commit has both trailers
```

- [x] **Step 2: Run** `python3 -m unittest tests/python/test_sb_sync.py -v` — Expected: FAIL.
- [x] **Step 3: Implement.** `pull`: skip unless enabled, no in-progress op (reuse `autocommit.IN_PROGRESS`), upstream exists (`git rev-parse --abbrev-ref @{u}`); dirty → `autocommit.run(..., message="sb: local changes before sync")` without pushing; `git pull --rebase` (timeout 20); on non-zero: collect `git diff --name-only --diff-filter=U`, `git rebase --abort`, return `conflict: …`. `push`: `git push` (or `git push -u origin HEAD` when no upstream), timeout 45; failure writes `.sb/push-pending`. `hooks/autocommit.py` passes `session_id` from the event. SessionEnd `timeout` → `60`.
- [x] **Step 4: Run** — Expected: PASS (the simulation test must finish in < 60 s). **Step 5: Checkpoint.**

---

### Task 6: `sb doctor`

**Files:**
- Create: `plugins/second-brain/lib/sb/doctor.py`, `tests/python/test_sb_doctor.py`
- Modify: `plugins/second-brain/lib/sb/cli.py`

**Interfaces:**
- Produces: `doctor.run(root, now=None, which=shutil.which) -> list` of `{"check", "status": "ok"|"warn"|"fail", "detail", "fix"}`; CLI `sb doctor [--json]` exits `1` if any `fail`. Text mode ends with the "Recommended Obsidian setup" table of spec §9.
- Checks (spec §6.5): `python` (≥ 3.9 and FTS5 → else `warn` "slow search"); `settings` (`.claude/settings.json` enables the three plugins and has the five deny rules → else `fail`, fix `sb init --upgrade --yes`); `extraction` (`pandoc`, `markitdown`, `pdftotext`, `npx` on PATH, `pypdf` importable → each missing one listed, `warn`, with install hints `uv tool install 'markitdown[all]'`, `sudo apt install pandoc poppler-utils`, `pip install pypdf`, Node.js for `npx`); `hooks` (`.sb/heartbeat.json` younger than 7 days → else `warn` "hooks may not be running: is the plugin installed for this project?"); `git` (top-level == root else `fail`; squad: remote, upstream, no `push-pending` → else `warn`).

- [x] **Step 1: Tests:** one per check with planted failures (`which` stub returning `None` for `pandoc`; settings missing a deny rule; heartbeat 8 days old; vault nested in a parent repo; squad without upstream) — Expected statuses asserted; `test_clean_vault_all_ok` with all tools stubbed present.
- [x] **Step 2–4:** Run (FAIL) → implement → run (PASS). **Step 5: Checkpoint.**

---

### Task 7: `init` skill, template, README, eval, version

**Files:**
- Modify: `plugins/second-brain/skills/init/SKILL.md`, `plugins/second-brain/templates/CLAUDE.md`, `plugins/second-brain/README.md`, `plugins/second-brain/.claude-plugin/plugin.json`, `tests/sb_structure_test.sh`
- Create: `plugins/second-brain/evals/folder-placement/{case.yaml,prompt.md,scaffold.sh,graders/in-decisions.md}`, `plugins/second-brain/evals/_fixtures/inbox-decision/2026-11-03-postgres.md`

- [x] **Step 1: `init` skill:** at most three questions — profile (with one-line description each), language, remote URL (squad only); existing vault → offer `sb init --upgrade` (show the dry run, apply only with the user's yes); then `sb doctor`. Tell the user to install with `--scope project` and to commit `.claude/settings.json`.
- [x] **Step 2: Template `CLAUDE.md`:** "File notes by the folder descriptions in the `<second-brain-vault>` block (from `_about.md`)"; `_about.md` is human-edited; in squad vaults `_index.md`/`_log.md` are local.
- [x] **Step 3: README:** profiles table, install with `--scope project`, squad workflow (what SessionStart/SessionEnd do, conflicts), `sb tree`, `sb doctor`, `sb init --upgrade`, the §9 Obsidian table (Terminal is the supported agent-in-Obsidian path; Linter discouraged), Obsidian Git settings for squad (pull on startup, rebase, auto commit-and-sync interval for human edits).
- [ ] **Step 4: Eval `folder-placement`:** scaffold `sb init --vault . --profile work` plus the inbox fixture (a decision: "Decidimos adotar PostgreSQL como banco padrão a partir de dezembro porque..."); `prompt.md` `runs: 10`, `max_turns: 40`: `Ingest the item in _inbox.`; grader `in-decisions.md`: `type: regex`, `target: files`, `pattern: '^wiki/Decisions/[^/]+\.md$'`, `match: "count:1"`. Run (ask the user first): `claude plugin eval ./plugins/second-brain --case folder-placement --model haiku --scaffold --allow-tools Bash Write Edit --threshold 0.8 --max-cost-usd 1`. Expected: score ≥ 0.8.  _(open: case written, but the paid `folder-placement` run (n=10) has no kept result)_
- [x] **Step 5:** version `0.2.2` in `plugin.json` and the structure test; structure checks for `hooks.SessionStart`, the four profile files, and SessionEnd `timeout == 60`.
- [ ] **Step 6: Verify:** `make check`, `make validate`; run `sb init --upgrade --yes` on a copy of a v0.1 eval fixture vault and `sb doctor` on it. **Exit criteria** (spec §6, §8): four profiles lint-clean with tree ≤ 2,000 chars; simulation passes; upgrade only adds files; doctor flags 5/5 planted failures; `folder-placement` ≥ 0.8.  _(open: all but `folder-placement` >= 0.8 verified 2026-11-03)_
- [x] **Step 7: Checkpoint** — ask the user whether to commit milestone C.

## Self-Review notes

- Spec §6.1 → Task 1; §6.2 → Task 2; §6.3 → Tasks 3–4; §6.4 → Task 5; §6.5 → Task 6; §9 → Tasks 6–7; D32 → Tasks 3, 5, 6.
- Task 2 runs before Task 5 by design; `session.start` gains the squad branch in Task 5 Step 3.
