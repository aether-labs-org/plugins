"""Text sanitising for anything a hook or CLI hands to the model. Milestone B adds
`clean_document`."""
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
