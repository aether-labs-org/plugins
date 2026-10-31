"""`sb doctor`: five checks with a fix command each (spec 6.5, D32)."""
import importlib.util
import json
import os
import shutil
import sqlite3
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path

from .vault import VaultError, load_config

_which = shutil.which
HEARTBEAT_MAX_AGE = timedelta(days=7)
REQUIRED_PLUGINS = ("second-brain@aether-labs", "document-skills@anthropic-agent-skills",
                    "obsidian@obsidian-skills")
REQUIRED_DENY = ("Edit(/_raw/**)", "Bash(git push --force*)", "Bash(git push -f*)",
                 "Bash(git reset --hard*)", "Bash(git clean*)")
TOOL_HINTS = {
    "pandoc": "sudo apt install pandoc poppler-utils",
    "pdftotext": "sudo apt install pandoc poppler-utils",
    "markitdown": "uv tool install 'markitdown[all]'",
    "npx": "install Node.js (npx runs defuddle for web pages)",
    "pypdf": "pip install pypdf",
}
OBSIDIAN_SETUP = """Recommended Obsidian setup
| Need | Recommendation | Note |
| --- | --- | --- |
| Agent inside Obsidian | Terminal (polyipseity) | runs the real `claude`; hooks apply. Claudian / Agent Client unsupported |
| Web capture | Obsidian Web Clipper + `_meta/web-clipper-template.json` | saves to `_inbox/` |
| Review queue | Bases (core) + `_views/unreviewed.base` | |
| Review actions | `second-brain-companion` (BRAT) | milestone D |
| Squad | Obsidian Git: pull on startup, rebase, auto commit-and-sync for human edits | mobile Git is unstable |
| HTML | HTML Viewer with scripts off for third-party pages | |
| draw.io / Excalidraw | Drawio Preview; Excalidraw (zsviczian) | `*.excalidraw.md` is excluded from notes |
| Human search | Omnisearch, Smart Connections (optional) | not used by the agent |
| Avoid | Linter (rewrites frontmatter on save) | breaks hashes, ghost diffs in squad |"""


def _result(check, status, detail, fix=""):
    return {"check": check, "status": status, "detail": detail, "fix": fix}


def _has_fts5():
    try:
        conn = sqlite3.connect(":memory:")
        try:
            conn.execute("CREATE VIRTUAL TABLE t USING fts5(x)")
        finally:
            conn.close()
        return True
    except sqlite3.Error:
        return False


def _importable(name):
    try:
        return importlib.util.find_spec(name) is not None
    except (ImportError, ValueError):
        return False


def check_python():
    version = "%d.%d.%d" % sys.version_info[:3]
    if sys.version_info < (3, 9):
        return _result("python", "fail", "Python %s is older than 3.9" % version,
                       "install Python 3.9 or newer")
    if not _has_fts5():
        return _result("python", "warn", "Python %s without SQLite FTS5: slow search" % version,
                       "use a Python build whose sqlite3 has FTS5 (any recent python.org or distro build)")
    return _result("python", "ok", "Python %s with SQLite FTS5" % version)


def check_settings(root):
    path = Path(root) / ".claude" / "settings.json"
    if not path.is_file():
        return _result("settings", "fail", ".claude/settings.json is missing", "sb init --upgrade --yes")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            raise ValueError("not a JSON object")
    except (OSError, ValueError) as exc:
        return _result("settings", "fail", ".claude/settings.json is unreadable: %s" % exc,
                       "fix the JSON by hand; templates/settings.json in the plugin is the reference")
    enabled = data.get("enabledPlugins")
    enabled = enabled if isinstance(enabled, dict) else {}
    deny = (data.get("permissions") or {}).get("deny") if isinstance(data.get("permissions"), dict) else None
    deny = deny if isinstance(deny, list) else []
    missing = ["plugin " + p for p in REQUIRED_PLUGINS if enabled.get(p) is not True]
    missing += ["deny " + r for r in REQUIRED_DENY if r not in deny]
    if missing:
        return _result("settings", "fail", "missing in .claude/settings.json: " + ", ".join(missing),
                       "sb init --upgrade --yes")
    return _result("settings", "ok", ".claude/settings.json enables the plugins and has the deny rules")


def check_extraction(which):
    missing = [t for t in ("pandoc", "markitdown", "pdftotext", "npx") if not which(t)]
    if not _importable("pypdf"):
        missing.append("pypdf")
    if not missing:
        return _result("extraction", "ok", "pandoc, markitdown, pdftotext, npx and pypdf are available")
    hints = []
    for tool in missing:
        if TOOL_HINTS[tool] not in hints:
            hints.append(TOOL_HINTS[tool])
    return _result("extraction", "warn", "missing extraction tools: " + ", ".join(missing),
                   "; ".join(hints))


def check_hooks(root, now):
    path = Path(root) / ".sb" / "heartbeat.json"
    problem = "hooks may not be running: is the plugin installed for this project?"
    try:
        beat = datetime.fromisoformat(json.loads(path.read_text(encoding="utf-8"))["session_start"])
    except (OSError, ValueError, KeyError, TypeError):
        return _result("hooks", "warn", "no usable .sb/heartbeat.json; " + problem,
                       "install the plugin with --scope project and start a session in the vault")
    if now - beat > HEARTBEAT_MAX_AGE:
        return _result("hooks", "warn", "last SessionStart was %s; %s" % (beat.date().isoformat(), problem),
                       "install the plugin with --scope project and start a session in the vault")
    return _result("hooks", "ok", "SessionStart ran on %s" % beat.date().isoformat())


def _git(root, *args):
    return subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True, timeout=30)


def check_git(root):
    root = Path(root)
    try:
        sync = load_config(root).get("sync", "local")
    except VaultError:
        sync = "local"
    try:
        top = _git(root, "rev-parse", "--show-toplevel")
    except (OSError, subprocess.SubprocessError) as exc:
        return _result("git", "warn", "git is not usable: %s" % exc, "install git")
    if top.returncode != 0:
        status = "fail" if sync == "squad" else "warn"
        return _result("git", status, "the vault is not a git repository (no auto-commit, no safety net)",
                       "git init (or sb init --git for a new vault)")
    if os.path.realpath(top.stdout.strip()) != os.path.realpath(root):
        return _result("git", "fail",
                       "git top-level is %s, not the vault root: a vault is its own repository" % top.stdout.strip(),
                       "move the vault out of the other repository, or run git init in the vault root")
    if sync != "squad":
        return _result("git", "ok", "the vault is its own git repository")
    problems = []
    if _git(root, "remote").stdout.strip() == "":
        problems.append("no remote")
    elif _git(root, "rev-parse", "--abbrev-ref", "@{u}").returncode != 0:
        problems.append("no upstream branch")
    if (root / ".sb" / "push-pending").exists():
        problems.append(".sb/push-pending exists: the last push failed")
    if problems:
        return _result("git", "warn", "squad sync: " + "; ".join(problems),
                       "git remote add origin <url> && git push -u origin HEAD; "
                       "a pending push is retried at the next SessionStart")
    return _result("git", "ok", "squad vault with remote and upstream, nothing pending")


def run(root, now=None, which=None):
    now = now or datetime.now()
    which = which or _which
    return [check_python(), check_settings(root), check_extraction(which), check_hooks(root, now),
            check_git(root)]


def render_text(results):
    lines = []
    for r in results:
        lines.append("%-4s %s: %s" % (r["status"], r["check"], r["detail"]))
        if r["status"] != "ok" and r["fix"]:
            lines.append("     fix: " + r["fix"])
    return "\n".join(lines) + "\n\n" + OBSIDIAN_SETUP
