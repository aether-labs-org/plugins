"""Provenance for ingest (spec 5.2): source ids, lookup of the notes made from a source,
sanitised converted copies under `_raw/.converted/`, and the inbox move."""
import hashlib
import json
import os
import re
from datetime import date
from pathlib import Path
from urllib.parse import urlsplit

from . import logfile
from .frontmatter import parse
from .fsutil import write_atomic
from .sanitize import clean_document, clean_inline
from .trust import norm
from .vault import load_notes

CONVERTED = "_raw/.converted"
SHA_ID_RE = re.compile(r"^sha256:[0-9a-f]{16}$")
DEFAULT_PORTS = {"http": "80", "https": "443"}


def _sha16(data):
    return hashlib.sha256(data).hexdigest()[:16]


def canonical_url(url):
    """Lower-case scheme and host, no fragment, no `utm_*` parameters, no trailing slash."""
    parts = urlsplit(str(url).strip())
    scheme = parts.scheme.lower()
    host = (parts.hostname or "").lower()
    if ":" in host:
        host = "[%s]" % host
    try:
        port = parts.port
    except ValueError:
        port = None
    if port is not None and str(port) != DEFAULT_PORTS.get(scheme):
        host = "%s:%d" % (host, port)
    path = parts.path.rstrip("/") if parts.path != "/" else ""
    query = "&".join(q for q in parts.query.split("&")
                     if q and not q.split("=", 1)[0].lower().startswith("utm_"))
    return "%s://%s%s%s" % (scheme, host, path, "?" + query if query else "")


def _is_url(target):
    return re.match(r"^https?://", str(target).strip(), re.IGNORECASE) is not None


def _resolve(root, target):
    path = Path(target)
    for candidate in ((path,) if path.is_absolute() else (Path(root) / path, path)):
        if candidate.is_file():
            return candidate
    raise ValueError("no such file: %s" % target)


def source_id_for(root, target):
    """`(source_id, kind)` with kind `file`, `url` or `inbox`."""
    if _is_url(target):
        return "url:" + canonical_url(target), "url"
    path = _resolve(root, target)
    data = path.read_bytes()
    try:
        rel = path.resolve().relative_to(Path(root).resolve()).parts
    except ValueError:
        rel = ()
    if rel[:1] == ("_inbox",):
        if path.suffix == ".md":
            fields = parse(data.decode("utf-8", "replace")).data
            for key in ("url", "source"):
                value = norm(fields.get(key))
                if _is_url(value):
                    return "url:" + canonical_url(value), "inbox"
        return "sha256:" + _sha16(data), "inbox"
    return "sha256:" + _sha16(data), "file"


def source_value(root, target):
    """The exact value for a note's `source:` field: the URL when the target is one, or an inbox
    clip carries one; else the item's final path (`_inbox/_done/<file>` for inbox items)."""
    if _is_url(target):
        return str(target).strip()
    path = _resolve(root, target)
    try:
        rel = path.resolve().relative_to(Path(root).resolve())
    except ValueError:
        return str(path)
    if rel.parts[:1] == ("_inbox",):
        if path.suffix == ".md":
            fields = parse(path.read_bytes().decode("utf-8", "replace")).data
            for key in ("url", "source"):
                value = norm(fields.get(key))
                if _is_url(value):
                    return value
        return "_inbox/_done/" + path.name
    return rel.as_posix()


def notes_for(root, source_id):
    """Rels of notes whose frontmatter `source_id` matches or that hold an agent block citing it."""
    block = re.compile(r"^>[ \t]*\[!agent\][^\n]*·[ \t]*%s[ \t]*$" % re.escape(source_id),
                       re.IGNORECASE | re.MULTILINE)
    found = []
    for note in load_notes(root):
        if norm(note.data.get("source_id")) == source_id or block.search(note.body):
            found.append(note.rel)
    return sorted(found)


def _converted_name(source_id):
    if SHA_ID_RE.match(source_id):
        return source_id.replace(":", "-") + ".md"
    if source_id.startswith("url:") and _is_url(source_id[4:]):
        return "url-%s.md" % _sha16(canonical_url(source_id[4:]).encode("utf-8"))
    raise ValueError("invalid source id: %r" % source_id)


def _quote(value, limit=500):
    return json.dumps(clean_inline(value, limit), ensure_ascii=False)


def save(root, source_id, text, tool, origin, today=None):
    """Write the sanitised extraction to `_raw/.converted/` with a provenance header."""
    name = _converted_name(source_id)
    clean, removed, flagged = clean_document(text)
    suspicious = bool(flagged)

    def header(numbers):
        return ["---", "source: " + _quote(origin), "source_id: " + _quote(source_id),
                "tool: " + _quote(tool, 80), "converted: %s" % (today or date.today().isoformat()),
                "suspicious: %s" % ("true" if suspicious else "false"),
                "flagged_lines: [%s]" % ", ".join(str(n) for n in numbers), "---", ""]

    offset = len(header([]))
    lines = [(number + offset, line) for number, line in flagged]
    out_dir = Path(root) / CONVERTED
    out_dir.mkdir(parents=True, exist_ok=True)
    write_atomic(out_dir / name, "\n".join(header([n for n, _ in lines])) + "\n" + clean)
    return {"path": "%s/%s" % (CONVERTED, name), "suspicious": suspicious, "removed": removed,
            "flagged": [{"line": n, "text": clean_inline(l, 200)} for n, l in lines]}


def inbox_done(root, rel, title):
    """Move an inbox item to `_inbox/_done/` without overwriting, log it, return the new rel."""
    root = Path(root).resolve()
    path = Path(rel)
    path = path if path.is_absolute() else root / path
    real = Path(os.path.realpath(str(path)))
    try:
        parts = real.relative_to(root).parts
    except ValueError:
        raise ValueError("%s is not inside the vault" % rel)
    if len(parts) < 2 or parts[0] != "_inbox" or "_done" in parts[1:-1] or parts[-1].startswith("."):
        raise ValueError("%s is not an item waiting in _inbox/" % rel)
    if not real.is_file():
        raise ValueError("no such file: %s" % rel)
    done = root / "_inbox" / "_done"
    done.mkdir(parents=True, exist_ok=True)
    target, counter = done / real.name, 2
    while target.exists():
        target = done / ("%s-%d%s" % (real.stem, counter, real.suffix))
        counter += 1
    os.rename(str(real), str(target))
    logfile.append(root, "ingest", title)
    return target.relative_to(root).as_posix()
