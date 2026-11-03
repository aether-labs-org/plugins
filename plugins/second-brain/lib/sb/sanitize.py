"""Text sanitising for anything a hook or CLI hands to the model."""
import re
import unicodedata

ELLIPSIS = "…"


def clean_inline(text, limit):
    """One line, no control, zero-width or bidi characters, at most `limit` characters."""
    kept = []
    for char in str(text):
        if char in "\n\r\t":
            kept.append(" ")
        elif unicodedata.category(char) in ("Cc", "Cf"):
            continue
        else:
            kept.append(char)
    out = " ".join("".join(kept).split())
    if len(out) > limit:
        out = out[:max(limit - 1, 0)].rstrip() + ELLIPSIS
    return out


TAG_RE = re.compile(r"<(/?\s*second-brain-)", re.IGNORECASE)


def escape_tags(text):
    """Break any `<second-brain-...>` or `</second-brain-...>` tag so vault text cannot open or
    close the blocks the hooks wrap around it."""
    return TAG_RE.sub(r"‹\1", str(text))


HTML_COMMENT_RE = re.compile(r"<!--.*?-->", re.DOTALL)
INJECTION_PATTERNS = [re.compile(p, re.IGNORECASE) for p in (
    r"ignore (all |any )?(previous|prior|above) instructions",
    r"disregard (the )?(previous|above)",
    r"you are now",
    r"system prompt",
    r"</?(system|assistant|user)>",
    r"\"(tool|function)_?(call|use)\"",
    r"ignore as instruções",
    r"você agora é",
)]


def clean_document(text):
    """Sanitise extracted third-party text. Returns `(clean, removed, flagged)`.

    Removes control and format characters (zero-width, bidi) except newline and tab, then
    HTML comments (multi-line). `removed` counts the characters dropped. `flagged` lists
    `(line_number, line)` of the cleaned text that match an injection pattern; those lines
    are reported, never removed.
    """
    text = str(text).replace("\r\n", "\n")
    kept, removed = [], 0
    for char in text:
        if char not in "\n\t" and unicodedata.category(char) in ("Cc", "Cf"):
            removed += 1
        else:
            kept.append(char)
    clean = HTML_COMMENT_RE.sub("", "".join(kept))
    flagged = [(number, line) for number, line in enumerate(clean.split("\n"), 1)
               if any(pattern.search(line) for pattern in INJECTION_PATTERNS)]
    return clean, removed, flagged
