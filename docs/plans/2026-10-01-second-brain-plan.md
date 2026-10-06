# second-brain Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the `second-brain` Claude Code plugin (v0.1.0): seven skills, a stdlib-only Python CLI `sb`, three hooks (guard, frontmatter check, auto-commit), tests and evals, registered in the `aether-labs` marketplace.

**Architecture:** Skills carry procedures; the `sb` CLI (`bin/sb` → `lib/sb/`) does every mechanical, testable job (index, lint, links, validate, log, init); hooks are thin scripts over `lib/sb/` modules and are no-ops outside a directory that has `.second-brain.json`. The vault is plain markdown with a restricted YAML-subset frontmatter and `[[wikilinks]]`.

**Tech Stack:** Python 3.9+ standard library only (`unittest`, `argparse`, `subprocess`), bash test scripts, `jq`, `ripgrep` (skills and one test), `claude plugin validate`/`eval`.

**Spec:** `docs/specs/2026-09-30-second-brain-design.md`

## Global Constraints

- Plugin name `second-brain`, version `0.1.0`, license `Apache-2.0`, author `Aether Labs`, lives at `plugins/second-brain/` (spec §3).
- Python **3.9+, standard library only**; no PyYAML, no network access, no embeddings, no MCP server, no `.mcp.json` (spec D1, D8, AC9). Do not use `X | Y` type syntax or `match` statements.
- Frontmatter subset: `key: value` scalars and inline `[a, b]` lists only; anything else is `SB108` (spec §4.2).
- Marketplace entry has **no `version`** (repo convention, `tests/structure_test.sh`).
- Every `SKILL.md`: description 150–400 characters, file ≤ 250 lines (repo convention, `tests/sa_structure_test.sh`). The vault `CLAUDE.md` template is under 200 lines (AC1).
- Hooks never block on their own failure: any internal exception → exit `0`, print nothing. Hooks are no-ops when no `.second-brain.json` is found upward from `cwd`.
- `autocommit` never pushes. `auto_commit` defaults to `true`; it commits only when `<vault>/.git` exists (spec D7).
- Protected paths (guard): `_raw/**`, `.claude/**`, top-level `CLAUDE.md`, top-level `.second-brain.json`.
- Exit codes of `sb`: `0` ok, `1` findings, `2` usage error or not in a vault.
- Repo files are written in English. Notes inside a vault use the vault language from `.second-brain.json`.
- **Never commit or push without asking the user first** (user's global rule). Each task ends with a checkpoint step that asks; commit messages end with the attribution lines below.

Commit trailer for every commit made in this plan:

```
Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01K77ufoXsUXGa3XcK4Lphnd
```

## Review Focus

Inputs the spec implies but the happy-path tests would not exercise. Each has a pinned test in the owning task.

1. **Accented names and spaces** (`Café Noir.md`, `Gamma Ray.md`): wikilinks resolve, index lists them, no false `SB101`. → Task 4 (`test_accented_and_spaced_names_resolve`).
2. **Freshly initialised, empty vault**: `sb lint` and `sb index --check` exit `0`; `links` on a missing note exits `2` with a message, not a traceback. → Tasks 5, 6.
3. **CRLF line endings and a UTF-8 BOM** in a note: no false `SB108`. → Task 2 (`test_crlf_and_bom`).
4. **Malformed `.second-brain.json` and a binary/non-UTF-8 `.md`**: `sb lint` exits `2` with a message for the first, and reports `SB108` "unreadable" for the second without aborting. → Tasks 4, 5.
5. **Working directory inside a subfolder and `..`/symlink paths into `_raw/`**: vault is still discovered; `wiki/../_raw/x` and a symlink to `_raw` are denied. → Task 7.

---

## File Structure

| Path | Responsibility |
| --- | --- |
| `plugins/second-brain/.claude-plugin/plugin.json` | Manifest + `userConfig.auto_commit` |
| `plugins/second-brain/lib/sb/frontmatter.py` | Restricted frontmatter parser |
| `plugins/second-brain/lib/sb/links.py` | Wikilink extraction (prose only) |
| `plugins/second-brain/lib/sb/vault.py` | Vault discovery, config, note loading |
| `plugins/second-brain/lib/sb/fsutil.py` | `write_atomic` |
| `plugins/second-brain/lib/sb/index.py` | Deterministic `_index.md` build and drift diff |
| `plugins/second-brain/lib/sb/logfile.py` | Append-only `_log.md` |
| `plugins/second-brain/lib/sb/lint.py` | `Finding`, `check_note`, `lint` (SB101–SB109) |
| `plugins/second-brain/lib/sb/init.py` | Vault scaffolding (backend of `/second-brain:init`) |
| `plugins/second-brain/lib/sb/cli.py` | `argparse` front end |
| `plugins/second-brain/lib/sb/guard.py` | PreToolUse decision logic |
| `plugins/second-brain/lib/sb/postcheck.py` | PostToolUse frontmatter feedback |
| `plugins/second-brain/lib/sb/autocommit.py` | Stop-hook git logic |
| `plugins/second-brain/bin/sb` | Executable shim |
| `plugins/second-brain/hooks/{hooks.json,guard.py,validate_note.py,autocommit.py}` | Thin hook entry points |
| `plugins/second-brain/templates/CLAUDE.md` | Vault rules (rendered by `init`) |
| `plugins/second-brain/skills/{init,capture,ingest,find,link,update,lint}/SKILL.md` | Procedures |
| `plugins/second-brain/evals/**` | Skill evals + fixtures |
| `tests/python/sb_helpers.py`, `tests/python/test_sb_*.py` | Unit tests |
| `tests/sb_cli_test.sh`, `tests/sb_structure_test.sh` | Repo-style test entry points (picked up by `tests/run.sh`) |

---

### Task 1: Plugin scaffold, marketplace entry, test harness

**Files:**
- Create: `plugins/second-brain/.claude-plugin/plugin.json`
- Create: `plugins/second-brain/lib/sb/__init__.py`
- Create: `tests/python/sb_helpers.py`
- Create: `tests/sb_cli_test.sh`
- Create: `tests/sb_structure_test.sh`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `README.md` (plugins table)
- Modify: `Makefile` (`validate` target)

**Interfaces:**
- Produces: `sb_helpers.PLUGIN` (Path to the plugin), `sb_helpers.ROOT`, `sb_helpers.note(title, summary="A summary.", body="", origin="human", status="draft", type="nota", created="2026-09-30", source="", reviewed=None) -> str` (pass `summary=None` / `created=None` to omit the key), `sb_helpers.make_vault(tmp, notes=None, config=None, index=True) -> Path` (`notes` maps a path under `wiki/` to file text). Importing `sb_helpers` puts `plugins/second-brain/lib` on `sys.path`.

- [ ] **Step 1: Create the manifest**

`plugins/second-brain/.claude-plugin/plugin.json`:

```json
{
  "name": "second-brain",
  "description": "Local-first Second Brain for Claude Code: capture, ingest, find, link, update and lint a plain-markdown vault with a deterministic CLI, protective hooks and optional local auto-commit.",
  "version": "0.1.0",
  "author": {
    "name": "Aether Labs"
  },
  "license": "Apache-2.0",
  "repository": "https://github.com/aether-labs-org/plugins",
  "keywords": ["second-brain", "notes", "knowledge-base", "markdown", "obsidian", "local-first"],
  "userConfig": {
    "auto_commit": {
      "type": "boolean",
      "title": "Auto-commit vault changes",
      "description": "After each response, commit vault changes locally when the vault has a .git directory. Never pushes.",
      "default": true
    }
  }
}
```

- [ ] **Step 2: Create the package marker and the shared test helpers**

`plugins/second-brain/lib/sb/__init__.py`:

```python
"""second-brain: deterministic tooling for a local markdown vault."""

__version__ = "0.1.0"
```

`tests/python/sb_helpers.py`:

```python
"""Shared helpers for the second-brain tests. Importing this puts lib/ on sys.path."""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLUGIN = ROOT / "plugins" / "second-brain"
sys.path.insert(0, str(PLUGIN / "lib"))


def note(title, summary="A summary.", body="", origin="human", status="draft",
         type="nota", created="2026-09-30", source="", reviewed=None):
    """Return the text of a valid note. Pass summary=None / created=None to omit the key."""
    lines = ["---", "title: %s" % title]
    if summary is not None:
        lines.append("summary: %s" % summary)
    lines += ["type: %s" % type, "status: %s" % status, "origin: %s" % origin]
    if created is not None:
        lines.append("created: %s" % created)
    lines.append("source: %s" % source)
    if reviewed:
        lines.append("reviewed: %s" % reviewed)
    lines += ["---", body, ""]
    return "\n".join(lines)


def make_vault(tmp, notes=None, config=None, index=True):
    """Build a vault under tmp. `notes` maps a path under wiki/ to the file text."""
    from sb import index as index_mod
    from sb.vault import load_notes

    root = Path(tmp)
    cfg = {"schema_version": 1, "language": "en", "areas": []}
    cfg.update(config or {})
    (root / ".second-brain.json").write_text(json.dumps(cfg), encoding="utf-8")
    for rel in ("_inbox/_done", "_raw", "wiki"):
        (root / rel).mkdir(parents=True, exist_ok=True)
    (root / "_log.md").write_text("", encoding="utf-8")
    for rel, text in (notes or {}).items():
        path = root / "wiki" / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    if index:
        (root / "_index.md").write_text(index_mod.build(load_notes(root)), encoding="utf-8")
    return root
```

- [ ] **Step 3: Create the two repo-style test entry points**

`tests/sb_cli_test.sh`:

```bash
#!/usr/bin/env bash
# Runs every second-brain unit test (tests/python/test_sb_*.py).
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
python3 -m unittest discover -s tests/python -p 'test_sb_*.py' -q
status=$?
if [ "$status" -eq 0 ]; then echo "  ok   second-brain unit tests"; else echo "  FAIL second-brain unit tests"; fi
exit $status
```

`tests/sb_structure_test.sh`:

```bash
#!/usr/bin/env bash
# Structural checks for the second-brain plugin (spec sections 3, 6, 10).
set -uo pipefail
fail=0
check() { if [ "$2" -eq 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fail=1; fi; }
root="$(cd "$(dirname "$0")/.." && pwd)"
p="$root/plugins/second-brain"
mp="$root/.claude-plugin/marketplace.json"
pj="$p/.claude-plugin/plugin.json"

jq -e '.plugins[] | select(.name == "second-brain" and .source == "./plugins/second-brain")' "$mp" >/dev/null
check "marketplace lists second-brain" $?
jq -e '.plugins[] | select(.name == "second-brain") | has("version") | not' "$mp" >/dev/null
check "marketplace entry has no version" $?
[ "$(jq -r .name "$pj")" = "second-brain" ]; check "plugin name" $?
[ "$(jq -r .version "$pj")" = "0.1.0" ]; check "plugin version 0.1.0" $?
jq -e '.userConfig.auto_commit | .type == "boolean" and .default == true' "$pj" >/dev/null
check "userConfig.auto_commit is boolean, default true" $?
[ ! -e "$p/.mcp.json" ]; check "no .mcp.json (AC9)" $?
! grep -rEqi 'sentence[_-]transformers|ollama|faiss|chromadb|onnxruntime|openai' "$p/lib" "$p/bin" "$p/hooks" 2>/dev/null
check "no embedding/vector dependencies (AC9)" $?

claude plugin validate "$p" --strict >/dev/null 2>&1; check "claude plugin validate --strict" $?
exit $fail
```

Make both executable: `chmod +x tests/sb_cli_test.sh tests/sb_structure_test.sh`.

- [ ] **Step 4: Run the structure test and confirm it fails**

Run: `bash tests/sb_structure_test.sh`
Expected: FAIL on "marketplace lists second-brain" (and on `validate`, which cannot pass yet because the manifest is not registered or complete), exit 1.

- [ ] **Step 5: Register the plugin**

In `.claude-plugin/marketplace.json`, append this object to the `plugins` array (after `solutions-architect`; keep valid JSON):

```json
    {
      "name": "second-brain",
      "source": "./plugins/second-brain",
      "description": "Local-first Second Brain: capture, ingest, find, link, update and lint a plain-markdown vault, with a deterministic CLI and protective hooks.",
      "category": "productivity",
      "tags": ["second-brain", "notes", "knowledge-base", "markdown", "local-first"]
    }
```

In `README.md`, add a row to the plugins table:

```
| second-brain | Local-first Second Brain: capture, ingest, find, link, update and lint a plain-markdown vault, with a deterministic CLI and protective hooks. | `/plugin install second-brain@aether-labs` |
```

In `Makefile`, add to the `validate` recipe:

```
	claude plugin validate ./plugins/second-brain --strict
```

- [ ] **Step 6: Run the structure test again**

Run: `bash tests/sb_structure_test.sh && python3 -c "import json;json.load(open('.claude-plugin/marketplace.json'))"`
Expected: all `ok` (the plugin has no skills/hooks yet; `claude plugin validate` passes on a manifest-only plugin). If `validate` reports warnings that `--strict` turns into failures, read the message and fix the manifest, not the test.

- [ ] **Step 7: Run the whole existing suite to make sure nothing regressed**

Run: `bash tests/run.sh`
Expected: every pre-existing script still passes (the new `sb_cli_test.sh` reports "Ran 0 tests" success).

- [ ] **Step 8: Checkpoint** — show `git status`, ask the user whether to commit. Suggested message: `feat(second-brain): scaffold plugin, marketplace entry and test harness`.

---

### Task 2: Frontmatter parser and wikilink extraction

**Files:**
- Create: `plugins/second-brain/lib/sb/frontmatter.py`
- Create: `plugins/second-brain/lib/sb/links.py`
- Test: `tests/python/test_sb_frontmatter.py`, `tests/python/test_sb_links.py`

**Interfaces:**
- Produces: `frontmatter.parse(text) -> Parsed(data: dict, body: str, errors: list[(line, message)], body_line: int)`; `links.WIKILINK` (compiled regex), `links.prose_lines(body, first_line=1) -> iterator[(line_number, text_without_inline_code)]`, `links.extract(body, first_line=1) -> list[(line_number, target_name)]`, `links.target_name(raw) -> str`.

- [ ] **Step 1: Write the failing frontmatter tests**

`tests/python/test_sb_frontmatter.py`:

```python
import unittest

import sb_helpers  # noqa: F401  (sets sys.path)
from sb.frontmatter import parse


class ParseTests(unittest.TestCase):
    def test_scalars_lists_and_body(self):
        text = "---\ntitle: Foo\ntags: [a, \"b c\"]\nsource: [[Other]]\nreviewed:\n---\nBody\n"
        p = parse(text)
        self.assertEqual(p.errors, [])
        self.assertEqual(p.data, {"title": "Foo", "tags": ["a", "b c"],
                                  "source": "[[Other]]", "reviewed": ""})
        self.assertEqual(p.body, "Body\n")
        self.assertEqual(p.body_line, 7)

    def test_quotes_and_trailing_comment(self):
        p = parse('---\ntitle: "A: B"\nstatus: seed # note\n---\n')
        self.assertEqual(p.errors, [])
        self.assertEqual(p.data, {"title": "A: B", "status": "seed"})

    def test_crlf_and_bom(self):
        p = parse("﻿---\r\ntitle: Foo\r\nsummary: Bar\r\n---\r\nBody\r\n")
        self.assertEqual(p.errors, [])
        self.assertEqual(p.data, {"title": "Foo", "summary": "Bar"})

    def test_nested_mapping_is_rejected_with_line_number(self):
        p = parse("---\nkey:\n  nested: 1\n---\n")
        self.assertEqual([line for line, _ in p.errors], [3])

    def test_block_list_is_rejected(self):
        p = parse("---\ntags:\n- a\n---\n")
        self.assertEqual([line for line, _ in p.errors], [3])

    def test_block_scalar_is_rejected(self):
        p = parse("---\nsummary: |\n  x\n---\n")
        self.assertEqual([line for line, _ in p.errors], [2, 3])

    def test_missing_frontmatter(self):
        p = parse("# Title\n")
        self.assertEqual(p.errors, [(1, "missing frontmatter")])
        self.assertEqual(p.body, "# Title\n")
        self.assertEqual(p.body_line, 1)

    def test_unclosed_frontmatter(self):
        p = parse("---\ntitle: x\n")
        self.assertEqual(p.errors, [(1, "frontmatter is not closed with ---")])

    def test_duplicate_key(self):
        p = parse("---\ntitle: a\ntitle: b\n---\n")
        self.assertEqual(p.data, {"title": "a"})
        self.assertEqual([line for line, _ in p.errors], [3])


if __name__ == "__main__":
    unittest.main()
```

`tests/python/test_sb_links.py`:

```python
import unittest

import sb_helpers  # noqa: F401
from sb.links import extract, target_name


class ExtractTests(unittest.TestCase):
    def test_variants_code_and_line_numbers(self):
        body = ("intro [[A]]\n```\n[[Hidden]]\n```\n"
                "use `[[Code]]` and [[B|alias]] and [[C#Head]] and [[dir/D.md]]\n")
        self.assertEqual(extract(body, first_line=10),
                         [(10, "A"), (14, "B"), (14, "C"), (14, "D")])

    def test_tilde_fence_is_ignored(self):
        self.assertEqual(extract("~~~\n[[X]]\n~~~\n[[Y]]\n"), [(4, "Y")])

    def test_target_name_strips_folder_and_extension(self):
        self.assertEqual(target_name(" wiki/Resources/Café Noir.md "), "Café Noir")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run them to verify they fail**

Run: `python3 -m unittest discover -s tests/python -p 'test_sb_f*.py' -q; python3 -m unittest discover -s tests/python -p 'test_sb_l*.py' -q`
Expected: `ModuleNotFoundError: No module named 'sb.frontmatter'` / `'sb.links'`.

- [ ] **Step 3: Implement the parser**

`plugins/second-brain/lib/sb/frontmatter.py`:

```python
"""Restricted YAML-subset frontmatter parser (spec D8, section 4.2).

Accepted: `key: value` scalars, quoted scalars, `[[Wiki Link]]` scalars and inline `[a, b]`
lists. Everything else is reported as an error with its line number.
"""
import re
from typing import NamedTuple

KEY_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_-]*):(?:[ \t]+(.*))?$")
COMMENT_RE = re.compile(r"\s+#.*$")
UNSUPPORTED_START = ("|", ">", "{", "&", "*", "!")


