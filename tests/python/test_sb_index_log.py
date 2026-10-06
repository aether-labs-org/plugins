import os
import tempfile
import unittest
from pathlib import Path

from sb_helpers import make_vault, note
from sb import index, logfile
from sb.fsutil import write_atomic
from sb.vault import load_notes


class IndexTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def test_build_is_sorted_casefolded_and_flags_missing_summary(self):
        root = make_vault(self.tmp.name, {
            "Resources/b.md": note("b", summary="Second."),
            "Resources/A.md": note("A", summary="First."),
            "Resources/C.md": note("C", summary=None),
        }, index=False)
        text = index.build(load_notes(root))
        self.assertTrue(text.startswith(index.HEADER))
        self.assertEqual(text[len(index.HEADER):].splitlines(),
                         ["- [[A]]: First.", "- [[b]]: Second.", "- [[C]]: (no summary)"])

    def test_build_is_deterministic(self):
        root = make_vault(self.tmp.name, {"R/A.md": note("A"), "R/B.md": note("B")})
        notes = load_notes(root)
        self.assertEqual(index.build(notes), index.build(list(reversed(notes))))

    def test_drift_is_empty_when_synced_and_a_diff_otherwise(self):
        root = make_vault(self.tmp.name, {"R/A.md": note("A")})
        self.assertEqual(index.drift(root, load_notes(root)), "")
        (root / "wiki" / "R" / "B.md").write_text(note("B"), encoding="utf-8")
        diff = index.drift(root, load_notes(root))
        self.assertIn("+- [[B]]: A summary.", diff)

    def test_missing_index_file_counts_as_drift(self):
        root = make_vault(self.tmp.name, {"R/A.md": note("A")}, index=False)
        self.assertNotEqual(index.drift(root, load_notes(root)), "")

    def test_write_atomic_replaces_file_and_leaves_no_temp_files(self):
        target = Path(self.tmp.name) / "x.md"
        write_atomic(target, "one\n")
        write_atomic(target, "two\n")
        self.assertEqual(target.read_text(encoding="utf-8"), "two\n")
        self.assertEqual(os.listdir(self.tmp.name), ["x.md"])


class LogTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def test_append_format_and_preserves_history(self):
        logfile.append(self.root, "ingest", "First  note", today="2026-09-30")
        logfile.append(self.root, "update", "Second", today="2026-10-01")
        self.assertEqual((self.root / "_log.md").read_text(encoding="utf-8"),
                         "## [2026-09-30] ingest | First note\n"
                         "## [2026-10-01] update | Second\n")

    def test_append_adds_missing_trailing_newline(self):
        (self.root / "_log.md").write_text("## [2026-01-01] init | x", encoding="utf-8")
        logfile.append(self.root, "link", "y", today="2026-01-02")
        self.assertEqual((self.root / "_log.md").read_text(encoding="utf-8").count("\n"), 2)

    def test_unknown_event_is_rejected(self):
        with self.assertRaises(ValueError):
            logfile.append(self.root, "delete", "x")


if __name__ == "__main__":
    unittest.main()
