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
