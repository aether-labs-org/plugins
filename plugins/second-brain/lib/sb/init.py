"""Vault scaffolding: the backend of /second-brain:init (spec 5.1, 6.1, D52, D53, D57)."""
import json
import subprocess
from pathlib import Path

from .fsutil import write_atomic
from .vault import MARKER, SCHEMA_VERSION

PLUGIN_ROOT = Path(__file__).resolve().parents[2]
TEMPLATES = PLUGIN_ROOT / "templates"
BASE_DIRS = ("_inbox/_done", "_raw", "_assets", "_meta", "_views", ".claude")
KEEP_DIRS = ("_inbox/_done", "_raw", "_assets")      # empty at first: a .gitkeep lets a clone have them
GITIGNORE_LINES = (".agents/second-brain/cache/", ".obsidian/workspace*", ".smart-env/")
# (path in the vault, template file) written when absent
EXTRA_FILES = ((".claude/settings.json", "settings.json"),
               ("_meta/web-clipper-template.json", "web-clipper-template.json"),
               ("_views/unreviewed.base", "unreviewed.base"),
               ("_views/notes.base", "notes.base"))
ASSETS_HINT = ("Obsidian: Settings, Files and links, Default location for new attachments, "
               "set it to the folder _assets")
MAX_DEPTH = 2
YAML_RISKY_START = "|>{[&*!'\"%@`#"


def default_folders():
    """The folders `sb init` creates when none are given: Projects, Areas, Resources, Archive."""
    return parse_folders((TEMPLATES / "folders-default.json").read_text(encoding="utf-8"))


def _check_path(path):
    if not isinstance(path, str) or not path or path != path.strip():
        raise ValueError("folder path must be a non-empty string without surrounding spaces: %r" % (path,))
    if any(ord(ch) < 32 or ord(ch) == 127 for ch in path):
        raise ValueError("folder path has control characters: %r" % path)
    if path.startswith("/") or "\\" in path or ":" in path.split("/")[0][1:2]:
        raise ValueError("folder path must be relative with forward slashes: %r" % path)
    parts = path.split("/")
    if len(parts) > MAX_DEPTH:
        raise ValueError("folder path has more than %d levels: %r" % (MAX_DEPTH, path))
    for part in parts:
        if not part or part != part.strip():
            raise ValueError("folder path has an empty or padded segment: %r" % path)
        if part in (".", "..") or part.startswith(("_", ".")):
            raise ValueError("folder segment may not be %r or start with _ or .: %r" % (part, path))


def parse_folders(text):
    """Validate a JSON array of `{path, description, conventions?}` and return clean dicts."""
    try:
        data = json.loads(text)
    except ValueError as exc:
        raise ValueError("folders must be JSON: %s" % exc) from exc
    if not isinstance(data, list):
        raise ValueError("folders must be a JSON array of {path, description, conventions?}")
    found, seen = [], set()
    for item in data:
        if not isinstance(item, dict):
            raise ValueError("each folder must be an object with path and description: %r" % (item,))
        path = item.get("path")
        _check_path(path)
        description = item.get("description")
        if not isinstance(description, str) or not description.strip():
            raise ValueError("folder %r needs a non-empty description" % path)
        conventions = item.get("conventions", "")
        if conventions is None:
            conventions = ""
        if not isinstance(conventions, str):
            raise ValueError("conventions of %r must be a string" % path)
        key = path.casefold()
        if key in seen:
            raise ValueError("duplicate folder path (ignoring case): %r" % path)
        seen.add(key)
        found.append({"path": path, "description": " ".join(description.split()),
                      "conventions": conventions.strip()})
    return found


def enclosing_repo(target):
    """The git work tree that contains `target` without being `target` itself, or None."""
    here = Path(target).resolve()
    for candidate in (here, *here.parents):
        if (candidate / ".git").exists():
            return None if candidate == here else candidate
    return None


def _scalar(text):
    """A frontmatter value the restricted parser reads back unchanged."""
    if text[:1] in YAML_RISKY_START or " #" in text:
        return '"%s"' % text.replace('"', "'")
    return text


def about_text(folder):
    parts = ["---", "description: %s" % _scalar(folder["description"]), "---", ""]
    if folder.get("conventions"):
        parts += ["## Conventions", folder["conventions"].strip(), ""]
    return "\n".join(parts)


def _write_new(root, name, text, created, kept):
    path = root / name
    if path.exists():
        kept.append(name)
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        write_atomic(path, text)
        created.append(name)


def _append_gitignore(root, lines, created, kept):
    path = root / ".gitignore"
    existed = path.exists()
    existing = path.read_text(encoding="utf-8") if existed else ""
    present = set(existing.splitlines())
    missing = [line for line in lines if line not in present]
    if not missing:
        kept.append(".gitignore")
        return
    if existing and not existing.endswith("\n"):
        existing += "\n"
    write_atomic(path, existing + "".join(line + "\n" for line in missing))
    (kept if existed else created).append(".gitignore")


def run(root, language="en", folders=None, remote=None, git=False):
    root = Path(root)
    if (root / MARKER).exists():
        return {"status": "exists", "root": str(root), "created": [], "kept": [MARKER],
                "warnings": [], "hints": []}
    folders = default_folders() if folders is None else folders
    root.mkdir(parents=True, exist_ok=True)
    created, kept, warnings = [], [], []
    for rel in (*BASE_DIRS, *("wiki/%s" % f["path"] for f in folders)):
        (root / rel).mkdir(parents=True, exist_ok=True)
    for folder in folders:
        _write_new(root, "wiki/%s/_about.md" % folder["path"], about_text(folder), created, kept)

    template = (TEMPLATES / "CLAUDE.md").read_text(encoding="utf-8")
    _write_new(root, "CLAUDE.md", template.replace("{{language}}", language), created, kept)
    for rel in KEEP_DIRS:
        _write_new(root, rel + "/.gitkeep", "", created, kept)
    for rel, source in EXTRA_FILES:
        _write_new(root, rel, (TEMPLATES / source).read_text(encoding="utf-8"), created, kept)
    _append_gitignore(root, GITIGNORE_LINES, created, kept)

    if git and not (root / ".git").exists():
        try:
            subprocess.run(["git", "init", "-q", str(root)], check=True, capture_output=True)
            created.append(".git")
        except (OSError, subprocess.CalledProcessError) as exc:
            warnings.append("git init failed: %s" % exc)
    if remote and (root / ".git").exists():
        done = subprocess.run(["git", "-C", str(root), "remote", "add", "origin", remote],
                              capture_output=True, text=True)
        if done.returncode != 0:
            warnings.append("git remote add failed: %s" % (done.stderr.strip() or done.stdout.strip()))

    marker = {"schema_version": SCHEMA_VERSION, "language": language,
              "sync": "pull" if remote else "local"}
    (root / MARKER).parent.mkdir(parents=True, exist_ok=True)
    write_atomic(root / MARKER, json.dumps(marker, ensure_ascii=False, indent=2) + "\n")
    created.append(MARKER)
    return {"status": "created", "root": str(root), "created": created, "kept": kept,
            "warnings": warnings, "hints": [ASSETS_HINT]}
