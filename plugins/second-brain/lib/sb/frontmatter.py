"""Restricted YAML-subset frontmatter parser (spec D8, section 4.2).

Accepted: `key: value` scalars, quoted scalars, `[[Wiki Link]]` scalars, inline `[a, b]`
lists and block lists (`key:` followed by `- item` lines). Everything else is reported as an
error with its line number.
"""
import re
from typing import NamedTuple

KEY_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_-]*):(?:[ \t]+(.*))?$")
COMMENT_RE = re.compile(r"\s+#.*$")
ITEM_RE = re.compile(r"^\s*-\s+(.*)$")
UNSUPPORTED_START = ("|", ">", "{", "&", "*", "!")
# A fence line is `---` with only spaces, tabs and CR around it; a blank line is only those. Never
# str.strip(): it also strips \x1c-\x1f, \x85 and others that JS trim() treats differently
# (other readers of the frontmatter, such as Obsidian, must agree).
FENCE_RE = re.compile(r"[ \t\r]*---[ \t\r]*")
BLANK_RE = re.compile(r"[ \t\r]*")


def _fence(line):
    return FENCE_RE.fullmatch(line) is not None


class Parsed(NamedTuple):
    data: dict
    body: str
    errors: list      # [(line_number, message)]
    body_line: int    # 1-based line number of the first body line


def parse(text):
    text = text.lstrip("﻿").replace("\r\n", "\n")
    lines = text.split("\n")
    if not _fence(lines[0]):
        return Parsed({}, text, [(1, "missing frontmatter")], 1)
    end = next((i for i in range(1, len(lines)) if _fence(lines[i])), None)
    if end is None:
        return Parsed({}, text, [(1, "frontmatter is not closed with ---")], 1)
    data, errors = {}, []
    i = 1
    while i < end:
        raw, number = lines[i], i + 1
        i += 1
        if BLANK_RE.fullmatch(raw) or raw.lstrip().startswith("#"):
            continue
        match = KEY_RE.match(raw)
        if not match:
            errors.append((number, "unsupported frontmatter syntax: %r" % raw.strip()))
            continue
        key, value = match.group(1), (match.group(2) or "").strip()
        items = None
        if not value:
            items = []
            while i < end and ITEM_RE.match(lines[i]):
                items.append(_item(ITEM_RE.match(lines[i]).group(1)))
                i += 1
        if key in data:
            errors.append((number, "duplicate key: %s" % key))
            continue
        data[key] = items if items else _value(value, number, errors)
    return Parsed(data, "\n".join(lines[end + 1:]), errors, end + 2)


def _unquote(value):
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value


def _item(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return _unquote(COMMENT_RE.sub("", value).strip())


def _value(value, number, errors):
    if value[:1] in UNSUPPORTED_START:
        errors.append((number, "unsupported value syntax: %r" % value))
        return ""
    if value[:1] in ("\"", "'"):
        if len(value) >= 2 and value.endswith(value[0]):
            return value[1:-1]
        errors.append((number, "unterminated quoted value"))
        return ""
    value = COMMENT_RE.sub("", value).strip()
    if value.startswith("[[") and value.endswith("]]"):
        return value
    if value.startswith("["):
        if not value.endswith("]"):
            errors.append((number, "unterminated inline list"))
            return []
        return [_unquote(item.strip()) for item in value[1:-1].split(",") if item.strip()]
    return value


RISKY_START = "|>{[&*!'\"%@`#-?,"


def scalar(value):
    """A value the restricted parser reads back unchanged: plain when that is safe, else quoted
    (a leading indicator, a ` #` comment, or `: `). A value holding both quote kinds loses its
    double quotes."""
    text = str(value)
    if not text or (text[:1] not in RISKY_START and " #" not in text and not text.endswith(":")):
        return text
    if '"' not in text:
        return '"%s"' % text
    if "'" not in text:
        return "'%s'" % text
    return '"%s"' % text.replace('"', "'")


def set_keys(text, updates):
    """Set scalar frontmatter keys without reformatting anything else.

    The line of an existing key is replaced in place (with the block-list items under it, if
    any); new keys are appended before the closing `---`; every other line stays byte-identical,
    including line endings and a BOM. Raises ValueError when the text has no closed frontmatter."""
    bom = text[:1] if text.startswith("﻿") else ""
    lines = text[len(bom):].split("\n")
    if not _fence(lines[0]):
        raise ValueError("no frontmatter")
    end = next((i for i in range(1, len(lines)) if _fence(lines[i])), None)
    if end is None:
        raise ValueError("frontmatter is not closed with ---")
    eol = "\r" if lines[0].endswith("\r") else ""
    head, front, tail = lines[:1], lines[1:end], lines[end:]
    for key, value in updates.items():
        new = "%s: %s%s" % (key, value, eol)
        matches = [KEY_RE.match(line.rstrip("\r")) for line in front]
        index = next((i for i, m in enumerate(matches) if m and m.group(1) == key), None)
        if index is None:
            front.append(new)
            continue
        stop = index + 1
        if not (matches[index].group(2) or "").strip():
            while stop < len(front) and ITEM_RE.match(front[stop].rstrip("\r")):
                stop += 1
        front[index:stop] = [new]
    return bom + "\n".join(head + front + tail)
