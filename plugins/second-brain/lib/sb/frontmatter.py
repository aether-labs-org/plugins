"""Restricted YAML-subset frontmatter parser (spec D8, section 4.2).

Accepted: `key: value` scalars, quoted scalars, `[[Wiki Link]]` scalars and inline `[a, b]`
lists. Everything else is reported as an error with its line number.
"""
import re
from typing import NamedTuple

KEY_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_-]*):(?:[ \t]+(.*))?$")
COMMENT_RE = re.compile(r"\s+#.*$")
UNSUPPORTED_START = ("|", ">", "{", "&", "*", "!")


class Parsed(NamedTuple):
    data: dict
    body: str
    errors: list      # [(line_number, message)]
    body_line: int    # 1-based line number of the first body line


def parse(text):
    text = text.lstrip("﻿").replace("\r\n", "\n")
    lines = text.split("\n")
    if lines[0].strip() != "---":
        return Parsed({}, text, [(1, "missing frontmatter")], 1)
    end = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), None)
    if end is None:
        return Parsed({}, text, [(1, "frontmatter is not closed with ---")], 1)
    data, errors = {}, []
    for number, raw in enumerate(lines[1:end], start=2):
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        match = KEY_RE.match(raw)
        if not match:
            errors.append((number, "unsupported frontmatter syntax: %r" % raw.strip()))
            continue
        key, value = match.group(1), (match.group(2) or "").strip()
        if key in data:
            errors.append((number, "duplicate key: %s" % key))
            continue
        data[key] = _value(value, number, errors)
    return Parsed(data, "\n".join(lines[end + 1:]), errors, end + 2)


def _unquote(value):
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value


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
