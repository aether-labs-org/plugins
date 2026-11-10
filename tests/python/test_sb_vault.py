import os
import tempfile
import unittest
from pathlib import Path

from sb_helpers import make_vault, note
from sb.fsutil import write_atomic
from sb import vault
from sb.vault import (LEGACY_MARKER, MARKER, VaultError, asset_names, find_legacy_vault, find_vault,
                      load_config, load_notes, sync_mode)


class VaultTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def test_find_vault_walks_up_from_a_subfolder(self):
        root = make_vault(self.tmp.name, {"Areas/A.md": note("A")})
        deep = root / "wiki" / "Areas"
        self.assertEqual(find_vault(deep), root.resolve())

    def test_write_atomic_replaces_file_and_leaves_no_temp_files(self):
        target = Path(self.tmp.name) / "x.md"
        write_atomic(target, "one\n")
        write_atomic(target, "two\n")
        self.assertEqual(target.read_text(encoding="utf-8"), "two\n")
        self.assertEqual(os.listdir(self.tmp.name), ["x.md"])

    def test_find_vault_uses_the_agents_marker(self):
        root = Path(self.tmp.name)
        self.assertEqual(MARKER, ".agents/second-brain/config.json")
        (root / ".agents/second-brain").mkdir(parents=True)
        (root / MARKER).write_text("{}", encoding="utf-8")
        (root / "wiki/A").mkdir(parents=True)
        self.assertEqual(find_vault(root / "wiki/A"), root.resolve())
        self.assertIsNone(find_legacy_vault(root / "wiki/A"))

    def test_legacy_marker_is_found_only_as_legacy(self):
        root = Path(self.tmp.name)
        (root / LEGACY_MARKER).write_text("{}", encoding="utf-8")
        (root / "wiki").mkdir()
        self.assertIsNone(find_vault(root / "wiki"))
        self.assertEqual(find_legacy_vault(root / "wiki"), root.resolve())
        self.assertIn("schema 2", vault.LEGACY_MESSAGE)
        self.assertIn("Migrating from 0.2", vault.LEGACY_MESSAGE)

    def test_new_marker_wins_over_the_legacy_one(self):
        root = make_vault(self.tmp.name)
        (root / LEGACY_MARKER).write_text("{}", encoding="utf-8")
        self.assertEqual(find_vault(root), root.resolve())
        self.assertIsNone(find_legacy_vault(root))

    def test_asset_names_skip_the_agents_dir(self):
        root = make_vault(self.tmp.name)
        (root / ".agents/second-brain/converted").mkdir(parents=True)
        (root / ".agents/second-brain/converted/x.pdf").write_bytes(b"x")
        (root / "_assets").mkdir()
        (root / "_assets/pic.png").write_bytes(b"x")
        names = asset_names(root)
        self.assertIn("pic.png", names)
        self.assertNotIn("x.pdf", names)
        self.assertNotIn("config.json", names)

    def test_sync_mode_defaults_to_local(self):
        self.assertEqual(sync_mode({"sync": "pull"}), "pull")
        for config in ({}, {"sync": "local"}, {"sync": "squad"}, {"sync": 3}, {"sync": None}):
            self.assertEqual(sync_mode(config), "local", config)

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
        (root / MARKER).parent.mkdir(parents=True)
        (root / MARKER).write_text("{}", encoding="utf-8")
        self.assertEqual(load_notes(root), [])

    def test_load_notes_skips_underscore_dot_and_excalidraw(self):
        root = make_vault(self.tmp.name, {
            "Resources/A.md": note("A"), "Resources/_about.md": "x",
            "Resources/_assets/img.md": "x", "Resources/Sketch.excalidraw.md": "x",
            "_views/v.md": "x"})
        self.assertEqual([n.rel for n in load_notes(root)], ["wiki/Resources/A.md"])

    def test_asset_names(self):
        root = make_vault(self.tmp.name, {"Resources/A.md": note("A")})
        (root / "wiki/Resources/_assets").mkdir()
        (root / "wiki/Resources/_assets/curva.png").write_bytes(b"x")
        (root / ".obsidian").mkdir()
        (root / ".obsidian/app.json").write_text("{}")
        self.assertEqual(asset_names(root), {"curva.png"})


if __name__ == "__main__":
    unittest.main()
