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
    existed = path.exists()
    existing = path.read_text(encoding="utf-8") if existed else ""
    present = set(existing.splitlines())
    missing = [line for line in GITIGNORE_LINES if line not in present]
    if not missing:
        kept.append(".gitignore")
        return
    if existing and not existing.endswith("\n"):
        existing += "\n"
    write_atomic(path, existing + "".join(line + "\n" for line in missing))
    (kept if existed else created).append(".gitignore")


def run(root, language="en", areas=(), git=False):
    root = Path(root)
    if (root / MARKER).exists():
        return {"status": "exists", "root": str(root), "created": [], "kept": [MARKER],
                "warnings": []}
    root.mkdir(parents=True, exist_ok=True)
    created, kept, warnings = [], [], []

    clean = []
    for area in areas:
        if not str(area).strip():
            continue
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
