import io
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from sb_helpers import PLUGIN, make_vault, note
from sb.cli import main
from sb.vault import LEGACY_MARKER, LEGACY_MESSAGE, MARKER


def run(*argv):
    out, err = io.StringIO(), io.StringIO()
    code = main(list(argv), out=out, err=err)
    return code, out.getvalue(), err.getvalue()


class CliTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = make_vault(self.tmp.name, {
            "Resources/A.md": note("A", body="see [[B]] and Gamma Ray"),
            "Resources/B.md": note("B", body="see [[A]] and [[Gamma Ray]]"),
            "Resources/Gamma Ray.md": note("Gamma Ray", body="[[A]]"),
        })

    def test_outside_a_vault_exits_2_with_a_hint(self):
        empty = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, empty)
        code, _, err = run("lint", "--vault", empty)
        self.assertEqual(code, 2)
        self.assertIn("not a second-brain vault", err)

    def test_vault_is_discovered_from_the_working_directory(self):
        old = os.getcwd()
        os.chdir(self.root / "wiki" / "Resources")
        self.addCleanup(os.chdir, old)
        self.assertEqual(run("lint")[0], 0)

    def test_lint_text_and_json(self):
        (self.root / "wiki" / "Resources" / "A.md").write_text(
            note("A", summary=None, body="see [[B]] [[Nope]]"), encoding="utf-8")
        code, out, _ = run("lint", "--vault", str(self.root))
        self.assertEqual(code, 1)
        self.assertIn("SB102", out)
        code, out, _ = run("lint", "--json", "--vault", str(self.root))
        self.assertEqual(code, 1)
        self.assertTrue({"SB101", "SB102"} <= {f["code"] for f in json.loads(out)})

    def test_lint_on_malformed_marker_exits_2(self):
        (self.root / MARKER).write_text("{nope", encoding="utf-8")
        code, _, err = run("lint", "--vault", str(self.root))
        self.assertEqual(code, 2)
        self.assertIn("cannot read", err)

    def test_links_outgoing_backlinks_and_suggestions(self):
        code, out, _ = run("links", "A", "--suggest", "--json", "--vault", str(self.root))
        self.assertEqual(code, 0)
        data = json.loads(out)
        self.assertEqual([o["target"] for o in data["outgoing"]], ["B"])
        self.assertEqual(data["backlinks"], ["B", "Gamma Ray"])
        self.assertEqual([s["name"] for s in data["suggestions"]], ["Gamma Ray"])

    def test_links_accepts_a_path_and_rejects_unknown_notes(self):
        self.assertEqual(run("links", "wiki/Resources/A.md", "--vault", str(self.root))[0], 0)
        code, _, err = run("links", "Nope", "--vault", str(self.root))
        self.assertEqual(code, 2)
        self.assertIn("note not found", err)

    def test_removed_commands_are_unknown(self):
        for argv in (("index", "--check"), ("validate", "x"), ("log", "init", "x")):
            self.assertEqual(run(*argv, "--vault", str(self.root))[0], 2, argv)

    def test_legacy_vault_exits_2_with_the_migration_message(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / LEGACY_MARKER).write_text('{"schema_version": 2}', encoding="utf-8")
            before = sorted(p.name for p in root.rglob("*"))
            for argv in (("lint",), ("search", "x"), ("tree",), ("inbox", "done", "_inbox/x.md"),
                         ("source", "add", "x.md"), ("links", "A")):
                code, _, err = run(*argv, "--vault", str(root))
                self.assertEqual(code, 2, argv)
                self.assertIn(LEGACY_MESSAGE, err)
            old = os.getcwd()
            os.chdir(root)
            try:
                code, _, err = run("lint")
            finally:
                os.chdir(old)
            self.assertEqual(code, 2)
            self.assertIn(LEGACY_MESSAGE, err)
            self.assertEqual(sorted(p.name for p in root.rglob("*")), before)

    def test_init_refuses_a_legacy_vault(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / LEGACY_MARKER).write_text('{"schema_version": 2}', encoding="utf-8")
            before = sorted(p.name for p in root.rglob("*"))
            code, _, err = run("init", "--vault", str(root))
            self.assertEqual(code, 2)
            self.assertIn(LEGACY_MESSAGE, err)
            self.assertEqual(sorted(p.name for p in root.rglob("*")), before)

    def test_executable_shim_runs(self):
        shim = PLUGIN / "bin" / "sb"
        self.assertTrue(os.access(shim, os.X_OK))
        done = subprocess.run([str(shim), "lint", "--vault", str(self.root)],
                              capture_output=True, text=True)
        self.assertEqual(done.returncode, 0)
        self.assertEqual({l.split(": ")[1].split()[0] for l in done.stdout.splitlines()}, {"SB111"})

    def test_ripgrep_finds_notes_under_underscore_folders(self):
        if not shutil.which("rg"):
            self.skipTest("ripgrep not installed")
        (self.root / "_inbox" / "_done" / "x.md").write_text("hello", encoding="utf-8")
        found = subprocess.run(["rg", "--files", "_inbox"], cwd=self.root,
                               capture_output=True, text=True).stdout
        self.assertIn("_inbox/_done/x.md", found)


class EmptyVaultTests(unittest.TestCase):
    def test_fresh_empty_vault_is_clean(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = make_vault(tmp)
            self.assertEqual(run("lint", "--vault", str(root))[0], 0)


if __name__ == "__main__":
    unittest.main()
