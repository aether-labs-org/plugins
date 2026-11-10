"""Provenance for ingest (spec 5.3, D47, D55): where a source lives, which notes were made from it,
sanitised converted copies under `.agents/second-brain/converted/`, relinking after a move, and
the inbox move. A source outside the vault is never copied in."""
import hashlib
import json
import os
import re
import unicodedata
from datetime import date, datetime
from pathlib import Path
from urllib.parse import urlsplit

from . import frontmatter
from .frontmatter import parse
from .fsutil import write_atomic
from .sanitize import clean_document, clean_inline
from .vault import CONVERTED_DIR, load_notes

CONVERTED = CONVERTED_DIR
DEFAULT_PORTS = {"http": "80", "https": "443"}
HASH_NAME_RE = re.compile(r"^sha256-([0-9a-f]{16})\.md$")
CALLOUT_RE = re.compile(r"^>[ \t]*\[!agent\][^\n]*·[ \t]*(.+?)[ \t]*$", re.IGNORECASE | re.MULTILINE)
TEXT_SUFFIXES = (".md", ".txt")
HEADER_LINES = 40


def _norm(value):
    if isinstance(value, (list, tuple)):
        return ",".join(str(v).strip() for v in value)
    return str(value if value is not None else "").strip()


def _sha16(data):
    return hashlib.sha256(data).hexdigest()[:16]


def content_hash(data):
    """`sha256:` and the first 16 hex digits of the hash of the bytes."""
    return "sha256:" + _sha16(data)


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


def _check_chars(value):
    """A source is one line of plain text: no control or format character (newline, CR, ESC,
    zero-width...), or it could forge a frontmatter key or a callout header."""
    for char in str(value):
        if unicodedata.category(char) in ("Cc", "Cf"):
            raise ValueError("a source may not contain control characters (found %r)" % char)
    return value


def _is_url(target):
    return re.match(r"^https?://", str(target).strip(), re.IGNORECASE) is not None


def _resolve(root, target):
    path = Path(os.path.expanduser(str(target)))
    for candidate in ((path,) if path.is_absolute() else (Path(root) / path, path)):
        if candidate.is_file():
            return candidate
    raise ValueError("no such file: %s" % target)


def _normalize(value):
    """The form in which two citations of the same source compare equal."""
    value = _norm(value)
    if _is_url(value):
        return canonical_url(value)
    if value.startswith("url:") and _is_url(value[4:]):
        return "url:" + canonical_url(value[4:])
    return value


def _clip_url(path):
    """The http(s) `url` (or `source`) of a Markdown clip, or ''."""
    if path.suffix != ".md":
        return ""
    fields = parse(path.read_bytes().decode("utf-8", "replace")).data
    for key in ("url", "source"):
        value = _norm(fields.get(key))
        if _is_url(value):
            return value
    return ""


def _same_bytes(path, data):
    try:
        return path.read_bytes() == data
    except OSError:
        return False


def done_name(root, path):
    """The file name an `_inbox/` item gets in `_inbox/_done/`: `<stem>-<mtime as YYYYMMDD-HHMMSS><ext>`,
    so items that share a name stay apart; if that is taken by other bytes, `-2`, `-3`... follow.
    Deterministic, so the `source:` recorded before the move is the path the move produces. A name
    that is free or already holds the same bytes is taken."""
    path = Path(path)
    done = Path(root) / "_inbox" / "_done"
    data = path.read_bytes()
    base = "%s-%s" % (path.stem, datetime.fromtimestamp(path.stat().st_mtime).strftime("%Y%m%d-%H%M%S"))
    counter = 1
    while True:
        name = "%s%s" % (base if counter == 1 else "%s-%d" % (base, counter), path.suffix)
        if not (done / name).exists() or _same_bytes(done / name, data):
            return name
        counter += 1


def _locate(root, path):
    """`(source value, kind)` for an existing file."""
    resolved = path.resolve()
    try:
        rel = resolved.relative_to(Path(root).resolve())
    except ValueError:
        rel = None
    if rel is not None:
        if rel.parts[:1] == ("_inbox",):
            url = _clip_url(path)
            if url:
                return canonical_url(url), "inbox"
            if rel.parts[1:2] == ("_done",):
                return rel.as_posix(), "inbox"
            return "_inbox/_done/" + done_name(root, path), "inbox"
        return rel.as_posix(), "file"
    try:
        return "~/" + resolved.relative_to(Path.home().resolve()).as_posix(), "file"
    except ValueError:
        return str(resolved), "file"


