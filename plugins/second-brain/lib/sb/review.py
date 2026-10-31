"""Review hash (spec 7.1): what a human review covers and its fingerprint.

The shared vectors in tests/fixtures/review-hash/vectors.json are the contract with the
second-brain-companion Obsidian plugin (src/hash.ts, src/blocks.ts); change both together.
"""
import hashlib
import re

from .frontmatter import parse

AGENT_HEADER_RE = re.compile(r"^> \[!agent\]", re.IGNORECASE)
TRAILING_BLANK_RE = re.compile(r"[ \t]+$")      # spaces and tabs only, not str.rstrip()


def _blank(line):
    return line.strip() == ""


def _first_trailing_header(lines):
    """Index of the header that starts the trailing agent blocks of `lines`, or None. Walk back
    from the end over blank or `>` lines; the first `^> [!agent]` header (any case) in that
    region starts the stripped part."""
    start = len(lines)
    while start > 0 and (_blank(lines[start - 1]) or lines[start - 1].startswith(">")):
        start -= 1
    return next((i for i in range(start, len(lines)) if AGENT_HEADER_RE.match(lines[i])), None)


def trailing_blocks_line(body):
    """0-based line of the first trailing agent block in `body`, or None."""
    return _first_trailing_header(body.split("\n"))


def split_trailing_agent_blocks(body):
    """`(kept, blocks)`: trailing `> [!agent]` callouts split off a body (LF line endings).

    `kept` is everything before the first trailing header (a plain `>` quote earlier in the
    region stays); each block keeps its header, trailing blank lines removed."""
    lines = body.split("\n")
    first = _first_trailing_header(lines)
    if first is None:
        return body, []
    blocks = []
    for line in lines[first:]:
        if AGENT_HEADER_RE.match(line):
            blocks.append([line])
        else:
            blocks[-1].append(line)
    for block in blocks:
        while len(block) > 1 and _blank(block[-1]):
            block.pop()
    return "\n".join(lines[:first]), ["\n".join(block) for block in blocks]


def review_text(body):
    """The text a review covers, from a parsed body (`frontmatter.parse(...).body`): minus
    trailing agent callouts, trailing spaces and tabs removed per line, leading and trailing blank
    lines removed. No Unicode normalisation."""
    kept, _ = split_trailing_agent_blocks(body)
    lines = [TRAILING_BLANK_RE.sub("", line) for line in kept.split("\n")]
    start, end = 0, len(lines)
    while start < end and lines[start] == "":
        start += 1
    while end > start and lines[end - 1] == "":
        end -= 1
    return "\n".join(lines[start:end])


def review_body(text):
    """`review_text` of a whole file: the body after the frontmatter (BOM stripped, CRLF to LF)."""
    return review_text(parse(text).body)


def body_hash(body):
    """`sha256:` plus the first 16 lowercase hex digits of SHA-256 over the UTF-8 review text of
    a parsed body."""
    return "sha256:" + hashlib.sha256(review_text(body).encode("utf-8")).hexdigest()[:16]


def review_hash(text):
    """`body_hash` of a whole file."""
    return body_hash(parse(text).body)
