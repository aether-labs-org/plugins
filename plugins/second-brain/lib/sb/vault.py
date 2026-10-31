"""Vault discovery and note loading."""
import json
import os
from dataclasses import dataclass
from pathlib import Path

from .frontmatter import parse

MARKER = ".second-brain.json"
SCHEMA_VERSION = 1
ASSET_SKIP_DIRS = {".git", ".sb", ".obsidian", ".trash"}


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


def is_note_rel(rel):
    """True when a path relative to `wiki/` is a note (not `_about.md`, `_assets/`, dot paths,
    or an Excalidraw drawing)."""
    parts = rel.split("/")
    if any(part.startswith(("_", ".")) for part in parts):
        return False
    return not parts[-1].endswith(".excalidraw.md")


def asset_names(root):
    """Basenames of every non-Markdown file in the vault (Obsidian resolves embeds by name)."""
    names = set()
    for _, dirs, files in os.walk(str(root)):
        dirs[:] = [d for d in dirs if d not in ASSET_SKIP_DIRS]
        names.update(f for f in files if not f.endswith(".md") and not f.startswith("."))
    return names


def load_notes(root):
    root = Path(root)
    wiki = root / "wiki"
    if not wiki.is_dir():
        return []
    notes = []
    for path in sorted(wiki.rglob("*.md")):
        if not is_note_rel(path.relative_to(wiki).as_posix()):
            continue
        notes.append(load_note(root, path))
    return notes
