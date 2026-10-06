"""File helpers."""
import os
from pathlib import Path


def write_atomic(path, text):
    """Write text to a temp file beside `path`, then rename it into place."""
    path = Path(path)
    tmp = path.with_name(".%s.tmp-%d" % (path.name, os.getpid()))
    with open(tmp, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
    os.replace(tmp, path)
