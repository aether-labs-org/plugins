import tempfile
import unittest
from pathlib import Path

from sb_helpers import make_vault, note
from sb.vault import MARKER, VaultError, find_vault, load_config, load_notes


class VaultTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def test_find_vault_walks_up_from_a_subfolder(self):
        root = make_vault(self.tmp.name, {"Areas/A.md": note("A")})
        deep = root / "wiki" / "Areas"
        self.assertEqual(find_vault(deep), root.resolve())

    def test_find_vault_returns_none_outside_a_vault(self):
        self.assertIsNone(find_vault(self.tmp.name))

    def test_load_config_rejects_malformed_json(self):
        root = make_vault(self.tmp.name)
        (root / MARKER).write_text("{not json", encoding="utf-8")
        with self.assertRaises(VaultError):
            load_config(root)

    def test_load_notes_skips_dot_folders_and_reports_unreadable_files(self):
        root = make_vault(self.tmp.name, {"Resources/A.md": note("A")})
        (root / "wiki" / ".obsidian").mkdir()
        (root / "wiki" / ".obsidian" / "x.md").write_text("junk", encoding="utf-8")
        (root / "wiki" / "Resources" / "Bin.md").write_bytes(b"\xff\xfe\x00bad")
        notes = {n.name: n for n in load_notes(root)}
        self.assertEqual(sorted(notes), ["A", "Bin"])
        self.assertIn("unreadable", notes["Bin"].errors[0][1])
        self.assertEqual(notes["A"].rel, "wiki/Resources/A.md")

    def test_load_notes_on_a_vault_without_wiki_dir(self):
        root = Path(self.tmp.name)
        (root / MARKER).write_text("{}", encoding="utf-8")
        self.assertEqual(load_notes(root), [])


if __name__ == "__main__":
    unittest.main()
