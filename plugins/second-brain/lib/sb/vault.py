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
