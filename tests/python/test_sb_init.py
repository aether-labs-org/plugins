import json
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import sb_helpers  # noqa: F401
from sb import init
from sb.lint import lint
from sb.vault import MARKER, load_config


class InitTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / "vault"

    def test_creates_layout_marker_and_a_clean_vault(self):
        result = init.run(self.root, language="pt-BR", areas=["Saúde", "Finanças"])
        self.assertEqual(result["status"], "created")
        for rel in ("_inbox/_done", "_raw", "wiki/Projects", "wiki/Areas/Saúde",
                    "wiki/Areas/Finanças", "wiki/Resources", "wiki/Archive"):
            self.assertTrue((self.root / rel).is_dir(), rel)
        for rel in ("CLAUDE.md", "_index.md", "_log.md", ".gitignore", MARKER):
            self.assertTrue((self.root / rel).is_file(), rel)
        self.assertEqual(load_config(self.root),
                         {"schema_version": 1, "language": "pt-BR", "areas": ["Saúde", "Finanças"]})
        self.assertIn("pt-BR", (self.root / "CLAUDE.md").read_text(encoding="utf-8"))
        self.assertIn("init | vault created", (self.root / "_log.md").read_text(encoding="utf-8"))
        self.assertEqual(lint(self.root, load_config(self.root)), [])

    def test_vault_claude_md_is_under_200_lines(self):
        init.run(self.root)
        self.assertLess(len((self.root / "CLAUDE.md").read_text(encoding="utf-8").splitlines()), 200)

    def test_is_idempotent_and_never_touches_an_existing_marker_vault(self):
        init.run(self.root, language="en")
        (self.root / "CLAUDE.md").write_text("mine", encoding="utf-8")
        again = init.run(self.root, language="pt-BR")
        self.assertEqual(again["status"], "exists")
        self.assertEqual((self.root / "CLAUDE.md").read_text(encoding="utf-8"), "mine")
        self.assertEqual(load_config(self.root)["language"], "en")

    def test_never_overwrites_an_existing_claude_md(self):
        self.root.mkdir()
        (self.root / "CLAUDE.md").write_text("mine", encoding="utf-8")
        result = init.run(self.root)
        self.assertIn("CLAUDE.md", result["kept"])
        self.assertEqual((self.root / "CLAUDE.md").read_text(encoding="utf-8"), "mine")

    def test_gitignore_lines_are_appended_once(self):
        self.root.mkdir()
        (self.root / ".gitignore").write_text("node_modules/\n", encoding="utf-8")
        init.run(self.root)
        text = (self.root / ".gitignore").read_text(encoding="utf-8")
        self.assertEqual(text.splitlines(), ["node_modules/", ".obsidian/workspace*", ".smart-env/"])

    def test_invalid_area_names_are_skipped_with_a_warning(self):
        result = init.run(self.root, areas=["ok", "../escape", ".hidden", "a/b", "  "])
        self.assertEqual(load_config(self.root)["areas"], ["ok"])
        self.assertEqual(len(result["warnings"]), 3)
        self.assertFalse((Path(self.tmp.name) / "escape").exists())

    def test_marker_is_written_last(self):
        calls = []
        real = init.write_atomic

        def spy(path, text):
            calls.append(Path(path).name)
            real(path, text)

        with mock.patch.object(init, "write_atomic", spy):
            init.run(self.root)
        self.assertEqual(calls[-1], MARKER)
        self.assertLess(calls.index("CLAUDE.md"), calls.index(MARKER))

    @unittest.skipUnless(shutil.which("git"), "git not installed")
    def test_git_flag_runs_git_init(self):
        init.run(self.root, git=True)
        self.assertTrue((self.root / ".git").exists())


if __name__ == "__main__":
    unittest.main()
