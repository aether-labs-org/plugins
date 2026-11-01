"""Deterministic lint rules SB101-SB112 (spec sections 5 and 7.1)."""
import re
from collections import defaultdict
from dataclasses import asdict, dataclass
from datetime import date

from . import index as index_mod
from . import tree
from .links import extract, is_asset, target_name
from .review import body_hash, split_trailing_agent_blocks, trailing_blocks_line
from .vault import SCHEMA_VERSION, asset_names, load_notes

REQUIRED = ("title", "summary", "type", "status", "origin", "created")
ENUMS = {
    "type": {"nota", "fonte", "projeto", "conceito"},
    "status": {"seed", "draft", "evergreen"},
    "origin": {"agent", "human", "mixed"},
}
INFO_CODES = {"SB111", "SB112"}
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


def _review_findings(note):
    """SB110 (reviewed text changed since review) and SB112 (agent blocks waiting), spec 7.1.
    A note reviewed by hand without `reviewed_hash` never gets SB110."""
    origin = str(note.data.get("origin") or "").strip().lower()
    reviewed = str(note.data.get("reviewed") or "").strip()
    stored = str(note.data.get("reviewed_hash") or "").strip()
    if origin in ("agent", "mixed") and not reviewed:
        return []                                  # unreviewed: SB106 covers it
    out = []
    if stored and stored != body_hash(note.body):
        out.append(Finding("SB110", note.rel, 1,
                           'reviewed text changed since %s; review again (Obsidian: "Mark as '
                           'reviewed", or sb review)' % (reviewed or "its review")))
    first = trailing_blocks_line(note.body)
    if first is not None:
        count = len(split_trailing_agent_blocks(note.body)[1])
        out.append(Finding("SB112", note.rel, note.body_line + first,
                           "%d agent block(s) waiting for review" % count))
    return out


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
    assets = asset_names(root)
    inbound = defaultdict(set)

    for note in notes:
        findings += check_note(note)
        for line, target in extract(note.body, note.body_line):
            if target not in known and is_asset(target):
                if target not in assets:
                    findings.append(Finding("SB101", note.rel, line, "broken link: [[%s]]" % target))
            elif target not in known:
                findings.append(Finding("SB101", note.rel, line, "broken link: [[%s]]" % target))
            elif target != note.name:
                inbound[target].add(note.name)
        if note.data.get("origin") == "agent" and not note.data.get("reviewed"):
            findings.append(Finding("SB106", note.rel, 1,
                                    "agent-written note has no `reviewed` date"))
        findings += _source_finding(root, note, known)
        findings += _review_findings(note)

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
    for _, folder in tree.flatten(tree.load(root)):
        if not (root / "wiki" / folder["path"] / "_about.md").is_file():
            findings.append(Finding("SB111", "wiki/%s" % folder["path"], 1,
                                    "folder has no _about.md"))
    try:
        version = int(config.get("schema_version", 0))
    except (TypeError, ValueError):
        version = 0
    if version < SCHEMA_VERSION:
        findings.append(Finding("SB107", ".second-brain.json", 1,
                                "schema_version %s is older than %d; run sb init --upgrade"
                                % (version, SCHEMA_VERSION)))
    return sorted(findings, key=lambda f: (f.path, f.line, f.code))


AGGREGATE_OVER = 20


def render_text(findings, verbose=False):
    """One line per finding; codes with more than AGGREGATE_OVER findings collapse to one line."""
    groups = defaultdict(list)
    for finding in findings:
        groups[finding.code].append(finding)
    lines, summaries = [], []
    for code in sorted(groups):
        group = groups[code]
        if verbose or len(group) <= AGGREGATE_OVER:
            continue
        messages = {f.message for f in group}
        if len(messages) == 1:
            summaries.append("%s %s: %d notes (run with --verbose)" % (code, group[0].message, len(group)))
        else:
            summaries.append("%s %s: %d findings (run with --verbose)"
                             % (code, group[0].message.split(":")[0], len(group)))
    for finding in findings:
        if verbose or len(groups[finding.code]) <= AGGREGATE_OVER:
            lines.append(str(finding))
    return "\n".join(lines + summaries)
