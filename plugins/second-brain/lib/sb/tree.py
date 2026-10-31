"""Folder contract: the `_about.md` of each folder under wiki/ and the compact tree (spec 6.1)."""
import re
from pathlib import Path

from .frontmatter import parse
from .sanitize import clean_inline

NO_DESCRIPTION = "(no description)"
SECTIONS = {"conventions": "conventions", "examples": "examples", "anti-examples": "anti_examples"}
HEADING_RE = re.compile(r"^##[ \t]+(.+?)[ \t]*$")
TRUE_VALUES = ("true", "yes", "1")
DESCRIPTION_CHARS = 120


def _skipped(name):
    return name.startswith(("_", "."))


def _is_true(value):
    return str(value if value is not None else "").strip().lower() in TRUE_VALUES


def read_about(folder):
    """`description`, `protected` and the three sections of `<folder>/_about.md`."""
    result = {"description": NO_DESCRIPTION, "protected": False,
              "conventions": "", "examples": "", "anti_examples": ""}
    try:
        text = (Path(folder) / "_about.md").read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return result
    parsed = parse(text)
    description = parsed.data.get("description")
    if isinstance(description, str) and description.strip():
        result["description"] = " ".join(description.split())
    result["protected"] = _is_true(parsed.data.get("protected"))
    current, chunks = None, {}
    for line in parsed.body.split("\n"):
        heading = HEADING_RE.match(line)
        if heading:
            current = SECTIONS.get(heading.group(1).strip().lower())
            if current:
                chunks.setdefault(current, [])
        elif current:
            chunks[current].append(line)
    for key, lines in chunks.items():
        result[key] = "\n".join(lines).strip()
    return result


def _walk(wiki, directory):
    folders = []
    for child in sorted(directory.iterdir(), key=lambda p: p.name):
        if not child.is_dir() or _skipped(child.name):
            continue
        entry = {"path": child.relative_to(wiki).as_posix()}
        entry.update(read_about(child))
        entry["children"] = _walk(wiki, child)
        folders.append(entry)
    return folders


def load(root):
    """Folder tree under wiki/ (names not starting with `_` or `.`), sorted by name."""
    wiki = Path(root) / "wiki"
    if not wiki.is_dir():
        return []
    return _walk(wiki, wiki)


def flatten(folders, depth=0):
    """`(depth, folder)` in tree order."""
    for folder in folders:
        yield depth, folder
        for item in flatten(folder["children"], depth + 1):
            yield item


def render_compact(folders, limit=2000):
    """One line per folder: `<indent><name>/ — <description>`; at most `limit` characters."""
    lines = ["%s%s/ — %s" % ("  " * depth, folder["path"].rsplit("/", 1)[-1],
                             clean_inline(folder["description"], DESCRIPTION_CHARS))
             for depth, folder in flatten(folders)]
    if limit is None or len("\n".join(lines)) <= limit:
        return "\n".join(lines)
    for keep in range(len(lines) - 1, -1, -1):
        text = "\n".join(lines[:keep] + ["… (+%d more)" % (len(lines) - keep)])
        if len(text) <= limit:
            return text
    return ""


def folder_protected(root, note_rel):
    """True when any folder above `note_rel` (relative to the vault) has `protected: true`."""
    parts = note_rel.split("/")
    if parts[0] != "wiki":
        return False
    folder = Path(root) / "wiki"
    for part in parts[1:-1]:
        folder = folder / part
        if read_about(folder)["protected"]:
            return True
    return False
