"""Trust label of a note (spec 5.3) and the guard tiers (spec 5.4, D11)."""
import re
from collections import Counter

from .frontmatter import parse

AGENT_BLOCK_RE = re.compile(r"^>[ \t]*\[!agent\]", re.IGNORECASE | re.MULTILINE)


def label(data, body):
    """`unreviewed` | `has-agent-blocks` | `reviewed`. A missing `origin` means human."""
    origin = str(data.get("origin") or "").strip().lower()
    reviewed = str(data.get("reviewed") or "").strip()
    if origin in ("agent", "mixed") and not reviewed:
        return "unreviewed"
    if AGENT_BLOCK_RE.search(body or ""):
        return "has-agent-blocks"
    return "reviewed"


# --- Guard tiers and change classification (spec 5.4, D11, D12, D27) -------------------------

TRUST_FIELDS = ("reviewed", "reviewed_hash", "protected", "origin")
WIKILINK_RE = re.compile(r"\[\[([^\[\]\n]*)\]\]")


def norm(value):
    if isinstance(value, (list, tuple)):
        return ",".join(str(v).strip() for v in value)
    return str(value if value is not None else "").strip()


def tier(data, folder_protected=False):
    """`T0` agent note not yet reviewed, `T1` human or reviewed, `T2` protected (D11)."""
    protected = norm(data.get("protected")).lower() in ("true", "yes", "1")
    if folder_protected or protected or norm(data.get("status")).lower() == "evergreen":
        return "T2"
    origin = norm(data.get("origin")).lower()
    if origin != "agent" or norm(data.get("reviewed")):
        return "T1"
    return "T0"


def trust_fields_changed(old, new):
    """Names of trust fields whose normalised value differs (missing equals empty)."""
    return [f for f in TRUST_FIELDS if norm(old.get(f)) != norm(new.get(f))]


def _frontmatter_lines(text):
    """Raw frontmatter lines (CRLF and BOM normalised, trailing blanks trimmed)."""
    lines = text.lstrip("﻿").replace("\r\n", "\n").split("\n")
    if not lines or lines[0].strip() != "---":
        return []
    end = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), len(lines))
    return [line.rstrip() for line in lines[1:end]]


def trust_fields_changed_text(old_text, new_text):
    """Like `trust_fields_changed` on whole files, and also catches duplicate or
    unparseable occurrences of a trust key that the parser would drop."""
    changed = set(trust_fields_changed(parse(old_text).data, parse(new_text).data))
    old_lines, new_lines = _frontmatter_lines(old_text), _frontmatter_lines(new_text)
    for field in TRUST_FIELDS:
        prefix = field + ":"
        if [l.strip() for l in old_lines if l.strip().startswith(prefix)] != \
                [l.strip() for l in new_lines if l.strip().startswith(prefix)]:
            changed.add(field)
    return [f for f in TRUST_FIELDS if f in changed]


def trust_key_lines(text):
    """Raw frontmatter lines of each trust field, stripped, in file order."""
    lines = [l.strip() for l in _frontmatter_lines(text)]
    return {f: [l for l in lines if l.startswith(f + ":")] for f in TRUST_FIELDS}


def _same_frontmatter(old_text, new_text, ignore_updated=True):
    def keep(lines):
        return [l for l in lines if not (ignore_updated and l.startswith("updated:"))]
    return keep(_frontmatter_lines(old_text)) == keep(_frontmatter_lines(new_text))


def append_only(old_text, new_text):
    """True when `new_text` only adds trailing `> [!agent]` callouts to `old_text`."""
    if not _same_frontmatter(old_text, new_text):
        return False
    old_body, new_body = parse(old_text).body.rstrip(), parse(new_text).body
    if not new_body.startswith(old_body):
        return False
    rest = new_body[len(old_body):]
    if old_body and not re.match(r"[ \t]*\n", rest):
        return False                      # text glued to the last reviewed line
    lines = [line for line in rest.split("\n") if line.strip()]
    if not lines or not AGENT_BLOCK_RE.match(lines[0]):
        return False
    return all(line.startswith(">") for line in lines)


def _display(match):
    inner = match.group(1)
    return inner.split("|", 1)[1] if "|" in inner else inner


def link_only(old_text, new_text):
    """True when the only change is wikilink markup added around existing text (D27)."""
    if not _same_frontmatter(old_text, new_text):
        return False
    old_body, new_body = parse(old_text).body, parse(new_text).body
    if old_body == new_body:
        return False
    kept = Counter(m.group(0) for m in WIKILINK_RE.finditer(old_body))

    def unwrap_added(match):
        if kept[match.group(0)] > 0:
            kept[match.group(0)] -= 1     # a link that was already there stays as is
            return match.group(0)
        return _display(match)

    return WIKILINK_RE.sub(unwrap_added, new_body) == old_body
