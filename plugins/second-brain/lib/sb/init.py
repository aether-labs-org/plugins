"""Vault scaffolding: the backend of /second-brain:init (spec sections 6.3 and 7)."""
import json
import subprocess
from pathlib import Path

from . import index as index_mod
from . import logfile
from .fsutil import write_atomic
from .vault import MARKER, SCHEMA_VERSION

TEMPLATES = Path(__file__).resolve().parents[2] / "templates"
PROFILES = ("personal", "work", "project", "squad")
BASE_DIRS = ("_inbox/_done", "_raw", "_meta", "_views", ".claude")
GITIGNORE_LINES = (".sb/", ".obsidian/workspace*", ".smart-env/")
SQUAD_GITIGNORE_LINES = ("_index.md", "_log.md")
# (path in the vault, template file) written when absent
EXTRA_FILES = ((".claude/settings.json", "settings.json"),
               ("_meta/web-clipper-template.json", "web-clipper-template.json"),
               ("_views/unreviewed.base", "unreviewed.base"))


def load_profile(name):
    if name not in PROFILES:
        raise ValueError("unknown profile %r (expected one of %s)" % (name, ", ".join(PROFILES)))
    return json.loads((TEMPLATES / "profiles" / ("%s.json" % name)).read_text(encoding="utf-8"))


def enclosing_repo(target):
    """The git work tree that contains `target` without being `target` itself, or None."""
    here = Path(target).resolve()
    for candidate in (here, *here.parents):
        if (candidate / ".git").exists():
            return None if candidate == here else candidate
    return None


def about_text(folder):
    parts = ["---", "description: %s" % folder["description"],
             "protected: %s" % ("true" if folder.get("protected") else "false"), "---", ""]
    for heading, key in (("Conventions", "conventions"), ("Examples", "examples"),
                         ("Anti-examples", "anti_examples")):
        parts += ["## %s" % heading, folder.get(key, "").strip(), ""]
    return "\n".join(parts)


def gitignore_lines(sync):
    return GITIGNORE_LINES + (SQUAD_GITIGNORE_LINES if sync == "squad" else ())


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


def run(root, language="en", profile="personal", remote=None, git=False, areas=()):
    root = Path(root)
    spec = load_profile(profile)
    if (root / MARKER).exists():
        return {"status": "exists", "root": str(root), "created": [], "kept": [MARKER],
                "warnings": []}
    root.mkdir(parents=True, exist_ok=True)
    created, kept, warnings = [], [], []
    folder_names = [f["path"] for f in spec["folders"]]

    clean = []
    for area in areas:
        if not str(area).strip():
            continue
        name = _clean_area(area)
        if not name:
            warnings.append("ignored invalid area name %r" % area)
        elif "Areas" not in folder_names:
            warnings.append("ignored area %r: the %s profile has no Areas folder" % (area, profile))
        else:
            clean.append(name)
    for rel in (*BASE_DIRS, *("wiki/%s" % n for n in folder_names),
                *("wiki/Areas/%s" % a for a in clean)):
        (root / rel).mkdir(parents=True, exist_ok=True)
    for folder in spec["folders"]:
        _write_new(root, "wiki/%s/_about.md" % folder["path"], about_text(folder), created, kept)

    template = (TEMPLATES / "CLAUDE.md").read_text(encoding="utf-8")
    _write_new(root, "CLAUDE.md", template.replace("{{language}}", language), created, kept)
    for rel, source in EXTRA_FILES:
        _write_new(root, rel, (TEMPLATES / source).read_text(encoding="utf-8"), created, kept)
    _append_gitignore(root, gitignore_lines(spec["sync"]), created, kept)
    _write_new(root, "_index.md", index_mod.build([]), created, kept)
    _write_new(root, "_log.md", "", created, kept)

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

    marker = {"schema_version": SCHEMA_VERSION, "language": language, "profile": profile,
              "sync": spec["sync"], "areas": clean}
    write_atomic(root / MARKER, json.dumps(marker, ensure_ascii=False, indent=2) + "\n")
    created.append(MARKER)
    logfile.append(root, "init", "vault created")
    return {"status": "created", "root": str(root), "created": created, "kept": kept,
            "warnings": warnings}
