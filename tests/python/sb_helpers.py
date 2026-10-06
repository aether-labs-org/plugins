"""Shared helpers for the second-brain tests. Importing this puts lib/ on sys.path."""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLUGIN = ROOT / "plugins" / "second-brain"
sys.path.insert(0, str(PLUGIN / "lib"))


def note(title, summary="A summary.", body="", origin="human", status="draft",
         type="nota", created="2026-09-30", source="", reviewed=None):
    """Return the text of a valid note. Pass summary=None / created=None to omit the key."""
    lines = ["---", "title: %s" % title]
    if summary is not None:
        lines.append("summary: %s" % summary)
    lines += ["type: %s" % type, "status: %s" % status, "origin: %s" % origin]
    if created is not None:
        lines.append("created: %s" % created)
    lines.append("source: %s" % source)
    if reviewed:
        lines.append("reviewed: %s" % reviewed)
    lines += ["---", body, ""]
    return "\n".join(lines)


def make_vault(tmp, notes=None, config=None, index=True):
    """Build a vault under tmp. `notes` maps a path under wiki/ to the file text."""
    from sb import index as index_mod
    from sb.vault import load_notes

    root = Path(tmp)
    cfg = {"schema_version": 1, "language": "en", "areas": []}
    cfg.update(config or {})
    (root / ".second-brain.json").write_text(json.dumps(cfg), encoding="utf-8")
    for rel in ("_inbox/_done", "_raw", "wiki"):
        (root / rel).mkdir(parents=True, exist_ok=True)
    (root / "_log.md").write_text("", encoding="utf-8")
    for rel, text in (notes or {}).items():
        path = root / "wiki" / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    if index:
        (root / "_index.md").write_text(index_mod.build(load_notes(root)), encoding="utf-8")
    return root