class Parsed(NamedTuple):
    data: dict
    body: str
    errors: list      # [(line_number, message)]
    body_line: int    # 1-based line number of the first body line


def parse(text):
    text = text.lstrip("﻿").replace("\r\n", "\n")
    lines = text.split("\n")
    if lines[0].strip() != "---":
        return Parsed({}, text, [(1, "missing frontmatter")], 1)
    end = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), None)
    if end is None:
        return Parsed({}, text, [(1, "frontmatter is not closed with ---")], 1)
    data, errors = {}, []
    for number, raw in enumerate(lines[1:end], start=2):
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        match = KEY_RE.match(raw)
        if not match:
            errors.append((number, "unsupported frontmatter syntax: %r" % raw.strip()))
            continue
        key, value = match.group(1), (match.group(2) or "").strip()
        if key in data:
            errors.append((number, "duplicate key: %s" % key))
            continue
        data[key] = _value(value, number, errors)
    return Parsed(data, "\n".join(lines[end + 1:]), errors, end + 2)


def _unquote(value):
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value


def _value(value, number, errors):
    if value[:1] in UNSUPPORTED_START:
        errors.append((number, "unsupported value syntax: %r" % value))
        return ""
    if value[:1] in ("\"", "'"):
        if len(value) >= 2 and value.endswith(value[0]):
            return value[1:-1]
        errors.append((number, "unterminated quoted value"))
        return ""
    value = COMMENT_RE.sub("", value).strip()
    if value.startswith("[[") and value.endswith("]]"):
        return value
    if value.startswith("["):
        if not value.endswith("]"):
            errors.append((number, "unterminated inline list"))
            return []
        return [_unquote(item.strip()) for item in value[1:-1].split(",") if item.strip()]
    return value
```

- [ ] **Step 4: Implement link extraction**

`plugins/second-brain/lib/sb/links.py`:

```python
"""Wikilink extraction. Links inside fenced code and inline code are ignored (spec 4.3)."""
import re

WIKILINK = re.compile(r"\[\[([^\[\]|#\n]+)(?:#[^\[\]|\n]*)?(?:\|[^\[\]\n]*)?\]\]")
INLINE_CODE = re.compile(r"`[^`\n]*`")


def target_name(raw):
    """`wiki/Resources/Foo.md` / `Foo.md` / `Foo` -> `Foo`."""
    name = raw.strip().rsplit("/", 1)[-1]
    return name[:-3] if name.endswith(".md") else name


def prose_lines(body, first_line=1):
    """Yield (line_number, text) for lines outside fenced code, with inline code removed."""
    fence = None
    for number, line in enumerate(body.split("\n"), start=first_line):
        stripped = line.lstrip()
        if fence:
            if stripped.startswith(fence):
                fence = None
            continue
        if stripped.startswith(("```", "~~~")):
            fence = stripped[:3]
            continue
        yield number, INLINE_CODE.sub("", line)


def extract(body, first_line=1):
    """Return [(line_number, target_name)] for every wikilink in prose."""
    found = []
    for number, line in prose_lines(body, first_line):
        for match in WIKILINK.finditer(line):
            found.append((number, target_name(match.group(1))))
    return found
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash tests/sb_cli_test.sh`
Expected: PASS (`ok second-brain unit tests`).

- [ ] **Step 6: Checkpoint** — ask the user whether to commit. Suggested message: `feat(second-brain): frontmatter subset parser and wikilink extraction`.

---

### Task 3: Vault model, atomic writes, index and log

**Files:**
- Create: `plugins/second-brain/lib/sb/vault.py`, `fsutil.py`, `index.py`, `logfile.py`
- Test: `tests/python/test_sb_vault.py`, `tests/python/test_sb_index_log.py`

**Interfaces:**
- Consumes: `frontmatter.parse`, `Parsed`.
- Produces:
  - `vault.MARKER = ".second-brain.json"`, `vault.SCHEMA_VERSION = 1`, `vault.VaultError`, `vault.Note(path, rel, name, data, body, body_line, errors)`, `vault.find_vault(start) -> Path|None`, `vault.load_config(root) -> dict`, `vault.load_note(root, path) -> Note`, `vault.load_notes(root) -> list[Note]` (every `*.md` under `wiki/`, sorted, skipping dot-folders).
  - `fsutil.write_atomic(path, text)`.
  - `index.build(notes) -> str`, `index.drift(root, notes) -> str` (unified diff, `""` when in sync), `index.summary_of(note) -> str`, `index.HEADER`.
  - `logfile.EVENTS`, `logfile.append(root, event, title, today=None)`.

- [ ] **Step 1: Write the failing tests**

`tests/python/test_sb_vault.py`:

```python
import tempfile
import unittest
from pathlib import Path

from sb_helpers import make_vault, note
from sb.vault import MARKER, VaultError, find_vault, load_config, load_notes


class VaultTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def test_find_vault_walks_up_from_a_subfolder(self):
        root = make_vault(self.tmp.name, {"Areas/A.md": note("A")})
        deep = root / "wiki" / "Areas"
        self.assertEqual(find_vault(deep), root.resolve())

    def test_find_vault_returns_none_outside_a_vault(self):
        self.assertIsNone(find_vault(self.tmp.name))

    def test_load_config_rejects_malformed_json(self):
        root = make_vault(self.tmp.name)
        (root / MARKER).write_text("{not json", encoding="utf-8")
        with self.assertRaises(VaultError):
            load_config(root)

    def test_load_notes_skips_dot_folders_and_reports_unreadable_files(self):
        root = make_vault(self.tmp.name, {"Resources/A.md": note("A")})
        (root / "wiki" / ".obsidian").mkdir()
        (root / "wiki" / ".obsidian" / "x.md").write_text("junk", encoding="utf-8")
        (root / "wiki" / "Resources" / "Bin.md").write_bytes(b"\xff\xfe\x00bad")
        notes = {n.name: n for n in load_notes(root)}
        self.assertEqual(sorted(notes), ["A", "Bin"])
        self.assertIn("unreadable", notes["Bin"].errors[0][1])
        self.assertEqual(notes["A"].rel, "wiki/Resources/A.md")

    def test_load_notes_on_a_vault_without_wiki_dir(self):
        root = Path(self.tmp.name)
        (root / MARKER).write_text("{}", encoding="utf-8")
        self.assertEqual(load_notes(root), [])


if __name__ == "__main__":
    unittest.main()
```

`tests/python/test_sb_index_log.py`:

```python
import os
import tempfile
import unittest
from pathlib import Path

from sb_helpers import make_vault, note
from sb import index, logfile
from sb.fsutil import write_atomic
from sb.vault import load_notes


class IndexTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def test_build_is_sorted_casefolded_and_flags_missing_summary(self):
        root = make_vault(self.tmp.name, {
            "Resources/b.md": note("b", summary="Second."),
            "Resources/A.md": note("A", summary="First."),
            "Resources/C.md": note("C", summary=None),
        }, index=False)
        text = index.build(load_notes(root))
        self.assertTrue(text.startswith(index.HEADER))
        self.assertEqual(text[len(index.HEADER):].splitlines(),
                         ["- [[A]]: First.", "- [[b]]: Second.", "- [[C]]: (no summary)"])

    def test_build_is_deterministic(self):
        root = make_vault(self.tmp.name, {"R/A.md": note("A"), "R/B.md": note("B")})
        notes = load_notes(root)
        self.assertEqual(index.build(notes), index.build(list(reversed(notes))))

    def test_drift_is_empty_when_synced_and_a_diff_otherwise(self):
        root = make_vault(self.tmp.name, {"R/A.md": note("A")})
        self.assertEqual(index.drift(root, load_notes(root)), "")
        (root / "wiki" / "R" / "B.md").write_text(note("B"), encoding="utf-8")
        diff = index.drift(root, load_notes(root))
        self.assertIn("+- [[B]]: A summary.", diff)

    def test_missing_index_file_counts_as_drift(self):
        root = make_vault(self.tmp.name, {"R/A.md": note("A")}, index=False)
        self.assertNotEqual(index.drift(root, load_notes(root)), "")

    def test_write_atomic_replaces_file_and_leaves_no_temp_files(self):
        target = Path(self.tmp.name) / "x.md"
        write_atomic(target, "one\n")
        write_atomic(target, "two\n")
        self.assertEqual(target.read_text(encoding="utf-8"), "two\n")
        self.assertEqual(os.listdir(self.tmp.name), ["x.md"])


class LogTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def test_append_format_and_preserves_history(self):
        logfile.append(self.root, "ingest", "First  note", today="2026-09-30")
        logfile.append(self.root, "update", "Second", today="2026-10-01")
        self.assertEqual((self.root / "_log.md").read_text(encoding="utf-8"),
                         "## [2026-09-30] ingest | First note\n"
                         "## [2026-10-01] update | Second\n")

    def test_append_adds_missing_trailing_newline(self):
        (self.root / "_log.md").write_text("## [2026-01-01] init | x", encoding="utf-8")
        logfile.append(self.root, "link", "y", today="2026-01-02")
        self.assertEqual((self.root / "_log.md").read_text(encoding="utf-8").count("\n"), 2)

    def test_unknown_event_is_rejected(self):
        with self.assertRaises(ValueError):
            logfile.append(self.root, "delete", "x")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/sb_cli_test.sh`
Expected: FAIL — `ModuleNotFoundError: No module named 'sb.vault'`.

- [ ] **Step 3: Implement**

`plugins/second-brain/lib/sb/fsutil.py`:

```python
"""File helpers."""
import os
from pathlib import Path


