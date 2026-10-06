"""Wikilink extraction. Links inside fenced code and inline code are ignored (spec 4.3)."""
import re

WIKILINK = re.compile(r"\[\[([^\[\]|#\n]+)(?:#[^\[\]|\n]*)?(?:\|[^\[\]\n]*)?\]\]")
INLINE_CODE = re.compile(r"`[^`\n]*`")


def target_name(raw):
    """`wiki/Resources/Foo.md` / `Foo.md` / `Foo` -> `Foo`."""
    name = raw.strip().rsplit("/", 1)[-1]
    return name[:-3] if name.endswith(".md") else name


def prose_lines(body, first_line=1):
    """Yield (line_number, text) for lines outside fenced code, with inline code removed."""
    fence = None
    for number, line in enumerate(body.split("\n"), start=first_line):
        stripped = line.lstrip()
        if fence:
            if stripped.startswith(fence):
                fence = None
            continue
        if stripped.startswith(("```", "~~~")):
            fence = stripped[:3]
            continue
        yield number, INLINE_CODE.sub("", line)


def extract(body, first_line=1):
    """Return [(line_number, target_name)] for every wikilink in prose."""
    found = []
    for number, line in prose_lines(body, first_line):
        for match in WIKILINK.finditer(line):
            found.append((number, target_name(match.group(1))))
    return found