def source_value(root, target):
    """The exact value for a note's `source:` field (spec 5.3)."""
    _check_chars(target)
    if _is_url(target):
        return canonical_url(target)
    return _check_chars(_locate(root, _resolve(root, target))[0])


def _converted_dir(root):
    return Path(root) / CONVERTED


def _read_header(path):
    """Header keys of a converted copy, reading only its first lines."""
    lines = []
    try:
        with open(str(path), encoding="utf-8", errors="replace") as handle:
            for _ in range(HEADER_LINES):
                line = handle.readline()
                if not line:
                    break
                lines.append(line.rstrip("\n"))
                if len(lines) > 1 and lines[-1].strip() == "---":
                    break
    except OSError:
        return {}
    if not lines or lines[0].strip() != "---":
        return {}
    data = {}
    for line in lines[1:]:
        key, sep, value = line.partition(":")
        if not sep:
            continue
        value = value.strip()
        if value[:1] == '"':
            try:
                value = json.loads(value)
            except ValueError:
                value = value.strip('"')
        data[key.strip()] = value
    return data


def _copies(root):
    """Converted copies as `{path, rel, hash, source}` (hash is '' for pages)."""
    found = []
    folder = _converted_dir(root)
    try:
        names = sorted(os.listdir(str(folder)))
    except OSError:
        return found
    for name in names:
        if not name.endswith(".md"):
            continue
        header = _read_header(folder / name)
        digest = _norm(header.get("content_hash"))
        match = HASH_NAME_RE.match(name)
        if not digest and match:
            digest = "sha256:" + match.group(1)
        found.append({"name": name, "rel": "%s/%s" % (CONVERTED, name), "hash": digest,
                      "source": _normalize(header.get("source"))})
    return found


def _citations(note):
    """`(source, legacy source_id, callout header values)` of a note, normalised."""
    source = _normalize(note.data.get("source"))
    legacy = _normalize(note.data.get("source_id"))
    callouts = {_normalize(m.group(1)) for m in CALLOUT_RE.finditer(note.body)}
    return source, legacy, callouts


def _identity(root, target):
    """What names the source: `(path or None, value, kind, hash or '', legacy id)`."""
    _check_chars(target)
    if _is_url(target):
        value = canonical_url(target)
        return None, value, "url", "", "url:" + value
    path = _resolve(root, target)
    value, kind = _locate(root, path)
    _check_chars(value)
    if kind == "inbox" and _is_url(value):
        return path, value, kind, "", "url:" + canonical_url(value)
    digest = content_hash(path.read_bytes())
    return path, value, kind, digest, digest


def _exists(root, value):
    """Does the path a note cites still exist? (`~/` expands, absolute as is, else in the vault.)"""
    value = str(value)
    path = Path(value).expanduser() if value.startswith("~/") else Path(value)
    return (path if path.is_absolute() else Path(root) / path).exists()


def _page_name(value):
    return "url-%s.md" % _sha16(canonical_url(value).encode("utf-8"))


def inspect(root, target):
    """Everything `ingest` needs to know about a source before it reads it."""
    path, value, kind, digest, legacy = _identity(root, target)
    wanted = _normalize(value)
    copies = _copies(root)
    direct, moved, via_source = set(), {}, set()
    same_hash = [c for c in copies if digest and c["hash"] == digest]
    recorded = {c["source"] for c in same_hash if c["source"] and c["source"] != wanted}
    for note in load_notes(root):
        source, legacy_id, callouts = _citations(note)
        cited = {source} | callouts
        if wanted in cited:
            direct.add(note.rel)
            via_source.add(note.rel)
        elif legacy in cited or (legacy_id == legacy and source in ("", wanted)):
            direct.add(note.rel)
        elif digest and legacy_id == legacy:
            moved[note.rel] = source
        elif digest and cited & recorded:
            moved[note.rel] = sorted(cited & recorded)[0]
    info = {"source": value, "kind": kind, "status": "new", "notes": sorted(direct | set(moved)),
            "converted": None}
    if info["notes"]:
        info["status"] = "seen"
    name = _page_name(value) if not digest else "%s.md" % digest.replace(":", "-")
    info["converted"] = next((c["rel"] for c in copies if c["name"] == name), None)
    gone = sorted(v for v in set(moved.values()) if v and not _exists(root, v))
    if digest and moved and not direct and gone:
        info["moved_from"] = gone[0]
        info["converted"] = info["converted"] or (same_hash[0]["rel"] if same_hash else None)
    if digest and via_source:
        mine = [c for c in copies if c["source"] == wanted and c["hash"]]
        if mine and not any(c["hash"] == digest for c in mine):
            info["changed"] = True
    return info