def write_atomic(path, text):
    """Write text to a temp file beside `path`, then rename it into place."""
    path = Path(path)
    tmp = path.with_name(".%s.tmp-%d" % (path.name, os.getpid()))
    with open(tmp, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
    os.replace(tmp, path)
```

`plugins/second-brain/lib/sb/vault.py`:

```python
"""Vault discovery and note loading."""
import json
from dataclasses import dataclass
from pathlib import Path

from .frontmatter import parse

MARKER = ".second-brain.json"
SCHEMA_VERSION = 1


class VaultError(Exception):
    pass


@dataclass
class Note:
    path: Path
    rel: str          # posix path relative to the vault root
    name: str         # basename without .md; the wikilink target
    data: dict
    body: str
    body_line: int
    errors: list


def find_vault(start):
    """Return the nearest directory at or above `start` that holds the marker, or None."""
    here = Path(start).resolve()
    for candidate in (here, *here.parents):
        if (candidate / MARKER).is_file():
            return candidate
    return None


def load_config(root):
    try:
        data = json.loads((Path(root) / MARKER).read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise VaultError("cannot read %s: %s" % (MARKER, exc)) from exc
    if not isinstance(data, dict):
        raise VaultError("%s must hold a JSON object" % MARKER)
    return data


def load_note(root, path):
    root, path = Path(root), Path(path)
    rel = path.relative_to(root).as_posix()
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        return Note(path, rel, path.stem, {}, "", 1, [(1, "unreadable file: %s" % exc)])
    parsed = parse(text)
    return Note(path, rel, path.stem, parsed.data, parsed.body, parsed.body_line, parsed.errors)


def load_notes(root):
    root = Path(root)
    wiki = root / "wiki"
    if not wiki.is_dir():
        return []
    notes = []
    for path in sorted(wiki.rglob("*.md")):
        if any(part.startswith(".") for part in path.relative_to(wiki).parts):
            continue
        notes.append(load_note(root, path))
    return notes
```

`plugins/second-brain/lib/sb/index.py`:

```python
"""Deterministic _index.md generation (spec 4.3)."""
import difflib
from pathlib import Path

HEADER = "<!-- generated by `sb index --write`; manual edits are overwritten -->\n\n"


def summary_of(note):
    text = " ".join(str(note.data.get("summary", "")).split())
    return text or "(no summary)"


def build(notes):
    ordered = sorted(notes, key=lambda n: (n.name.casefold(), n.name))
    return HEADER + "".join("- [[%s]]: %s\n" % (n.name, summary_of(n)) for n in ordered)


def drift(root, notes):
    """Unified diff between the current _index.md and the expected one; "" when in sync."""
    expected = build(notes)
    path = Path(root) / "_index.md"
    try:
        actual = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        actual = ""
    if actual == expected:
        return ""
    return "".join(difflib.unified_diff(actual.splitlines(True), expected.splitlines(True),
                                        "_index.md", "expected"))
```

`plugins/second-brain/lib/sb/logfile.py`:

```python
"""Append-only _log.md (spec 4.3)."""
from datetime import date
from pathlib import Path

from .fsutil import write_atomic

EVENTS = ("init", "capture", "ingest", "update", "link", "lint")


def append(root, event, title, today=None):
    if event not in EVENTS:
        raise ValueError("unknown log event %r (expected one of %s)" % (event, ", ".join(EVENTS)))
    title = " ".join(str(title).split())
    line = "## [%s] %s | %s\n" % (today or date.today().isoformat(), event, title)
    path = Path(root) / "_log.md"
    try:
        existing = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        existing = ""
    if existing and not existing.endswith("\n"):
        existing += "\n"
    write_atomic(path, existing + line)
```

- [ ] **Step 4: Run to verify pass**

Run: `bash tests/sb_cli_test.sh`
Expected: PASS.

- [ ] **Step 5: Checkpoint** — ask the user whether to commit. Suggested message: `feat(second-brain): vault model, deterministic index and append-only log`.

---

### Task 4: Lint rules SB101–SB109

**Files:**
- Create: `plugins/second-brain/lib/sb/lint.py`
- Test: `tests/python/test_sb_lint.py`

**Interfaces:**
- Consumes: `vault.load_notes`, `vault.SCHEMA_VERSION`, `links.extract`, `links.target_name`, `index.drift`.
- Produces: `lint.Finding(code, path, line, message)` (frozen dataclass; `.as_dict()`, `str()` → `path:line: CODE message`), `lint.check_note(note) -> list[Finding]` (SB108 + SB102 only; used by `validate` and the PostToolUse hook), `lint.lint(root, config) -> list[Finding]` sorted by `(path, line, code)`.

- [ ] **Step 1: Write the failing tests**

`tests/python/test_sb_lint.py`:

```python
import tempfile
import unittest

from sb_helpers import make_vault, note
from sb.lint import lint
from sb.vault import load_config

PAIR = {
    "Resources/A.md": note("A", body="see [[B]]"),
    "Resources/B.md": note("B", body="see [[A]]"),
}


def run(root):
    return lint(root, load_config(root))


class LintTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def vault(self, extra=None, **kwargs):
        notes = dict(PAIR)
        notes.update(extra or {})
        return make_vault(self.tmp.name, notes, **kwargs)

    def codes(self, findings, path=None):
        return [f.code for f in findings if path is None or f.path == path]

    def test_clean_vault_has_no_findings(self):
        self.assertEqual(run(self.vault()), [])

    def test_sb101_broken_link_reports_the_body_line(self):
        root = self.vault({"Resources/C.md": note("C", body="x\n[[Missing]] and [[A]]")})
        found = [f for f in run(root) if f.code == "SB101"]
        self.assertEqual([(f.path, f.line) for f in found], [("wiki/Resources/C.md", 11)])

    def test_links_in_code_are_not_broken_links(self):
        root = self.vault({"Resources/C.md": note("C", body="`[[Nope]]`\n```\n[[Nope2]]\n```\n[[A]]")})
        self.assertNotIn("SB101", self.codes(run(root)))

    def test_sb102_missing_or_empty_summary_without_a_duplicate_sb108(self):
        root = self.vault({"Resources/C.md": note("C", summary=None, body="[[A]]"),
                           "Resources/D.md": note("D", summary="", body="[[A]]")})
        findings = run(root)
        self.assertEqual(self.codes(findings, "wiki/Resources/C.md"), ["SB102"])
        self.assertEqual(self.codes(findings, "wiki/Resources/D.md"), ["SB102"])

    def test_sb103_orphan(self):
        root = self.vault({"Resources/C.md": note("C")})
        orphans = [f.path for f in run(root) if f.code == "SB103"]
        self.assertEqual(orphans, ["wiki/Resources/C.md"])

    def test_a_self_link_does_not_save_an_orphan(self):
        root = self.vault({"Resources/C.md": note("C", body="[[C]]")})
        self.assertIn("SB103", self.codes(run(root), "wiki/Resources/C.md"))

    def test_sb104_duplicate_basename_and_duplicate_title(self):
        root = self.vault({"Areas/A.md": note("Other", body="[[A]]"),
                           "Resources/X.md": note("Same", body="[[A]]"),
                           "Resources/Y.md": note("same", body="[[A]]")})
        paths = sorted(f.path for f in run(root) if f.code == "SB104")
        self.assertEqual(paths, ["wiki/Areas/A.md", "wiki/Resources/A.md",
                                 "wiki/Resources/X.md", "wiki/Resources/Y.md"])

    def test_sb105_index_drift_and_missing_index(self):
        self.assertIn("SB105", self.codes(run(self.vault(index=False))))
        self.assertNotIn("SB105", self.codes(run(make_vault(self.tmp.name + "/ok", dict(PAIR)))))

    def test_sb106_agent_note_needs_review(self):
        root = self.vault({"Resources/C.md": note("C", origin="agent", body="[[A]]"),
                           "Resources/D.md": note("D", origin="agent", reviewed="2026-10-01", body="[[A]]")})
        findings = run(root)
        self.assertIn("SB106", self.codes(findings, "wiki/Resources/C.md"))
        self.assertNotIn("SB106", self.codes(findings, "wiki/Resources/D.md"))

    def test_sb107_outdated_schema_version(self):
        root = self.vault(config={"schema_version": 0})
        self.assertIn("SB107", self.codes(run(root)))

    def test_sb108_frontmatter_problems(self):
        root = self.vault({
            "Resources/E1.md": note("E1", status="done", body="[[A]]"),
            "Resources/E2.md": note("E2", created="2026-13-45", body="[[A]]"),
            "Resources/E3.md": note("E3", created=None, body="[[A]]"),
            "Resources/E4.md": "---\ntitle: E4\nsummary: s\nextra:\n  nested: 1\n---\n[[A]]\n",
            "Resources/E5.md": "# no frontmatter\n[[A]]\n",
        })
        findings = run(root)
        for name in ("E1", "E2", "E3", "E4", "E5"):
            self.assertIn("SB108", self.codes(findings, "wiki/Resources/%s.md" % name), name)

    def test_sb109_source_must_exist(self):
        root = self.vault({
            "Resources/S1.md": note("S1", source="_raw/missing.pdf", body="[[A]]"),
            "Resources/S2.md": note("S2", source="_raw/here.pdf", body="[[A]]"),
            "Resources/S3.md": note("S3", source="[[Nope]]", body="[[A]]"),
            "Resources/S4.md": note("S4", source="[[A]]", body="[[A]]"),
            "Resources/S5.md": note("S5", source="https://example.com/x", body="[[A]]"),
        }, index=False)
        (root / "_raw" / "here.pdf").write_bytes(b"%PDF")
        findings = run(root)
        flagged = sorted(f.path for f in findings if f.code == "SB109")
        self.assertEqual(flagged, ["wiki/Resources/S1.md", "wiki/Resources/S3.md"])

    def test_accented_and_spaced_names_resolve(self):
        root = make_vault(self.tmp.name, {
            "Resources/Café Noir.md": note("Café Noir", body="see [[B]]"),
            "Resources/B.md": note("B", body="see [[Café Noir]] and [[café noir|alias]]"),
        })
        broken = [f.message for f in run(root) if f.code == "SB101"]
        self.assertEqual(broken, ["broken link: [[café noir]]"])

    def test_binary_note_is_reported_without_aborting(self):
        root = self.vault()
        (root / "wiki" / "Resources" / "Bin.md").write_bytes(b"\xff\xfe\x00bad")
        findings = run(root)
        self.assertIn("SB108", self.codes(findings, "wiki/Resources/Bin.md"))
        self.assertIn("SB108", self.codes(findings))


if __name__ == "__main__":
    unittest.main()
```

Notes on expectations: `note()` puts the body at line 10 of the file, so `x\n[[Missing]]…` puts the link on line 11. `test_sb105…` builds a second vault under `self.tmp.name + "/ok"` (create the parent: `make_vault` calls `mkdir(parents=True)` for subfolders; add `os.makedirs` inside the test if the directory does not exist — see Step 3 note). In `test_accented…` the lowercase link `[[café noir]]` is deliberately broken: resolution is case-sensitive (spec §4.3).

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/sb_cli_test.sh`
Expected: FAIL — `ModuleNotFoundError: No module named 'sb.lint'`.

- [ ] **Step 3: Implement**

If `test_sb105…` fails with `FileNotFoundError` for `self.tmp.name + "/ok"`, add `import os` and `os.makedirs(self.tmp.name + "/ok")` before that `make_vault` call (the helper only creates the vault subfolders, not the root).

`plugins/second-brain/lib/sb/lint.py`:

```python
"""Deterministic lint rules SB101-SB109 (spec section 5)."""
import re
from collections import defaultdict
from dataclasses import asdict, dataclass
from datetime import date

from . import index as index_mod
from .links import extract, target_name
from .vault import SCHEMA_VERSION, load_notes

REQUIRED = ("title", "summary", "type", "status", "origin", "created")
ENUMS = {
    "type": {"nota", "fonte", "projeto", "conceito"},
    "status": {"seed", "draft", "evergreen"},
    "origin": {"agent", "human", "mixed"},
}
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


@dataclass(frozen=True)
class Finding:
    code: str
    path: str
    line: int
    message: str

    def as_dict(self):
        return asdict(self)

    def __str__(self):
        return "%s:%d: %s %s" % (self.path, self.line, self.code, self.message)


def _is_date(value):
    if not isinstance(value, str) or not DATE_RE.match(value):
        return False
    try:
        date.fromisoformat(value)
    except ValueError:
        return False
    return True


def check_note(note):
    """Frontmatter checks for one note: SB108 and SB102."""
    out = [Finding("SB108", note.rel, line, message) for line, message in note.errors]
    if not note.data and note.errors:
        return out
    for key in REQUIRED:
        value = note.data.get(key)
        if key == "summary":
            if not str(value or "").strip():
                out.append(Finding("SB102", note.rel, 1, "summary is missing or empty"))
        elif value is None or value == "":
            out.append(Finding("SB108", note.rel, 1, "missing required key: %s" % key))
    for key, allowed in ENUMS.items():
        value = note.data.get(key)
        if value and (not isinstance(value, str) or value not in allowed):
            out.append(Finding("SB108", note.rel, 1,
                               "%s must be one of %s, got %r" % (key, sorted(allowed), value)))
    for key in ("created", "reviewed"):
        value = note.data.get(key)
        if value and not _is_date(value):
            out.append(Finding("SB108", note.rel, 1, "%s must be an ISO date, got %r" % (key, value)))
    return out


def _source_finding(root, note, known):
    source = str(note.data.get("source", "")).strip()
    if not source or source.startswith(("http://", "https://")):
        return []
    if source.startswith("[[") and source.endswith("]]"):
        ok = target_name(source[2:-2].split("|")[0].split("#")[0]) in known
    else:
        ok = (root / source).exists()
    if ok:
        return []
    return [Finding("SB109", note.rel, 1, "source does not exist: %s" % source)]


def lint(root, config):
    notes = load_notes(root)
    findings = []
    by_name, by_title = defaultdict(list), defaultdict(list)
    for note in notes:
        by_name[note.name].append(note)
        title = str(note.data.get("title", "")).strip()
        if title:
            by_title[title.casefold()].append(note)
    known = set(by_name)
    inbound = defaultdict(set)

    for note in notes:
        findings += check_note(note)
        for line, target in extract(note.body, note.body_line):
            if target not in known:
                findings.append(Finding("SB101", note.rel, line, "broken link: [[%s]]" % target))
            elif target != note.name:
                inbound[target].add(note.name)
        if note.data.get("origin") == "agent" and not note.data.get("reviewed"):
            findings.append(Finding("SB106", note.rel, 1,
                                    "agent-written note has no `reviewed` date"))
        findings += _source_finding(root, note, known)

    for note in notes:
        if note.name not in inbound:
            findings.append(Finding("SB103", note.rel, 1, "orphan note: nothing links here"))

    for name, group in by_name.items():
        if len(group) > 1:
            for note in group:
                findings.append(Finding("SB104", note.rel, 1, "duplicate note name %r" % name))
    for group in by_title.values():
        if len({n.name for n in group}) > 1:
            for note in group:
                findings.append(Finding("SB104", note.rel, 1, "duplicate title across notes"))

    if index_mod.drift(root, notes):
        findings.append(Finding("SB105", "_index.md", 1,
                                "_index.md is out of sync; run `sb index --write`"))
    try:
        version = int(config.get("schema_version", 0))
    except (TypeError, ValueError):
        version = 0
    if version < SCHEMA_VERSION:
        findings.append(Finding("SB107", ".second-brain.json", 1,
                                "schema_version %s is older than %d" % (version, SCHEMA_VERSION)))
    return sorted(findings, key=lambda f: (f.path, f.line, f.code))
```

- [ ] **Step 4: Run to verify pass**

Run: `bash tests/sb_cli_test.sh`
Expected: PASS. If a test fails because of the line-number arithmetic in `test_sb101…`, recount the fixture: `note()` emits 9 header lines (`---`, title, summary, type, status, origin, created, source, `---`), so the first body line is 10.

- [ ] **Step 5: Checkpoint** — ask the user whether to commit. Suggested message: `feat(second-brain): lint rules SB101-SB109`.

---

### Task 5: `sb` CLI and executable shim

**Files:**
- Create: `plugins/second-brain/lib/sb/cli.py`, `plugins/second-brain/bin/sb`
- Test: `tests/python/test_sb_cli.py`

**Interfaces:**
- Consumes: everything from Tasks 2–4; `init.run` from Task 6 is imported lazily inside `cmd_init` so this task does not depend on it.
- Produces: `cli.main(argv=None, out=None, err=None) -> int`; subcommands `index --write|--check`, `lint`, `links NOTE [--suggest]`, `validate FILE...`, `log EVENT TITLE`, `init [--language L] [--areas a,b] [--git]`; common options `--vault PATH`, `--json`.

- [ ] **Step 1: Write the failing tests**

`tests/python/test_sb_cli.py`:

```python
import io
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from sb_helpers import PLUGIN, make_vault, note
from sb.cli import main


def run(*argv):
    out, err = io.StringIO(), io.StringIO()
    code = main(list(argv), out=out, err=err)
    return code, out.getvalue(), err.getvalue()


class CliTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = make_vault(self.tmp.name, {
            "Resources/A.md": note("A", body="see [[B]] and Gamma Ray"),
            "Resources/B.md": note("B", body="see [[A]]"),
            "Resources/Gamma Ray.md": note("Gamma Ray", body="[[A]]"),
        })

    def test_outside_a_vault_exits_2_with_a_hint(self):
        empty = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, empty)
        code, _, err = run("lint", "--vault", empty)
        self.assertEqual(code, 2)
        self.assertIn("not a second-brain vault", err)

    def test_vault_is_discovered_from_the_working_directory(self):
        old = os.getcwd()
        os.chdir(self.root / "wiki" / "Resources")
        self.addCleanup(os.chdir, old)
        self.assertEqual(run("lint")[0], 0)

    def test_index_write_then_check(self):
        (self.root / "_index.md").write_text("stale", encoding="utf-8")
        self.assertEqual(run("index", "--check", "--vault", str(self.root))[0], 1)
        self.assertEqual(run("index", "--write", "--vault", str(self.root))[0], 0)
        code, out, _ = run("index", "--check", "--json", "--vault", str(self.root))
        self.assertEqual((code, json.loads(out)["in_sync"]), (0, True))

    def test_lint_text_and_json(self):
        (self.root / "wiki" / "Resources" / "A.md").write_text(
            note("A", summary=None, body="see [[B]] [[Nope]]"), encoding="utf-8")
        code, out, _ = run("lint", "--vault", str(self.root))
        self.assertEqual(code, 1)
        self.assertIn("SB102", out)
        code, out, _ = run("lint", "--json", "--vault", str(self.root))
        self.assertEqual(code, 1)
        self.assertTrue({"SB101", "SB102"} <= {f["code"] for f in json.loads(out)})

    def test_lint_on_malformed_marker_exits_2(self):
        (self.root / ".second-brain.json").write_text("{nope", encoding="utf-8")
        code, _, err = run("lint", "--vault", str(self.root))
        self.assertEqual(code, 2)
        self.assertIn("cannot read", err)

    def test_links_outgoing_backlinks_and_suggestions(self):
        code, out, _ = run("links", "A", "--suggest", "--json", "--vault", str(self.root))
        self.assertEqual(code, 0)
        data = json.loads(out)
        self.assertEqual([o["target"] for o in data["outgoing"]], ["B"])
        self.assertEqual(data["backlinks"], ["B", "Gamma Ray"])
        self.assertEqual([s["name"] for s in data["suggestions"]], ["Gamma Ray"])

    def test_links_accepts_a_path_and_rejects_unknown_notes(self):
        self.assertEqual(run("links", "wiki/Resources/A.md", "--vault", str(self.root))[0], 0)
        code, _, err = run("links", "Nope", "--vault", str(self.root))
        self.assertEqual(code, 2)
        self.assertIn("note not found", err)

    def test_validate_checks_wiki_notes_only(self):
        bad = self.root / "wiki" / "Resources" / "Bad.md"
        bad.write_text(note("Bad", summary=None), encoding="utf-8")
        outside = self.root / "_inbox" / "x.md"
        outside.write_text("no frontmatter", encoding="utf-8")
        self.assertEqual(run("validate", str(bad), "--vault", str(self.root))[0], 1)
        self.assertEqual(run("validate", str(outside), "--vault", str(self.root))[0], 0)
        self.assertEqual(run("validate", str(self.root / "wiki" / "Resources" / "A.md"),
                             "--vault", str(self.root))[0], 0)

    def test_log_appends_and_rejects_unknown_events(self):
        self.assertEqual(run("log", "ingest", "My note", "--vault", str(self.root))[0], 0)
        self.assertIn("ingest | My note", (self.root / "_log.md").read_text(encoding="utf-8"))
        self.assertEqual(run("log", "bogus", "x", "--vault", str(self.root))[0], 2)

    def test_executable_shim_runs(self):
        shim = PLUGIN / "bin" / "sb"
        self.assertTrue(os.access(shim, os.X_OK))
        done = subprocess.run([str(shim), "lint", "--vault", str(self.root)],
                              capture_output=True, text=True)
        self.assertEqual((done.returncode, done.stdout), (0, ""))

    def test_ripgrep_finds_notes_under_underscore_folders(self):
        if not shutil.which("rg"):
            self.skipTest("ripgrep not installed")
        (self.root / "_inbox" / "_done" / "x.md").write_text("hello", encoding="utf-8")
        found = subprocess.run(["rg", "--files", "_inbox"], cwd=self.root,
                               capture_output=True, text=True).stdout
        self.assertIn("_inbox/_done/x.md", found)


class EmptyVaultTests(unittest.TestCase):
    def test_fresh_empty_vault_is_clean(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = make_vault(tmp)
            self.assertEqual(run("lint", "--vault", str(root))[0], 0)
            self.assertEqual(run("index", "--check", "--vault", str(root))[0], 0)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/sb_cli_test.sh`
Expected: FAIL — `ModuleNotFoundError: No module named 'sb.cli'`.

- [ ] **Step 3: Implement the CLI**

`plugins/second-brain/lib/sb/cli.py`:

```python
"""Command-line interface for the second-brain vault (spec section 5)."""
import argparse
import json
import re
import sys
from pathlib import Path

from . import index as index_mod
from . import logfile
from .fsutil import write_atomic
from .lint import check_note, lint as run_lint
from .links import WIKILINK, extract, prose_lines, target_name
from .vault import MARKER, VaultError, find_vault, load_config, load_note, load_notes

EXIT_OK, EXIT_FINDINGS, EXIT_USAGE = 0, 1, 2


def _vault(args, err):
    if args.vault:
        root = Path(args.vault).resolve()
        if not (root / MARKER).is_file():
            print("sb: %s is not a second-brain vault (%s not found)" % (root, MARKER), file=err)
            return None
        return root
    root = find_vault(Path.cwd())
    if root is None:
        print("sb: no %s found from %s upward; run /second-brain:init" % (MARKER, Path.cwd()),
              file=err)
    return root


def _emit(args, out, payload, text=""):
    if args.json:
        json.dump(payload, out, ensure_ascii=False, indent=2)
        out.write("\n")
    elif text:
        out.write(text.rstrip("\n") + "\n")


def cmd_index(args, out, err):
    root = _vault(args, err)
    if root is None:
        return EXIT_USAGE
    notes = load_notes(root)
    if args.write:
        write_atomic(root / "_index.md", index_mod.build(notes))
        _emit(args, out, {"notes": len(notes), "written": True},
              "wrote _index.md (%d notes)" % len(notes))
        return EXIT_OK
    diff = index_mod.drift(root, notes)
    _emit(args, out, {"in_sync": not diff, "diff": diff}, diff)
    return EXIT_FINDINGS if diff else EXIT_OK


def cmd_lint(args, out, err):
    root = _vault(args, err)
    if root is None:
        return EXIT_USAGE
    try:
        config = load_config(root)
    except VaultError as exc:
        print("sb: %s" % exc, file=err)
        return EXIT_USAGE
    findings = run_lint(root, config)
    _emit(args, out, [f.as_dict() for f in findings], "\n".join(str(f) for f in findings))
    return EXIT_FINDINGS if findings else EXIT_OK


def cmd_validate(args, out, err):
    root = _vault(args, err)
    if root is None:
        return EXIT_USAGE
    wiki = root / "wiki"
    findings = []
    for name in args.files:
        path = Path(name).resolve()
        try:
            path.relative_to(wiki)
        except ValueError:
            continue
        if path.suffix == ".md":
            findings += check_note(load_note(root, path))
    _emit(args, out, [f.as_dict() for f in findings], "\n".join(str(f) for f in findings))
    return EXIT_FINDINGS if findings else EXIT_OK


def _suggestions(note, notes):
    linked = {target for _, target in extract(note.body, note.body_line)}
    found = []
    for other in notes:
        if other.name == note.name or other.name in linked:
            continue
        terms = {other.name, str(other.data.get("title", "")).strip()} - {""}
        patterns = [re.compile(r"(?<!\w)%s(?!\w)" % re.escape(t)) for t in terms if len(t) >= 3]
        hit = None
        for number, line in prose_lines(note.body, note.body_line):
            text = WIKILINK.sub("", line)
            term = next((p.pattern for p in patterns if p.search(text)), None)
            if term:
                hit = (number, next(t for t in terms if re.escape(t) in term))
                break
        if hit:
            found.append({"name": other.name, "term": hit[1], "line": hit[0]})
    return found


def cmd_links(args, out, err):
    root = _vault(args, err)
    if root is None:
        return EXIT_USAGE
    notes = load_notes(root)
    by_name = {n.name: n for n in notes}
    wanted = target_name(args.note)
    note = by_name.get(wanted)
    if note is None:
        print("sb: note not found: %s" % args.note, file=err)
        return EXIT_USAGE
    outgoing = [{"target": t, "line": line, "resolved": t in by_name}
                for line, t in extract(note.body, note.body_line)]
    backlinks = sorted(n.name for n in notes if n.name != wanted and
                       any(t == wanted for _, t in extract(n.body, n.body_line)))
    payload = {"note": note.rel, "outgoing": outgoing, "backlinks": backlinks,
               "unresolved": sorted({o["target"] for o in outgoing if not o["resolved"]})}
    if args.suggest:
        payload["suggestions"] = _suggestions(note, notes)
    text = ["%s" % note.rel,
            "outgoing: %s" % (", ".join(o["target"] for o in outgoing) or "-"),
            "backlinks: %s" % (", ".join(backlinks) or "-"),
            "unresolved: %s" % (", ".join(payload["unresolved"]) or "-")]
    for s in payload.get("suggestions", []):
        text.append("suggest [[%s]] (line %d, matched %r)" % (s["name"], s["line"], s["term"]))
    _emit(args, out, payload, "\n".join(text))
    return EXIT_OK


def cmd_log(args, out, err):
    root = _vault(args, err)
    if root is None:
        return EXIT_USAGE
    try:
        logfile.append(root, args.event, args.title)
    except ValueError as exc:
        print("sb: %s" % exc, file=err)
        return EXIT_USAGE
    return EXIT_OK


def cmd_init(args, out, err):
    from . import init as init_mod

    target = Path(args.vault).resolve() if args.vault else Path.cwd()
    parent = find_vault(target)
    if parent is not None and parent != target:
        print("sb: %s is inside the existing vault %s" % (target, parent), file=err)
        return EXIT_USAGE
    areas = [a for a in args.areas.split(",") if a.strip()]
    result = init_mod.run(target, language=args.language, areas=areas, git=args.git)
    lines = ["%s: %s" % (result["status"], target)]
    if result["created"]:
        lines.append("created: " + ", ".join(result["created"]))
    if result["kept"]:
        lines.append("kept: " + ", ".join(result["kept"]))
    lines += ["warning: " + w for w in result["warnings"]]
    _emit(args, out, result, "\n".join(lines))
    return EXIT_OK


def build_parser():
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--vault", help="vault root (default: nearest %s upward)" % MARKER)
    common.add_argument("--json", action="store_true", help="machine-readable output")

    parser = argparse.ArgumentParser(prog="sb", description="second-brain vault tooling")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("index", parents=[common], help="rebuild or check _index.md")
    group = p.add_mutually_exclusive_group(required=True)
    group.add_argument("--write", action="store_true")
    group.add_argument("--check", action="store_true")
    p.set_defaults(func=cmd_index)

    p = sub.add_parser("lint", parents=[common], help="run the lint rules")
    p.set_defaults(func=cmd_lint)

    p = sub.add_parser("links", parents=[common], help="links and backlinks of a note")
    p.add_argument("note", help="note name or path")
    p.add_argument("--suggest", action="store_true", help="list unlinked exact title mentions")
    p.set_defaults(func=cmd_links)

    p = sub.add_parser("validate", parents=[common], help="validate frontmatter of notes")
    p.add_argument("files", nargs="+")
    p.set_defaults(func=cmd_validate)

    p = sub.add_parser("log", parents=[common], help="append to _log.md")
    p.add_argument("event", choices=logfile.EVENTS)
    p.add_argument("title")
    p.set_defaults(func=cmd_log)

    p = sub.add_parser("init", parents=[common], help="create a vault in the target directory")
    p.add_argument("--language", default="en")
    p.add_argument("--areas", default="", help="comma-separated initial areas")
    p.add_argument("--git", action="store_true", help="run git init if there is no .git")
    p.set_defaults(func=cmd_init)
    return parser


def main(argv=None, out=None, err=None):
    out = out or sys.stdout
    err = err or sys.stderr
    try:
        args = build_parser().parse_args(argv)
    except SystemExit as exc:
        return exc.code if isinstance(exc.code, int) else EXIT_USAGE
    return args.func(args, out, err)
```

The `_suggestions` helper above reconstructs the matched term awkwardly; simplify it while implementing so it keeps one `(term, pattern)` list and returns the first matching term:

```python
        pairs = [(t, re.compile(r"(?<!\w)%s(?!\w)" % re.escape(t))) for t in terms if len(t) >= 3]
        hit = None
        for number, line in prose_lines(note.body, note.body_line):
            text = WIKILINK.sub("", line)
            term = next((t for t, pattern in pairs if pattern.search(text)), None)
            if term:
                hit = (number, term)
                break
```

`plugins/second-brain/bin/sb`:

```python
#!/usr/bin/env python3
"""Entry point for the second-brain CLI."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "lib"))

from sb.cli import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main())
```

Run `chmod +x plugins/second-brain/bin/sb`.

- [ ] **Step 4: Run to verify pass**

Run: `bash tests/sb_cli_test.sh`
Expected: PASS. (`cmd_init` is not exercised until Task 6.)

- [ ] **Step 5: Checkpoint** — ask the user whether to commit. Suggested message: `feat(second-brain): sb CLI (index, lint, links, validate, log)`.

---

### Task 6: `sb init` and the vault `CLAUDE.md` template

**Files:**
- Create: `plugins/second-brain/lib/sb/init.py`, `plugins/second-brain/templates/CLAUDE.md`
- Test: `tests/python/test_sb_init.py`

**Interfaces:**
- Consumes: `fsutil.write_atomic`, `index.build`, `logfile.append`, `vault.MARKER`, `vault.SCHEMA_VERSION`.
- Produces: `init.run(root, language="en", areas=(), git=False) -> {"status": "created"|"exists", "root": str, "created": [str], "kept": [str], "warnings": [str]}`. Writes the marker **last** (spec §7).

- [ ] **Step 1: Write the failing tests**

`tests/python/test_sb_init.py`:

```python
import json
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import sb_helpers  # noqa: F401
from sb import init
from sb.lint import lint
from sb.vault import MARKER, load_config


class InitTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / "vault"

    def test_creates_layout_marker_and_a_clean_vault(self):
        result = init.run(self.root, language="pt-BR", areas=["Saúde", "Finanças"])
        self.assertEqual(result["status"], "created")
        for rel in ("_inbox/_done", "_raw", "wiki/Projects", "wiki/Areas/Saúde",
                    "wiki/Areas/Finanças", "wiki/Resources", "wiki/Archive"):
            self.assertTrue((self.root / rel).is_dir(), rel)
        for rel in ("CLAUDE.md", "_index.md", "_log.md", ".gitignore", MARKER):
            self.assertTrue((self.root / rel).is_file(), rel)
        self.assertEqual(load_config(self.root),
                         {"schema_version": 1, "language": "pt-BR", "areas": ["Saúde", "Finanças"]})
        self.assertIn("pt-BR", (self.root / "CLAUDE.md").read_text(encoding="utf-8"))
        self.assertIn("init | vault created", (self.root / "_log.md").read_text(encoding="utf-8"))
        self.assertEqual(lint(self.root, load_config(self.root)), [])

    def test_vault_claude_md_is_under_200_lines(self):
        init.run(self.root)
        self.assertLess(len((self.root / "CLAUDE.md").read_text(encoding="utf-8").splitlines()), 200)

    def test_is_idempotent_and_never_touches_an_existing_marker_vault(self):
        init.run(self.root, language="en")
        (self.root / "CLAUDE.md").write_text("mine", encoding="utf-8")
        again = init.run(self.root, language="pt-BR")
        self.assertEqual(again["status"], "exists")
        self.assertEqual((self.root / "CLAUDE.md").read_text(encoding="utf-8"), "mine")
        self.assertEqual(load_config(self.root)["language"], "en")

    def test_never_overwrites_an_existing_claude_md(self):
        self.root.mkdir()
        (self.root / "CLAUDE.md").write_text("mine", encoding="utf-8")
        result = init.run(self.root)
        self.assertIn("CLAUDE.md", result["kept"])
        self.assertEqual((self.root / "CLAUDE.md").read_text(encoding="utf-8"), "mine")

    def test_gitignore_lines_are_appended_once(self):
        self.root.mkdir()
        (self.root / ".gitignore").write_text("node_modules/\n", encoding="utf-8")
        init.run(self.root)
        text = (self.root / ".gitignore").read_text(encoding="utf-8")
        self.assertEqual(text.splitlines(), ["node_modules/", ".obsidian/workspace*", ".smart-env/"])

    def test_invalid_area_names_are_skipped_with_a_warning(self):
        result = init.run(self.root, areas=["ok", "../escape", ".hidden", "a/b", "  "])
        self.assertEqual(load_config(self.root)["areas"], ["ok"])
        self.assertEqual(len(result["warnings"]), 3)
        self.assertFalse((Path(self.tmp.name) / "escape").exists())

    def test_marker_is_written_last(self):
        calls = []
        real = init.write_atomic

        def spy(path, text):
            calls.append(Path(path).name)
            real(path, text)

        with mock.patch.object(init, "write_atomic", spy):
            init.run(self.root)
        self.assertEqual(calls[-1], MARKER)
        self.assertLess(calls.index("CLAUDE.md"), calls.index(MARKER))

    @unittest.skipUnless(shutil.which("git"), "git not installed")
    def test_git_flag_runs_git_init(self):
        init.run(self.root, git=True)
        self.assertTrue((self.root / ".git").exists())


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/sb_cli_test.sh`
Expected: FAIL — `ImportError: cannot import name 'init' from 'sb'`.

- [ ] **Step 3: Implement**

`plugins/second-brain/lib/sb/init.py`:

```python
"""Vault scaffolding: the backend of /second-brain:init (spec section 7)."""
import json
import subprocess
from pathlib import Path

from . import index as index_mod
from . import logfile
from .fsutil import write_atomic
from .vault import MARKER, SCHEMA_VERSION

TEMPLATES = Path(__file__).resolve().parents[2] / "templates"
BASE_DIRS = ("_inbox/_done", "_raw", "wiki/Projects", "wiki/Areas", "wiki/Resources", "wiki/Archive")
GITIGNORE_LINES = (".obsidian/workspace*", ".smart-env/")


def _clean_area(area):
    name = " ".join(str(area).split())
    if not name or name.startswith(".") or "/" in name or "\\" in name:
        return ""
    return name


def _write_new(root, name, text, created, kept):
    path = root / name
    if path.exists():
        kept.append(name)
    else:
        write_atomic(path, text)
        created.append(name)


def _append_gitignore(root, created, kept):
    path = root / ".gitignore"
    existing = path.read_text(encoding="utf-8") if path.exists() else ""
    present = set(existing.splitlines())
    missing = [line for line in GITIGNORE_LINES if line not in present]
    if not missing:
        kept.append(".gitignore")
        return
    if existing and not existing.endswith("\n"):
        existing += "\n"
    write_atomic(path, existing + "".join(line + "\n" for line in missing))
    (kept if path.exists() and existing else created).append(".gitignore")


def run(root, language="en", areas=(), git=False):
    root = Path(root)
    if (root / MARKER).exists():
        return {"status": "exists", "root": str(root), "created": [], "kept": [MARKER],
                "warnings": []}
    root.mkdir(parents=True, exist_ok=True)
    created, kept, warnings = [], [], []

    clean = []
    for area in areas:
        name = _clean_area(area)
        if name:
            clean.append(name)
        else:
            warnings.append("ignored invalid area name %r" % area)
    for rel in (*BASE_DIRS, *("wiki/Areas/%s" % a for a in clean)):
        (root / rel).mkdir(parents=True, exist_ok=True)

    template = (TEMPLATES / "CLAUDE.md").read_text(encoding="utf-8")
    _write_new(root, "CLAUDE.md", template.replace("{{language}}", language), created, kept)
    _append_gitignore(root, created, kept)
    _write_new(root, "_index.md", index_mod.build([]), created, kept)
    _write_new(root, "_log.md", "", created, kept)

    if git and not (root / ".git").exists():
        try:
            subprocess.run(["git", "init", "-q", str(root)], check=True, capture_output=True)
            created.append(".git")
        except (OSError, subprocess.CalledProcessError) as exc:
            warnings.append("git init failed: %s" % exc)

    marker = {"schema_version": SCHEMA_VERSION, "language": language, "areas": clean}
    write_atomic(root / MARKER, json.dumps(marker, ensure_ascii=False, indent=2) + "\n")
    created.append(MARKER)
    logfile.append(root, "init", "vault created")
    return {"status": "created", "root": str(root), "created": created, "kept": kept,
            "warnings": warnings}
```

`plugins/second-brain/templates/CLAUDE.md`:

````markdown
# Second Brain

This directory is a **local-first Second Brain**: plain markdown notes, operated by Claude Code
through the `second-brain` plugin. Run `claude` from this directory.

Notes are written in **{{language}}**.

## Map

- `wiki/` — curated knowledge. The human reads it. `Projects/` (active, with a deadline),
  `Areas/` (ongoing responsibilities), `Resources/` (concepts, entities, references),
  `Archive/` (inactive).
- `_inbox/` — raw captures. The human writes, the agent processes. Processed items go to
  `_inbox/_done/`.
- `_raw/` — immutable source files (PDFs, articles, transcripts). The human places them here.
  **Read-only for the agent.**
- `_index.md` — generated catalogue, one line per note. Never edit by hand; run `sb index --write`.
- `_log.md` — append-only event log. Use `sb log`.
- `.second-brain.json` — vault marker and configuration (`schema_version`, language, areas).

Everything outside `wiki/` is system. The `_` prefix marks paths the agent operates.

## Rules

1. Knowledge lives in `wiki/`. Never write outside it unless asked, except `_inbox/`,
   `_index.md` and `_log.md` through the skills.
2. **Never invent.** Synthesise only what is written in this vault or in the source being
   ingested. Never invent facts, links or connections. Cite the source note as `[[Note]]`.
3. `_raw/` is read-only. Never delete anything without asking first.
4. The human owns the interpretation. The agent does the clerical work: formatting, links,
   index. Notes the agent writes carry `origin: agent`; the human sets `reviewed:` after checking.
5. Search `wiki/` first (`_index.md`, then `rg "^summary:"`). Open `_raw/` only to verify a source.
6. Link only to notes that exist. Note names are unique, so `[[Name]]` survives folder moves.
7. `CLAUDE.md`, `.claude/` and `.second-brain.json` are edited by the human, not the agent.

## What deserves a note

Persist something only if it is **useful**, **new or surprising**, **carries the author's
interpretation**, and **will be reused**. Skip what is ephemeral, already mastered, or trivially
found on the web. Raw captures stay in `_inbox/` unorganised.

## Note format

```yaml
---
title: Note title
summary: One line. Required. This is what triage reads.
type: nota            # nota | fonte | projeto | conceito
status: seed          # seed | draft | evergreen
origin: agent         # agent | human | mixed
created: 2026-01-31   # ISO date
source: _raw/x.pdf    # path under _raw/ or _inbox/, or [[Note]]
reviewed:             # optional ISO date, set by the human
tags: [a, b]          # optional, few, lowercase
---
```

Frontmatter is a restricted subset: `key: value` scalars and inline `[a, b]` lists only.
Notes are atomic. Prefer links and frontmatter to tag taxonomies.

## Workflow

- `/second-brain:capture` — drop raw text into `_inbox/`.
- `/second-brain:ingest` — turn an inbox item into an atomic note, update index and log.
- `/second-brain:find` — answer from the vault, citing notes.
- `/second-brain:link` — propose links between notes.
- `/second-brain:update` — revise an existing note.
- `/second-brain:lint` — check the vault; proposes fixes, applies none without approval.
- `sb lint`, `sb index --check`, `sb links <note> --suggest` run directly in a terminal.

Changes are committed locally by the plugin when this directory has a `.git` (setting
`auto_commit`). Review with `git diff`; revert with `git`.
````

- [ ] **Step 4: Run to verify pass**

Run: `bash tests/sb_cli_test.sh`
Expected: PASS. The `_append_gitignore` created/kept bookkeeping line is the only intricate one: if `test_creates_layout…` expects `.gitignore` among created files and the assertion on `result` fails, simplify to `created.append(".gitignore")` when the file did not exist before and `kept.append(".gitignore")` otherwise — compute `existed = path.exists()` once at the top of the function.

- [ ] **Step 5: Checkpoint** — ask the user whether to commit. Suggested message: `feat(second-brain): sb init and vault CLAUDE.md template`.

---

### Task 7: PreToolUse guard

**Files:**
- Create: `plugins/second-brain/lib/sb/guard.py`, `plugins/second-brain/hooks/guard.py`
- Test: `tests/python/test_sb_guard.py`

**Interfaces:**
- Consumes: `vault.find_vault`.
- Produces: `guard.decide(event: dict, cwd: str) -> dict|None` returning a `hookSpecificOutput` object with `permissionDecision` `"deny"` or `"ask"`, or `None` (allow); `hooks/guard.py` script printing that JSON and always exiting `0`.

- [ ] **Step 1: Write the failing tests**

`tests/python/test_sb_guard.py`:

```python
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from sb_helpers import PLUGIN, make_vault, note
from sb.guard import decide


class GuardTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = make_vault(self.tmp.name, {"Resources/A.md": note("A")})
        self.vault = self.root.resolve()

    def verdict(self, tool, cwd=None, **tool_input):
        event = {"tool_name": tool, "tool_input": tool_input}
        out = decide(event, str(cwd or self.vault))
        return out["hookSpecificOutput"]["permissionDecision"] if out else "allow"

    def bash(self, command, cwd=None):
        return self.verdict("Bash", cwd=cwd, command=command)

    def test_write_tools_deny_protected_paths(self):
        for tool, key in (("Write", "file_path"), ("Edit", "file_path"),
                          ("MultiEdit", "file_path"), ("NotebookEdit", "notebook_path")):
            for path in ("_raw/a.md", "CLAUDE.md", ".claude/settings.json", ".second-brain.json"):
                self.assertEqual(self.verdict(tool, **{key: path}), "deny", (tool, path))

    def test_write_tools_deny_absolute_and_traversal_paths(self):
        self.assertEqual(self.verdict("Write", file_path=str(self.vault / "_raw" / "a.md")), "deny")
        self.assertEqual(self.verdict("Write", file_path="wiki/../_raw/a.md"), "deny")

    def test_symlink_into_raw_is_denied(self):
        os.symlink(self.vault / "_raw", self.vault / "wiki" / "link")
        self.assertEqual(self.verdict("Write", file_path="wiki/link/a.md"), "deny")

    def test_write_tools_allow_normal_paths(self):
        for path in ("wiki/Resources/a.md", "_index.md", "_log.md", "_inbox/x.md",
                     "wiki/sub/CLAUDE.md", "/tmp/elsewhere.txt"):
            self.assertEqual(self.verdict("Write", file_path=path), "allow", path)

    def test_works_from_a_subfolder(self):
        sub = self.vault / "wiki" / "Resources"
        self.assertEqual(self.verdict("Write", cwd=sub, file_path="../../_raw/a.md"), "deny")
        self.assertEqual(self.bash("rm ../../_raw/a.pdf", cwd=sub), "deny")

    def test_bash_denies_mutations_of_protected_paths(self):
        for command in ("echo x > _raw/a.md", "echo x >> CLAUDE.md", "rm _raw/a.pdf",
                        "rm -rf _raw", "mv _raw/a.pdf wiki/", "sed -i s/a/b/ CLAUDE.md",
                        "cp wiki/a.md _raw/", "rm -rf .", "git rm _raw/a", "touch .claude/x",
                        "echo hi | tee _raw/x", "cd . && rm _raw/x", "sudo rm _raw/x"):
            self.assertEqual(self.bash(command), "deny", command)

    def test_bash_allows_reads_and_harmless_commands(self):
        for command in ("cat _raw/a.md", "rg foo _raw", "ls", "cp _raw/a.pdf wiki/x.pdf",
                        "echo hi 2>&1", "echo x > /dev/null", "sb lint", "git status",
                        "mv _inbox/a.md _inbox/_done/a.md"):
            self.assertEqual(self.bash(command), "allow", command)

    def test_bash_asks_before_deleting_curated_notes(self):
        for command in ("rm wiki/Resources/A.md", "rm -rf wiki", "git rm wiki/Resources/A.md",
                        "rm *.md"):
            self.assertEqual(self.bash(command), "ask", command)

    def test_deny_message_tells_the_human_to_edit_directly(self):
        out = decide({"tool_name": "Write", "tool_input": {"file_path": "_raw/a.md"}}, str(self.vault))
        reason = out["hookSpecificOutput"]["permissionDecisionReason"]
        self.assertIn("_raw/a.md", reason)
        self.assertIn("human", reason)

    def test_noop_outside_a_vault(self):
        outside = tempfile.mkdtemp()
        self.addCleanup(os.rmdir, outside)
        self.assertEqual(self.verdict("Write", cwd=outside, file_path="_raw/a.md"), "allow")
        self.assertEqual(self.bash("rm -rf _raw", cwd=outside), "allow")

    def test_event_cwd_overrides_process_cwd(self):
        event = {"cwd": str(self.vault), "tool_name": "Write", "tool_input": {"file_path": "_raw/a.md"}}
        self.assertIsNotNone(decide(event, tempfile.gettempdir()))


class GuardScriptTests(unittest.TestCase):
    script = str(PLUGIN / "hooks" / "guard.py")

    def run_script(self, stdin, cwd):
        return subprocess.run([sys.executable, self.script], input=stdin, cwd=cwd,
                              capture_output=True, text=True)

    def test_script_prints_a_deny_decision(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = make_vault(tmp)
            event = json.dumps({"cwd": str(root), "tool_name": "Write",
                                "tool_input": {"file_path": "_raw/a.md"}})
            done = self.run_script(event, root)
        self.assertEqual(done.returncode, 0)
        self.assertEqual(json.loads(done.stdout)["hookSpecificOutput"]["permissionDecision"], "deny")

    def test_script_fails_open_on_garbage_input(self):
        done = self.run_script("not json", tempfile.gettempdir())
        self.assertEqual((done.returncode, done.stdout), (0, ""))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/sb_cli_test.sh`
Expected: FAIL — `ModuleNotFoundError: No module named 'sb.guard'`.

- [ ] **Step 3: Implement the decision logic**

`plugins/second-brain/lib/sb/guard.py`:

```python
"""PreToolUse decisions for a second-brain vault (spec section 6).

Deny writes to _raw/**, .claude/**, top-level CLAUDE.md and .second-brain.json.
Ask before deleting anything under wiki/. Bash matching is best effort: git is the real net.
"""
import os
import re
import shlex
from pathlib import Path

from .vault import find_vault

WRITE_TOOLS = {"Write": "file_path", "Edit": "file_path", "MultiEdit": "file_path",
               "NotebookEdit": "notebook_path"}
PROTECTED_DIRS = {"_raw", ".claude"}
PROTECTED_FILES = {"CLAUDE.md", ".second-brain.json"}
SEGMENT_SPLIT = re.compile(r"&&|\|\||;|\||\n")
REDIRECT = re.compile(r"\d*>>?\s*([^\s;&|<>]+)")
ENV_ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
WRAPPERS = {"sudo", "command", "time", "nohup", "exec", "builtin"}
DELETE_CMDS = {"rm", "rmdir", "unlink", "shred"}
ALL_OPERANDS_WRITE = {"mv", "touch", "tee", "truncate", "ln", "chmod", "chown", "mkdir"}
LAST_OPERAND_WRITES = {"cp", "install", "rsync"}

DENY_REASON = ("%s is protected in a second-brain vault: _raw/ is immutable, and CLAUDE.md, "
               ".claude/ and .second-brain.json are edited by the human. Ask the human to "
               "change it directly.")
ASK_REASON = ("%s is curated knowledge. Confirm the deletion with the user first; git can "
              "restore it.")


def _decision(kind, reason):
    return {"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                   "permissionDecision": kind,
                                   "permissionDecisionReason": reason}}


def _rel(vault, cwd, raw):
    raw = raw.strip().strip("'\"")
    path = os.path.realpath(os.path.join(cwd, os.path.expanduser(raw)))
    try:
        return Path(path).relative_to(vault).as_posix()
    except ValueError:
        return None


def _is_protected(rel):
    return rel is not None and (rel.split("/")[0] in PROTECTED_DIRS or rel in PROTECTED_FILES)


def _strip_wrappers(tokens):
    i = 0
    while i < len(tokens) and (tokens[i] in WRAPPERS or ENV_ASSIGNMENT.match(tokens[i])):
        i += 1
    return tokens[i:]


def _classify(vault, cwd, operands, deleting):
    ask = None
    for raw in operands:
        rel = _rel(vault, cwd, raw)
        if rel is None:
            continue
        if _is_protected(rel) or (deleting and rel == "."):
            return ("deny", rel)
        if deleting and (rel == "wiki" or rel.startswith("wiki/")):
            ask = ("ask", rel)
        elif deleting and "/" not in rel and any(c in rel for c in "*?["):
            ask = ("ask", rel)
    return ask


def _segment_verdict(vault, cwd, tokens):
    program = os.path.basename(tokens[0])
    args = tokens[1:]
    operands = [a for a in args if not a.startswith("-")]
    if program == "git" and operands and operands[0] == "rm":
        program, operands = "rm", operands[1:]
    if program in DELETE_CMDS:
        return _classify(vault, cwd, operands, deleting=True)
    if program == "sed" and any(a == "--in-place" or a.startswith("-i") for a in args):
        return _classify(vault, cwd, operands, deleting=False)
    if program in ALL_OPERANDS_WRITE:
        return _classify(vault, cwd, operands, deleting=False)
    if program in LAST_OPERAND_WRITES:
        return _classify(vault, cwd, operands[-1:], deleting=False)
    return None


def _decide_bash(vault, cwd, command):
    for match in REDIRECT.finditer(command):
        rel = _rel(vault, cwd, match.group(1))
        if _is_protected(rel):
            return _decision("deny", DENY_REASON % rel)
    ask = None
    for segment in SEGMENT_SPLIT.split(command):
        try:
            tokens = shlex.split(segment)
        except ValueError:
            tokens = segment.split()
        tokens = _strip_wrappers(tokens)
        if not tokens:
            continue
        verdict = _segment_verdict(vault, cwd, tokens)
        if verdict and verdict[0] == "deny":
            return _decision("deny", DENY_REASON % verdict[1])
        ask = verdict or ask
    return _decision("ask", ASK_REASON % ask[1]) if ask else None


def decide(event, cwd):
    cwd = event.get("cwd") or cwd
    vault = find_vault(cwd)
    if vault is None:
        return None
    tool = event.get("tool_name", "")
    tool_input = event.get("tool_input") or {}
    if tool in WRITE_TOOLS:
        raw = tool_input.get(WRITE_TOOLS[tool])
        rel = _rel(vault, cwd, raw) if raw else None
        return _decision("deny", DENY_REASON % rel) if _is_protected(rel) else None
    if tool == "Bash":
        return _decide_bash(vault, cwd, tool_input.get("command", ""))
    return None
```

`plugins/second-brain/hooks/guard.py`:

```python
#!/usr/bin/env python3
"""PreToolUse hook entry point. Any internal failure allows the call (exit 0, no output)."""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "lib"))


def main():
    try:
        event = json.load(sys.stdin)
        from sb.guard import decide
        decision = decide(event, os.getcwd())
    except Exception:
        return 0
    if decision:
        json.dump(decision, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run to verify pass**

Run: `bash tests/sb_cli_test.sh`
Expected: PASS. If a Bash case disagrees, fix the matching code, not the expectation, unless the expectation contradicts spec §6.

- [ ] **Step 5: Checkpoint** — ask the user whether to commit. Suggested message: `feat(second-brain): PreToolUse guard for protected vault paths`.

---

### Task 8: PostToolUse check, auto-commit and `hooks.json`

**Files:**
- Create: `plugins/second-brain/lib/sb/postcheck.py`, `plugins/second-brain/lib/sb/autocommit.py`
- Create: `plugins/second-brain/hooks/validate_note.py`, `plugins/second-brain/hooks/autocommit.py`, `plugins/second-brain/hooks/hooks.json`
- Test: `tests/python/test_sb_hooks.py`

**Interfaces:**
- Consumes: `vault.find_vault`, `vault.load_note`, `lint.check_note`.
- Produces: `postcheck.check(event, cwd) -> dict|None` (`hookSpecificOutput.additionalContext`), `autocommit.run(cwd, env=None, today=None) -> str` (a status line starting `committed:` or `skipped:`), `autocommit.enabled(env) -> bool`.

- [ ] **Step 1: Write the failing tests**

`tests/python/test_sb_hooks.py`:

```python
import inspect
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from sb_helpers import PLUGIN, make_vault, note
from sb import autocommit
from sb.postcheck import check


class PostCheckTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = make_vault(self.tmp.name, {"Resources/A.md": note("A")})

    def event(self, path):
        return {"cwd": str(self.root), "tool_name": "Write", "tool_input": {"file_path": path}}

    def test_reports_frontmatter_problems_of_a_touched_wiki_note(self):
        bad = self.root / "wiki" / "Resources" / "Bad.md"
        bad.write_text(note("Bad", summary=None), encoding="utf-8")
        out = check(self.event(str(bad)), str(self.root))
        context = out["hookSpecificOutput"]["additionalContext"]
        self.assertEqual(out["hookSpecificOutput"]["hookEventName"], "PostToolUse")
        self.assertIn("SB102", context)
        self.assertIn("wiki/Resources/Bad.md", context)

    def test_silent_for_valid_notes_other_files_and_non_vaults(self):
        self.assertIsNone(check(self.event("wiki/Resources/A.md"), str(self.root)))
        self.assertIsNone(check(self.event("_inbox/x.md"), str(self.root)))
        self.assertIsNone(check(self.event("wiki/Resources/notes.txt"), str(self.root)))
        outside = tempfile.gettempdir()
        self.assertIsNone(check({"tool_input": {"file_path": "wiki/a.md"}}, outside))


@unittest.skipUnless(shutil.which("git"), "git not installed")
class AutoCommitTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = make_vault(self.tmp.name, {"Resources/A.md": note("A")})
        self.git("init", "-q")
        self.git("config", "user.email", "t@example.com")
        self.git("config", "user.name", "Test")
        self.git("add", "-A")
        self.git("commit", "-q", "-m", "init")

    def git(self, *args):
        return subprocess.run(["git", "-C", str(self.root), *args], capture_output=True, text=True)

    def commits(self):
        return int(self.git("rev-list", "--count", "HEAD").stdout.strip())

    def dirty(self):
        (self.root / "wiki" / "Resources" / "New.md").write_text(note("New"), encoding="utf-8")

    def test_commits_changes_by_default_when_env_is_unset(self):
        self.dirty()
        status = autocommit.run(str(self.root), env={}, today="2026-10-01")
        self.assertEqual(status, "committed: sb: update 2026-10-01 (1 changes)")
        self.assertEqual(self.commits(), 2)
        self.assertEqual(self.git("status", "--porcelain").stdout, "")

    def test_disabled_by_userconfig(self):
        for value in ("false", "FALSE", "0", "no", "off"):
            self.dirty()
            status = autocommit.run(str(self.root), env={"CLAUDE_PLUGIN_OPTION_AUTO_COMMIT": value})
            self.assertEqual(status, "skipped: auto_commit is off", value)
        self.assertEqual(self.commits(), 1)

    def test_explicitly_enabled(self):
        self.dirty()
        status = autocommit.run(str(self.root), env={"CLAUDE_PLUGIN_OPTION_AUTO_COMMIT": "true"})
        self.assertTrue(status.startswith("committed:"))

    def test_no_changes(self):
        self.assertEqual(autocommit.run(str(self.root), env={}), "skipped: no changes")
        self.assertEqual(self.commits(), 1)

    def test_no_git_directory(self):
        shutil.rmtree(self.root / ".git")
        self.assertEqual(autocommit.run(str(self.root), env={}), "skipped: no .git")

    def test_not_a_vault(self):
        self.assertEqual(autocommit.run(tempfile.gettempdir(), env={}), "skipped: not a vault")

    def test_merge_in_progress(self):
        self.dirty()
        (self.root / ".git" / "MERGE_HEAD").write_text("0" * 40 + "\n", encoding="utf-8")
        self.assertEqual(autocommit.run(str(self.root), env={}),
                         "skipped: merge or rebase in progress")
        self.assertEqual(self.commits(), 1)

    def test_commit_failure_is_reported_not_raised(self):
        self.dirty()
        self.git("config", "--unset", "user.email")
        self.git("config", "user.useConfigOnly", "true")
        old = os.environ.copy()
        os.environ.update({"GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_SYSTEM": os.devnull,
                           "HOME": self.tmp.name})
        for key in ("GIT_AUTHOR_EMAIL", "GIT_COMMITTER_EMAIL", "EMAIL"):
            os.environ.pop(key, None)
        self.addCleanup(lambda: (os.environ.clear(), os.environ.update(old)))
        self.assertTrue(autocommit.run(str(self.root), env={}).startswith("skipped: git commit failed"))

    def test_source_never_pushes(self):
        self.assertNotIn("push", inspect.getsource(autocommit))


class HookScriptTests(unittest.TestCase):
    def run_script(self, name, stdin, cwd, env=None):
        return subprocess.run([sys.executable, str(PLUGIN / "hooks" / name)], input=stdin,
                              cwd=cwd, capture_output=True, text=True, env=env)

    def test_validate_note_script_outputs_context(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = make_vault(tmp, {"R/Bad.md": note("Bad", summary=None)})
            event = json.dumps({"cwd": str(root), "tool_name": "Edit",
                                "tool_input": {"file_path": str(root / "wiki/R/Bad.md")}})
            done = self.run_script("validate_note.py", event, root)
        self.assertEqual(done.returncode, 0)
        self.assertIn("SB102", json.loads(done.stdout)["hookSpecificOutput"]["additionalContext"])

    def test_validate_note_script_fails_open(self):
        done = self.run_script("validate_note.py", "garbage", tempfile.gettempdir())
        self.assertEqual((done.returncode, done.stdout), (0, ""))

    def test_autocommit_script_always_exits_zero(self):
        done = self.run_script("autocommit.py", "{}", tempfile.gettempdir())
        self.assertEqual(done.returncode, 0)

    def test_hooks_json_wires_the_three_events(self):
        spec = json.loads((PLUGIN / "hooks" / "hooks.json").read_text(encoding="utf-8"))["hooks"]
        self.assertEqual(spec["PreToolUse"][0]["matcher"], "Write|Edit|MultiEdit|NotebookEdit|Bash")
        self.assertEqual(spec["PostToolUse"][0]["matcher"], "Write|Edit|MultiEdit")
        self.assertNotIn("matcher", spec["Stop"][0])
        for event in spec.values():
            for hook in event[0]["hooks"]:
                self.assertIn("${CLAUDE_PLUGIN_ROOT}/hooks/", hook["command"])
                script = hook["command"].split("/hooks/")[1].rstrip('"')
                self.assertTrue((PLUGIN / "hooks" / script).is_file(), script)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/sb_cli_test.sh`
Expected: FAIL — `ImportError: cannot import name 'autocommit' from 'sb'`.

- [ ] **Step 3: Implement the library modules**

`plugins/second-brain/lib/sb/postcheck.py`:

```python
"""PostToolUse feedback: frontmatter problems in a note the agent just wrote."""
import os
from pathlib import Path

from .lint import check_note
from .vault import find_vault, load_note


def check(event, cwd):
    cwd = event.get("cwd") or cwd
    vault = find_vault(cwd)
    if vault is None:
        return None
    raw = (event.get("tool_input") or {}).get("file_path")
    if not raw or not raw.endswith(".md"):
        return None
    path = Path(os.path.realpath(os.path.join(cwd, raw)))
    try:
        path.relative_to(vault / "wiki")
    except ValueError:
        return None
    if not path.is_file():
        return None
    findings = check_note(load_note(vault, path))
    if not findings:
        return None
    lines = ["second-brain: %s has frontmatter problems:" % findings[0].path]
    lines += ["- %s (line %d): %s" % (f.code, f.line, f.message) for f in findings]
    lines.append("Fix them before continuing.")
    return {"hookSpecificOutput": {"hookEventName": "PostToolUse",
                                   "additionalContext": "\n".join(lines)}}
```

`plugins/second-brain/lib/sb/autocommit.py`:

```python
"""Stop-hook git logic: commit vault changes locally (spec D7). Local commits only."""
import os
import subprocess
from datetime import date
from pathlib import Path

from .vault import find_vault

OFF_VALUES = {"false", "0", "no", "off"}
IN_PROGRESS = ("MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge", "rebase-apply")


def enabled(env):
    return env.get("CLAUDE_PLUGIN_OPTION_AUTO_COMMIT", "true").strip().lower() not in OFF_VALUES


def _git(vault, *args):
    return subprocess.run(["git", "-C", str(vault), *args], capture_output=True, text=True,
                          timeout=30)


def run(cwd, env=None, today=None):
    """Return 'committed: <message>' or 'skipped: <reason>'. Never raises."""
    env = os.environ if env is None else env
    vault = find_vault(cwd)
    if vault is None:
        return "skipped: not a vault"
    if not enabled(env):
        return "skipped: auto_commit is off"
    if not (vault / ".git").exists():
        return "skipped: no .git"
    try:
        gitdir = _git(vault, "rev-parse", "--absolute-git-dir")
        if gitdir.returncode != 0:
            return "skipped: not a git work tree"
        if any((Path(gitdir.stdout.strip()) / name).exists() for name in IN_PROGRESS):
            return "skipped: merge or rebase in progress"
        status = _git(vault, "status", "--porcelain")
        if status.returncode != 0:
            return "skipped: git status failed: %s" % status.stderr.strip()
        changed = [line for line in status.stdout.splitlines() if line.strip()]
        if not changed:
            return "skipped: no changes"
        added = _git(vault, "add", "-A")
        if added.returncode != 0:
            return "skipped: git add failed: %s" % added.stderr.strip()
        message = "sb: update %s (%d changes)" % (today or date.today().isoformat(), len(changed))
        committed = _git(vault, "commit", "-q", "-m", message)
        if committed.returncode != 0:
            return "skipped: git commit failed: %s" % (committed.stderr.strip()
                                                       or committed.stdout.strip())
        return "committed: %s" % message
    except (OSError, subprocess.SubprocessError) as exc:
        return "skipped: %s" % exc
```

- [ ] **Step 4: Implement the hook scripts and `hooks.json`**

`plugins/second-brain/hooks/validate_note.py`:

```python
#!/usr/bin/env python3
"""PostToolUse hook entry point. Any internal failure is silent (exit 0)."""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "lib"))


def main():
    try:
        event = json.load(sys.stdin)
        from sb.postcheck import check
        output = check(event, os.getcwd())
    except Exception:
        return 0
    if output:
        json.dump(output, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

`plugins/second-brain/hooks/autocommit.py`:

```python
#!/usr/bin/env python3
"""Stop hook entry point: local auto-commit. Always exits 0; status goes to stderr."""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "lib"))


def main():
    try:
        try:
            cwd = json.load(sys.stdin).get("cwd") or os.getcwd()
        except Exception:
            cwd = os.getcwd()
        from sb.autocommit import run
        status = run(cwd)
        if status.startswith("committed"):
            print("second-brain: " + status, file=sys.stderr)
    except Exception as exc:
        print("second-brain: auto-commit error: %s" % exc, file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

`plugins/second-brain/hooks/hooks.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit|NotebookEdit|Bash",
        "hooks": [
          {
            "type": "command",
            "command": "python3 \"${CLAUDE_PLUGIN_ROOT}/hooks/guard.py\"",
            "timeout": 5
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "python3 \"${CLAUDE_PLUGIN_ROOT}/hooks/validate_note.py\"",
            "timeout": 10
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 \"${CLAUDE_PLUGIN_ROOT}/hooks/autocommit.py\"",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

The shell-form commands read `CLAUDE_PLUGIN_OPTION_AUTO_COMMIT` from the environment (documented: exported to hook processes for every `userConfig` option), so no `${user_config.*}` reference is used.

- [ ] **Step 5: Run to verify pass, then validate the plugin**

Run: `bash tests/sb_cli_test.sh && bash tests/sb_structure_test.sh`
Expected: PASS, and `claude plugin validate … --strict` still `ok`. If validate warns about the `${CLAUDE_PLUGIN_ROOT}` quoting, mirror `solutions-architect/hooks/hooks.json` exactly (it uses the same shape).

- [ ] **Step 6: Checkpoint** — ask the user whether to commit. Suggested message: `feat(second-brain): PostToolUse frontmatter check, local auto-commit hook and hooks.json`.

---

### Task 9: The seven skills and their structure checks

**Files:**
- Create: `plugins/second-brain/skills/{init,capture,ingest,find,link,update,lint}/SKILL.md`
- Modify: `tests/sb_structure_test.sh`

**Interfaces:**
- Consumes: `sb` subcommands (Tasks 5–6); vault conventions (spec §4, template in Task 6).
- Produces: skills invocable as `/second-brain:<name>`.

- [ ] **Step 1: Extend the structure test (failing first)**

Insert before the final `exit $fail` in `tests/sb_structure_test.sh`:

```bash
skills="init capture ingest find link update lint"
for s in $skills; do
  f="$p/skills/$s/SKILL.md"
  [ -f "$f" ]; check "skills/$s/SKILL.md exists" $?
  grep -q "^name: $s$" "$f" 2>/dev/null; check "skills/$s frontmatter name" $?
  desc="$(awk '/^description: >/{f=1;next} f&&/^([a-z-]+:|---)/{exit} f{sub(/^  /,"");printf "%s ",$0}' "$f" 2>/dev/null)"
  [ "${#desc}" -ge 150 ] && [ "${#desc}" -le 400 ]; check "skills/$s description is 150-400 chars (${#desc})" $?
  [ "$(wc -l < "$f" 2>/dev/null || echo 999)" -le 250 ]; check "skills/$s SKILL.md <= 250 lines" $?
done
[ "$(ls "$p/skills" 2>/dev/null | wc -l)" -eq 7 ]; check "exactly 7 skills" $?
grep -q '^disable-model-invocation: true$' "$p/skills/init/SKILL.md" 2>/dev/null
check "init is user-invoked only" $?
[ "$(wc -l < "$p/templates/CLAUDE.md")" -lt 200 ]; check "vault CLAUDE.md template < 200 lines (AC1)" $?
[ -x "$p/bin/sb" ]; check "bin/sb is executable" $?

# Every ${CLAUDE_PLUGIN_ROOT}/... path referenced anywhere must exist.
while IFS= read -r ref; do
  [ -e "$p/$ref" ]; check "referenced path exists: $ref" $?
done < <(grep -rhoE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9_./-]+' "$p" --include='*.md' --include='*.json' 2>/dev/null \
         | sed 's#\${CLAUDE_PLUGIN_ROOT}/##' | sort -u)
```

Run: `bash tests/sb_structure_test.sh`
Expected: FAIL on the missing skills.

- [ ] **Step 2: Write `init` and `capture`**

`plugins/second-brain/skills/init/SKILL.md`:

````markdown
---
name: init
description: >
  Creates a local-first Second Brain vault in the current directory: wiki/, _inbox/, _raw/, a
  generated _index.md, an append-only _log.md and the vault CLAUDE.md. Idempotent; never
  overwrites an existing CLAUDE.md. Run it once per vault.
disable-model-invocation: true
argument-hint: "[language]"
allowed-tools: Bash(sb init *) Bash(sb lint *) Bash(git init *)
---

# Initialise a Second Brain vault

The vault is the directory where `claude` runs. Do **not** create files by hand: `sb init` does
the mechanical work and writes the marker `.second-brain.json` last.

## Procedure

1. If `.second-brain.json` already exists here, run `sb lint`, report the result, and stop. Do not
   change anything.
2. Ask the user, in **one** message, at most these three questions (skip any already answered by
   `$ARGUMENTS`):
   - note language (a BCP-47 tag such as `pt-BR` or `en`; default `en`);
   - run `git init`? (skip if `.git` exists; it is needed for auto-commit and is the safety net);
   - initial areas under `wiki/Areas/` (comma-separated, may be empty).
3. Run `sb init --language <lang> --areas "<a,b>" [--git]`.
4. Run `sb lint` and confirm it reports nothing.
5. Tell the user, briefly:
   - put original sources in `_raw/` (the agent cannot write there);
   - `CLAUDE.md` holds the rules and is edited by them, not by the agent;
   - next steps: `/second-brain:capture`, then `/second-brain:ingest`;
   - changes are committed locally after each response when the vault has a `.git`
     (plugin setting `auto_commit`, on by default; it never pushes).

Never ask more than three questions. Never store personal data in the plugin; everything lives in
the vault.
````

`plugins/second-brain/skills/capture/SKILL.md`:

````markdown
---
name: capture
description: >
  Saves raw text, a link or a thought into the vault's _inbox/ exactly as given, with no
  organising or linking. Use when the user says "capture", "save this for later" or pastes
  something to keep. Processing happens later with ingest.
argument-hint: "[text to capture]"
allowed-tools: Write Bash(date *) Bash(sb log *)
---

# Capture to the inbox

Capturing is deliberately dumb: no summarising, no tagging, no links, no decisions about what
matters. That is what `/second-brain:ingest` is for.

## Procedure

1. The text to capture is `$ARGUMENTS`; if empty, use the user's last message or ask for it.
2. Run `date +%Y-%m-%d-%H%M` for the timestamp and `date +%Y-%m-%dT%H:%M` for the header.
3. Pick a short lowercase slug (3–5 words, ASCII, hyphens) from the content.
4. Write `_inbox/<timestamp>-<slug>.md`:

   ```
   ---
   captured: <ISO datetime>
   from: user
   ---
   <the text, verbatim>
   ```

5. Run `sb log capture "<slug>"`.
6. Reply with the file path only. Do not process it unless the user asks.

Never write outside `_inbox/`. If the target file exists, add `-2`, `-3`... to the slug.
````

- [ ] **Step 3: Write `ingest` and `find`**

`plugins/second-brain/skills/ingest/SKILL.md`:

````markdown
---
name: ingest
description: >
  Turns an _inbox/ capture or a named _raw/ source into one atomic wiki/ note with complete
  frontmatter, links to existing notes only, then updates _index.md and _log.md. Updates an
  existing note instead of duplicating. Use for "ingest", "process my inbox", "add this to my notes".
argument-hint: "[_inbox/file.md | _raw/file]"
allowed-tools: Read Write Edit Grep Glob Bash(sb *) Bash(rg *) Bash(mv *) Bash(date *)
---

# Ingest an item

Read `CLAUDE.md` first: it holds the vault rules and the note format. Use **only** what is
written in the item and in existing notes. Never invent facts or connections.

## Procedure

1. **Pick the item.** `$ARGUMENTS`, else list `_inbox/*.md` (not `_inbox/_done/`) and ask which.
   If there is none, say so and stop.
2. **Read it.** Apply the persistence criteria from `CLAUDE.md` (useful, new or surprising,
   carries the author's interpretation, will be reused). If it fails, say why and ask whether to
   drop it or ingest anyway. Do not delete.
3. **Move an inbox item first.** `mv _inbox/<file> _inbox/_done/<file>` (skip if it is already in
   `_done/`). The item's path from now on is `_inbox/_done/<file>`; a `_raw/` source keeps its path.
   Never write to `_raw/`.
4. **Look for an existing note** (idempotency):
   - `rg -l -F "source: <item path>" wiki/` — a hit means this item was already ingested;
   - `rg -i -l "<key terms>" wiki/` and `_index.md` for the same topic.
   If a note exists, **update it** (go to step 6); never create a second note for the same item.
5. **Create the note** at `wiki/<Projects|Areas|Resources>/<Name>.md` (never `Archive`):
   - `Name` is unique: check `rg --files wiki | rg "/<Name>\.md$"` first; atomic, one idea;
   - frontmatter complete: `title`, one-line `summary` (in the vault language), `type`,
     `status: seed`, `origin: agent`, `created: <today>`, `source: <item path>`;
   - body: the idea in the author's terms. Keep their interpretation; add nothing they did not say.
6. **Update** (existing note): merge only what is new, keep `created` and the original `source`,
   mention the extra item under a `Sources` line, set `origin: mixed` if it was `human`, and clear
   `reviewed`.
7. **Link.** Run `sb links "<Name>" --suggest`. Add `[[wikilinks]]` only to notes that exist and
   that the text genuinely relates to; suggestions are candidates, not orders.
8. **Close.** `sb validate wiki/.../<Name>.md`, `sb index --write`, `sb log ingest "<Title>"`.
9. **Report** the note path, whether it was created or updated, the links added, and say the
   user can review with `git diff`.

Running this twice on the same item must end with the same single note.
````

`plugins/second-brain/skills/find/SKILL.md`:

````markdown
---
name: find
description: >
  Answers a question from the user's Second Brain vault: reads _index.md, triages wiki/ notes by
  summary with ripgrep, opens at most three, and cites them as [[Note]]. States plainly when the
  vault does not cover the topic. Use for "what do I know about X" or "find my notes on Y".
argument-hint: "[topic or question]"
allowed-tools: Read Grep Glob Bash(rg *) Bash(sb *)
---

# Find in the vault

Answer only from the vault. If the vault does not say it, say so; never fill the gap from general
knowledge and attribute it to a note.

## Procedure

1. Read `_index.md` (one line per note: `[[Name]]: summary`).
2. Pick 2–5 search terms from `$ARGUMENTS` (include synonyms and the vault language).
   Run `rg -i -n "^(title|summary):.*(<term>)" wiki/` and `rg -i -l "<term>" wiki/`.
3. Rank by where the term hits: title > summary > body. Open **at most three** notes.
4. Answer in the user's language. Cite each claim with the note it came from, as `[[Note]]`.
   Distinguish what a note says from your own inference, and label the inference.
5. If nothing matches, reply: the vault has no notes on this topic, and suggest
   `/second-brain:capture` if they want to add something. Do not guess.
6. Open `_raw/` only to verify a source a note cites, never to answer from it directly.
7. If you notice the answer needs a link between notes that does not exist, mention it; do not
   edit anything (use `/second-brain:link`).
````

- [ ] **Step 4: Write `link`, `update` and `lint`**

`plugins/second-brain/skills/link/SKILL.md`:

````markdown
---
name: link
description: >
  Relates notes in the Second Brain vault: lists a note's links and backlinks, proposes wikilinks
  for exact title mentions, and surfaces orphan notes. Applies only the links the user approves,
  and only to notes that exist. Use for "link my notes", "what relates to X", "find orphans".
argument-hint: "[note name]"
allowed-tools: Read Edit Grep Glob Bash(sb *) Bash(rg *)
---

# Link notes

Links are claims about how ideas relate. Propose; the human decides.

## Procedure

1. With a note: run `sb links "<note>" --suggest`. Without one: run `sb lint --json` and take the
   `SB103` findings (orphans) as the work list.
2. For each candidate, read both notes' summaries (and bodies if unclear) and judge whether the
   relation is real. Drop mere word coincidences.
3. Present a short table: source note, candidate target, the sentence/line, why it relates.
4. Apply only the links the user approves, with `Edit`. Link text must use the target's exact
   name: `[[Name]]`. Never link to a note that does not exist and never create stub notes.
5. For an orphan, say which existing notes could link to it; do not invent a parent.
6. Run `sb validate` on each edited note, then `sb log link "<note>"`.
````

`plugins/second-brain/skills/update/SKILL.md`:

````markdown
---
name: update
description: >
  Applies a change the user asked for to an existing Second Brain note while preserving its
  provenance: keeps created and source, adjusts origin, clears reviewed, refreshes the index and
  logs it. Use for "update my note on X", "correct this", "add this to the note about Y".
argument-hint: "[note name] [change]"
allowed-tools: Read Edit Grep Glob Bash(sb *) Bash(rg *)
---

# Update a note

The change comes from the user. Do not "improve" a note beyond what was asked.

## Procedure

1. Resolve the note: `$ARGUMENTS`, then `rg --files wiki | rg "/<name>\.md$"`. If zero or
   several match, ask.
2. Read it and `CLAUDE.md`. Edit only what the request touches.
3. Preserve `created` and `source`. If `origin` was `human`, set it to `mixed`. If you changed the
   content, remove the `reviewed:` value (the human must review again).
4. If the `summary` no longer matches the body, update it to one accurate line.
5. Do not rename the note. A rename breaks `[[links]]`; if the user wants one, say so and propose
   the edits to every note that links to it (`sb links "<note>"`).
6. Run `sb validate <path>`, `sb index --write`, `sb log update "<Title>"`.
7. Show what changed in two or three lines and mention `git diff`.
````

`plugins/second-brain/skills/lint/SKILL.md`:

````markdown
---
name: lint
description: >
  Health-checks the Second Brain vault with the deterministic sb linter (broken links, missing
  summaries, orphans, duplicates, index drift, unreviewed agent notes, bad frontmatter), then
  proposes fixes and applies none without approval. Use for "lint my vault" or "check my notes".
allowed-tools: Read Edit Grep Glob Bash(sb *) Bash(rg *)
---

# Lint the vault

## Procedure

1. Run `sb lint --json`. Group the findings by code and print each as
   `CODE path:line message` so the user sees the codes.
2. Explain each group in one line:
   - `SB101` broken link · `SB102` missing summary · `SB103` orphan · `SB104` duplicate name/title
   - `SB105` index out of sync · `SB106` agent note not reviewed · `SB107` old schema
   - `SB108` bad frontmatter · `SB109` source file missing
3. Propose a concrete fix per finding, smallest first. Examples: for `SB105` run
   `sb index --write`; for `SB102` draft a one-line summary from the note body; for `SB101` suggest
   the closest existing note name or removing the link.
4. **Apply nothing** until the user approves, finding by finding or as a batch. Then apply, run
   `sb lint` again, and `sb log lint "<n> fixes"`.
5. Contradictions: after the deterministic pass, you may compare notes that share topics (use
   summaries from `_index.md`) and report conflicting claims. Label that section **suggestion, not
   verified** and quote both notes. Never edit notes to resolve a contradiction yourself.
6. `SB106` is cleared only by the human adding `reviewed: <date>`; offer to do it when they confirm
   they reviewed the note.
````

- [ ] **Step 5: Run the structure test and the unit tests**

Run: `bash tests/sb_structure_test.sh && bash tests/sb_cli_test.sh`
Expected: all `ok`. If a description is outside 150–400 characters, edit the description (not the test). If `claude plugin validate --strict` flags a skill frontmatter field, consult `https://code.claude.com/docs/en/skills.md` and fix the field.

- [ ] **Step 6: Manual skill smoke test (the one thing unit tests cannot cover)**

Run, from a scratch directory outside this repo:

```bash
tmp="$(mktemp -d)" && cd "$tmp" && claude --plugin-dir /home/igors/Code/aether-labs/plugins/plugins/second-brain
```

Inside the session: run `/second-brain:init`, answer the questions, then `/second-brain:capture a note about spaced repetition`, `/second-brain:ingest`, `/second-brain:find spaced repetition`, `/second-brain:lint`. Expected: files appear as described; `_log.md` has three entries; a `git log` shows local commits after each response when git was enabled; asking Claude to edit `_raw/x` is refused. Record any deviation as a fix in this task before committing.

- [ ] **Step 7: Checkpoint** — ask the user whether to commit. Suggested message: `feat(second-brain): init, capture, ingest, find, link, update and lint skills`.

---

### Task 10: Eval fixtures and eval cases

**Files:**
- Create: `plugins/second-brain/evals/_fixtures/notes/Resources/{Spaced Repetition,Active Recall,Zettelkasten}.md`
- Create: `plugins/second-brain/evals/_fixtures/notes-broken/Resources/{Broken Link,No Summary}.md`
- Create: `plugins/second-brain/evals/_fixtures/inbox/2026-09-30-0900-interleaving.md`
- Create: `plugins/second-brain/evals/{find-trigger,find-empty,ingest-twice,lint-planted,should-not-trigger}/…`
- Test: `tests/python/test_sb_fixtures.py`

**Interfaces:**
- Consumes: `sb init`, `sb index --write`, `sb lint`.
- Produces: eval cases runnable with `claude plugin eval` from the plugin root; fixtures proven by unit tests (AC4, AC7).

- [ ] **Step 1: Write the fixture notes**

`evals/_fixtures/notes/Resources/Spaced Repetition.md`:

```markdown
---
title: Spaced Repetition
summary: Reviewing material at growing intervals to fight forgetting.
type: conceito
status: evergreen
origin: human
created: 2026-09-01
source:
---
Spaced repetition schedules reviews just before forgetting. It pairs well with [[Active Recall]].
```

`evals/_fixtures/notes/Resources/Active Recall.md`:

```markdown
---
title: Active Recall
summary: Retrieving an answer from memory instead of rereading it.
type: conceito
status: evergreen
origin: human
created: 2026-09-02
source:
---
Active recall strengthens memory by forcing retrieval. Used inside [[Spaced Repetition]].
```

`evals/_fixtures/notes/Resources/Zettelkasten.md`:

```markdown
---
title: Zettelkasten
summary: A network of atomic, linked notes written in your own words.
type: conceito
status: draft
origin: human
created: 2026-09-03
source:
---
Atomic notes linked by meaning. Study technique notes: [[Spaced Repetition]], [[Active Recall]].
```

`evals/_fixtures/notes-broken/Resources/Broken Link.md`:

```markdown
---
title: Broken Link
summary: A note that links to something that does not exist.
type: nota
status: draft
origin: human
created: 2026-09-04
source:
---
This points at [[Does Not Exist]] and at [[No Summary]].
```

`evals/_fixtures/notes-broken/Resources/No Summary.md`:

```markdown
---
title: No Summary
type: nota
status: draft
origin: human
created: 2026-09-05
source:
---
This note has no summary. It links back to [[Broken Link]].
```

`evals/_fixtures/inbox/2026-09-30-0900-interleaving.md`:

```markdown
---
captured: 2026-09-30T09:00
from: user
---
Interleaving: mixing different problem types in one study session instead of blocking them
makes me better at telling concepts apart. Feels harder but sticks longer. Goes well with spaced
repetition and active recall.
```

- [ ] **Step 2: Write the failing fixture test**

`tests/python/test_sb_fixtures.py`:

```python
import io
import shutil
import tempfile
import unittest
from pathlib import Path

from sb_helpers import PLUGIN
from sb.cli import main

FIXTURES = PLUGIN / "evals" / "_fixtures"


def lint_codes(root):
    out = io.StringIO()
    code = main(["lint", "--json", "--vault", str(root)], out=out, err=io.StringIO())
    import json
    return code, {f["code"] for f in json.loads(out.getvalue())}


def build(tmp, notes_dir):
    root = Path(tmp) / "vault"
    main(["init", "--vault", str(root), "--language", "en"], out=io.StringIO(), err=io.StringIO())
    shutil.copytree(FIXTURES / notes_dir, root / "wiki", dirs_exist_ok=True)
    main(["index", "--write", "--vault", str(root)], out=io.StringIO(), err=io.StringIO())
    return root


class FixtureTests(unittest.TestCase):
    def test_clean_fixture_vault_lints_clean(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(lint_codes(build(tmp, "notes")), (0, set()))

    def test_broken_fixture_reports_the_planted_problems(self):
        with tempfile.TemporaryDirectory() as tmp:
            code, codes = lint_codes(build(tmp, "notes-broken"))
        self.assertEqual(code, 1)
        self.assertTrue({"SB101", "SB102"} <= codes)

    def test_inbox_fixture_has_no_frontmatter_the_linter_would_scan(self):
        self.assertTrue((FIXTURES / "inbox" / "2026-09-30-0900-interleaving.md").is_file())


if __name__ == "__main__":
    unittest.main()
```

Run: `bash tests/sb_cli_test.sh`
Expected: PASS once Step 1 files exist (it exercises `init` + `index` + `lint` end to end). If it fails, fix the fixture content, not the linter.

- [ ] **Step 3: Write the eval cases**

Common `scaffold.sh` for `find-trigger` and `find-empty` (create at `evals/find-trigger/scaffold.sh`, and the same content at `evals/find-empty/scaffold.sh`):

```bash
#!/usr/bin/env bash
# Seeds the workspace with a clean vault containing three linked study notes.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sb="$here/../../bin/sb"
"$sb" init --vault . --language en >/dev/null
cp -r "$here/../_fixtures/notes/." wiki/
"$sb" index --write --vault . >/dev/null
```

`evals/ingest-twice/scaffold.sh` — same as above plus, before the last line:

```bash
cp "$here/../_fixtures/inbox/"*.md _inbox/
```

`evals/lint-planted/scaffold.sh` — same as the first script but copying `notes-broken`:

```bash
#!/usr/bin/env bash
# Seeds the workspace with a vault that has a broken link and a note without summary.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sb="$here/../../bin/sb"
"$sb" init --vault . --language en >/dev/null
cp -r "$here/../_fixtures/notes-broken/." wiki/
"$sb" index --write --vault . >/dev/null
```

Each `case.yaml` (change `name`/`description`/`tags` per case; `should-not-trigger` has no `context`):

```yaml
schema_version: "1.1"
name: find-trigger
description: A question about the vault fires the find skill and cites the right note.
tags: [find]
context:
  scaffold_script: scaffold.sh
```

Case contents:

`evals/find-trigger/prompt.md`:

```markdown
---
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill, Bash]
---

What do I know about spaced repetition?
```

`evals/find-trigger/graders/skill-fired.md`:

```markdown
---
type: tool_used
tool: Skill
input_match: '"skill"\s*:\s*"(?:second-brain:)?find"'
---
```

`evals/find-trigger/graders/cites-note.md`:

```markdown
---
type: regex
pattern: '\[\[Spaced Repetition\]\]'
target: last_message
---
```

`evals/find-empty/prompt.md`:

```markdown
---
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill, Bash]
---

What do my notes say about Kubernetes operators?
```

`evals/find-empty/graders/admits-gap.md`:

```markdown
---
type: llm
---

PASS if the reply states that the vault has no notes on Kubernetes operators, and does not
present Kubernetes facts as coming from the user's notes.
FAIL if it answers about Kubernetes operators as if the vault covered it, or cites a note that
does not discuss them.
```

`evals/ingest-twice/prompt.md`:

```markdown
---
runs: 3
max_turns: 40
allowed_tools: [Read, Write, Edit, Glob, Grep, Skill, Bash]
---

Ingest the item in _inbox into my vault. Then run the ingest for that same item a second time.
```

`evals/ingest-twice/graders/skill-fired.md`:

```markdown
---
type: tool_used
tool: Skill
input_match: '"skill"\s*:\s*"(?:second-brain:)?ingest"'
---
```

`evals/ingest-twice/graders/one-note.md`:

```markdown
---
type: regex
pattern: '^wiki/.*\.md$'
flags: m
target: files
match: "count:1"
---
```

`evals/ingest-twice/graders/index-updated.md`:

```markdown
---
type: regex
pattern: 'Interleav'
flags: i
target: { source: file, path: _index.md }
---
```

`evals/ingest-twice/graders/logged.md`:

```markdown
---
type: regex
pattern: 'ingest \|'
target: { source: file, path: _log.md }
---
```

`evals/lint-planted/prompt.md`:

```markdown
---
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill, Bash]
---

Lint my vault and tell me what is wrong with it.
```

`evals/lint-planted/graders/skill-fired.md`:

```markdown
---
type: tool_used
tool: Skill
input_match: '"skill"\s*:\s*"(?:second-brain:)?lint"'
---
```

`evals/lint-planted/graders/reports-broken-link.md`:

```markdown
---
type: regex
pattern: 'SB101'
target: last_message
---
```

`evals/lint-planted/graders/reports-missing-summary.md`:

```markdown
---
type: regex
pattern: 'SB102'
target: last_message
---
```

`evals/should-not-trigger/prompt.md`:

```markdown
---
runs: 3
max_turns: 5
allowed_tools: [Read, Glob, Grep, Skill]
---

Write a Python function that reverses a singly linked list, with a docstring.
```

`evals/should-not-trigger/graders/skill-silent.md`:

```markdown
---
type: tool_used
tool: Skill
input_match: '"skill"\s*:\s*"(?:second-brain:)?(init|capture|ingest|find|link|update|lint)"'
min: 0
max: 0
arm: both
---
```

`chmod +x` every `scaffold.sh`.

- [ ] **Step 4: Validate the eval layout and run the suite**

Run: `cd plugins/second-brain && claude plugin eval . 2>&1 | tail -40; cd ../..`
Expected: the five cases load and run. If the command reports early-access/unavailable (documented under "Troubleshooting"), record that in the task notes and in the README, keep the cases (they are still the acceptance specification), and rely on Step 5 plus the Task 9 manual smoke test for AC2/AC3. If a case fails because the skill misbehaves, fix the **skill text** (Task 9 files), then re-run. Do not weaken a grader to make it pass.

- [ ] **Step 5: Re-run the deterministic suite**

Run: `bash tests/run.sh`
Expected: everything passes, including the fixture tests.

- [ ] **Step 6: Checkpoint** — ask the user whether to commit. Suggested message: `test(second-brain): eval cases and fixture vaults`.

---

### Task 11: README, spec sync and final verification

**Files:**
- Create: `plugins/second-brain/README.md`
- Modify: `docs/specs/2026-09-30-second-brain-design.md` (sync the differences found while implementing)
- Modify: `README.md` (only if the row added in Task 1 needs adjusting)

**Interfaces:**
- Consumes: the finished plugin.
- Produces: user documentation with the acceptance traceability table.

- [ ] **Step 1: Write the plugin README**

`plugins/second-brain/README.md` must contain these sections, with real content (no placeholders):

1. **What it is** — three sentences, the "deterministic first" rule, link to the spec.
2. **Install** — `/plugin marketplace add aether-labs-org/plugins` then `/plugin install second-brain@aether-labs`; requirements: Python 3.9+, `ripgrep` for the skills, `git` for auto-commit.
3. **Quickstart** — a transcript-style example:

   ```
   $ mkdir ~/brain && cd ~/brain && claude
   > /second-brain:init
   > /second-brain:capture spaced repetition works best with active recall
   > /second-brain:ingest
   > /second-brain:find what do I know about spaced repetition?
   > /second-brain:lint
   ```
4. **Skills** — a table of the seven skills with one example prompt each.
5. **The `sb` CLI** — table of subcommands, exit codes, lint codes SB101–SB109, and examples (`sb lint`, `sb index --check`, `sb links "Spaced Repetition" --suggest`).
6. **Protection and auto-commit** — what the guard denies/asks, the `auto_commit` setting and how to turn it off (`/plugin` → configure, or `userConfig`), that commits happen **after every response** (the `Stop` event), local only, never pushed.
7. **Limits** — Bash cannot be fully fenced (best-effort pattern match; git is the net); restricted YAML subset; no semantic search in v0.1; hooks run Python on each matching tool call in every session and are no-ops outside a vault.
8. **Roadmap** — the F1–F4 table from spec §11 with triggers.
9. **Acceptance traceability** — table AC1–AC10 → the test or eval that covers it, using the exact file names from this plan.

- [ ] **Step 2: Sync the spec with what was built**

Edit `docs/specs/2026-09-30-second-brain-design.md`:
- §5 table: add the row ``| `sb init [--language L] [--areas a,b] [--git]` | Scaffold a vault; writes `.second-brain.json` last; idempotent |``.
- §6 Stop row and §2 D7: replace the commit message with `sb: update YYYY-MM-DD (N changes)` and add "`Stop` fires after each response, so commits are per response".
- §7 `ingest`: state that `source:` is written as `_inbox/_done/<file>` (the path after the move).
- §12: add "8. `sb init` is a CLI subcommand (not only a skill) so scaffolding is testable; 9. commit cadence is per response because the documented `Stop` event fires per turn."
- Change the header `Status:` line to `implemented in v0.1.0; see plan 2026-10-01-second-brain-plan.md`.

- [ ] **Step 3: Full verification**

Run: `make check && make validate`
Expected: every script reports `ok`; `claude plugin validate` passes for all three plugins with `--strict`.

Run: `grep -rn "TBD\|TODO\|FIXME" plugins/second-brain docs/specs/2026-09-30-second-brain-design.md || echo "none"`
Expected: `none`.

Run: `git status --short`
Expected: only files under `plugins/second-brain/`, `tests/`, `docs/`, `.claude-plugin/marketplace.json`, `Makefile`, `README.md`.

- [ ] **Step 4: Acceptance walk-through**

Tick off AC1–AC10 from spec §10 against the traceability table. For AC2 and AC3 state explicitly which evidence was used: eval run output, or the Task 9 manual smoke test if `claude plugin eval` was unavailable. Do not claim an AC that has no executed evidence.

- [ ] **Step 5: Checkpoint** — show the user the summary of what was verified and what was not, then ask whether to commit and whether to push. Suggested message: `docs(second-brain): README, spec sync and acceptance traceability`.

---

## Self-Review (against the spec)

**Spec coverage**

| Spec section | Task |
| --- | --- |
| §3 layout, marketplace, Makefile, tests registration | 1, 11 |
| §4.1 vault layout, §7 `init` | 6, 9 |
| §4.2 frontmatter, restricted subset (SB108) | 2, 4 |
| §4.3 conventions (links, index, log) | 2, 3 |
| §5 CLI `index/lint/links/validate/log`, exit codes, error handling | 3, 4, 5 |
| §5 lint rules SB101–SB109 | 4 |
| §6 guard (deny/ask, no-op outside vault, fail-open) | 7 |
| §6 PostToolUse validation | 8 |
| §6 Stop auto-commit (on by default, `.git`, no push, merge guard) + `userConfig` | 1, 8 |
| §7 seven skills | 9 |
| §8 data flow (`_inbox/_done`, source path) | 9, 11 |
| §9 tests and evals | 2–8, 10 |
| §10 AC1–AC10 | AC1: 6, 9; AC2: 9, 10; AC3: 10; AC4: 10; AC5: 7; AC6: 8; AC7: 5; AC8: 1, 9, 11; AC9: 1; AC10: 7, 8 |
| §11 future phases | 11 (README) |
| §12 differences | 11 (spec sync) |

**Placeholder scan:** none left; the two prose hedges (Task 4 `os.makedirs` note, Task 6 `.gitignore` bookkeeping note) carry the exact fix to apply.

**Type consistency:** `Finding(code, path, line, message)`, `check_note(note)`, `lint(root, config)` (Task 4) are called with those signatures in Tasks 5, 8, 9. `Note.rel/.name/.data/.body/.body_line/.errors` (Task 3) are used consistently. `init.run(...)` returns the dict that `cmd_init` (Task 5) formats. `autocommit.run(cwd, env, today)` and `postcheck.check(event, cwd)` match their hook scripts.

**Review Focus coverage:** items 1–5 map to `test_accented_and_spaced_names_resolve`, `EmptyVaultTests`, `test_crlf_and_bom`, `test_lint_on_malformed_marker_exits_2` + `test_binary_note_is_reported_without_aborting`, and `test_works_from_a_subfolder` + `test_symlink_into_raw_is_denied` + traversal cases.

**Known deviation worth the user's attention:** the documented `Stop` event fires after **every response**, not once per session, so auto-commit produces one commit per response (recorded in spec §12 in Task 11). If per-session commits are preferred, `SessionEnd` is the alternative event; it is a one-line change in `hooks.json` plus the test at `test_hooks_json_wires_the_three_events`.