def _quote(value, limit=500):
    return json.dumps(clean_inline(value, limit), ensure_ascii=False)


def save(root, target, text, tool, today=None):
    """Write the sanitised extraction to the converted folder with a provenance header."""
    path, value, kind, digest, _ = _identity(root, target)
    name = _page_name(value) if not digest else "%s.md" % digest.replace(":", "-")
    clean, removed, flagged = clean_document(text)
    suspicious = bool(flagged)

    def header(numbers):
        lines = ["---", "source: " + _quote(value)]
        if digest:
            lines.append("content_hash: " + _quote(digest))
        lines += ["tool: " + _quote(tool, 80), "converted: %s" % (today or date.today().isoformat()),
                  "suspicious: %s" % ("true" if suspicious else "false"),
                  "flagged_lines: [%s]" % ", ".join(str(n) for n in numbers), "---", ""]
        return lines

    offset = len(header([]))
    lines = [(number + offset, line) for number, line in flagged]
    out_dir = _converted_dir(root)
    out_dir.mkdir(parents=True, exist_ok=True)
    write_atomic(out_dir / name, "\n".join(header([n for n, _ in lines])) + "\n" + clean)
    return {"path": "%s/%s" % (CONVERTED, name), "suspicious": suspicious, "removed": removed,
            "flagged": [{"line": n, "text": clean_inline(l, 200)} for n, l in lines]}


def save_text_file(root, target, today=None):
    """Sanitise a `.md` or `.txt` source in place of an extraction (tool `none`)."""
    path = _resolve(root, target)
    return save(root, target, path.read_bytes().decode("utf-8", "replace"), "none", today=today)


def is_text_file(root, target):
    return not _is_url(target) and _resolve(root, target).suffix.lower() in TEXT_SUFFIXES


def _replace_header_source(path, old, new):
    lines = _read_text(path).split("\n")
    for i, line in enumerate(lines[1:HEADER_LINES], 1):
        if line.strip() == "---":
            break
        if line.startswith("source:") and _normalize(_read_header_line(line.rstrip("\r"))) == old:
            lines[i] = "source: " + _quote(new) + ("\r" if line.endswith("\r") else "")
            break
    write_atomic(path, "\n".join(lines))


def _read_text(path):
    """A file's text with its line endings untouched (no universal-newline translation)."""
    with open(str(path), encoding="utf-8", newline="") as handle:
        return handle.read()


def _read_header_line(line):
    value = line.partition(":")[2].strip()
    if value[:1] == '"':
        try:
            return json.loads(value)
        except ValueError:
            return value.strip('"')
    return value


def relink(root, target):
    """Point the converted copy, the notes and the callout headers at the current path."""
    info = inspect(root, target)
    old = info.get("moved_from")
    if not old:
        raise ValueError("nothing to relink: %s was not moved" % info["source"])
    new = info["source"]
    written = frontmatter.scalar(new)
    if frontmatter.parse("---\nsource: %s\n---\n" % written).data.get("source") != new:
        raise ValueError("cannot write this source into frontmatter safely: %s" % new)
    path, _, _, digest, legacy = _identity(root, target)
    old_n = _normalize(old)
    for copy in _copies(root):
        if copy["hash"] == digest and copy["source"] == old_n:
            _replace_header_source(Path(root) / copy["rel"], old_n, new)
    changed = []
    header = re.compile(r"^(>[ \t]*\[!agent\][^\n]*·[ \t]*)%s([ \t\r]*)$" % re.escape(old),
                        re.IGNORECASE | re.MULTILINE)
    for note in load_notes(root):
        source, legacy_id, callouts = _citations(note)
        text = _read_text(note.path)
        updated = text
        if source == old_n:
            updated = frontmatter.set_keys(updated, {"source": written})
        updated = header.sub(lambda m: m.group(1) + new + m.group(2), updated)
        if updated != text:
            write_atomic(note.path, updated)
            changed.append(note.rel)
    return {"source": new, "moved_from": old, "converted": info["converted"],
            "changed": sorted(changed)}


def inbox_done(root, rel):
    """Move an inbox item to `_inbox/_done/` under a timestamped name, without overwriting; return the new rel."""
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
    target = done / done_name(root, real)
    os.rename(str(real), str(target))
    return target.relative_to(root).as_posix()
