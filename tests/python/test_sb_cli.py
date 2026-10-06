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

    def test_index_write_then_check(self):
        (self.root / "_index.md").write_text("stale", encoding="utf-8")
        self.assertEqual(run("index", "--check", "--vault", str(self.root))[0], 1)
        self.assertEqual(run("index", "--write", "--vault", str(self.root))[0], 0)
        code, out, _ = run("index", "--check", "--json", "--vault", str(self.root))
        self.assertEqual((code, json.loads(out)["in_sync"]), (0, True))

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
        (self.root / ".second-brain.json").write_text("{nope", encoding="utf-8")
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

    def test_validate_checks_wiki_notes_only(self):
        bad = self.root / "wiki" / "Resources" / "Bad.md"
        bad.write_text(note("Bad", summary=None), encoding="utf-8")
        outside = self.root / "_inbox" / "x.md"
        outside.write_text("no frontmatter", encoding="utf-8")
        self.assertEqual(run("validate", str(bad), "--vault", str(self.root))[0], 1)
        self.assertEqual(run("validate", str(outside), "--vault", str(self.root))[0], 0)
        self.assertEqual(run("validate", str(self.root / "wiki" / "Resources" / "A.md"),
                             "--vault", str(self.root))[0], 0)

    def test_log_appends_and_rejects_unknown_events(self):
        self.assertEqual(run("log", "ingest", "My note", "--vault", str(self.root))[0], 0)
        self.assertIn("ingest | My note", (self.root / "_log.md").read_text(encoding="utf-8"))
        self.assertEqual(run("log", "bogus", "x", "--vault", str(self.root))[0], 2)

    def test_executable_shim_runs(self):
        shim = PLUGIN / "bin" / "sb"
        self.assertTrue(os.access(shim, os.X_OK))
        done = subprocess.run([str(shim), "lint", "--vault", str(self.root)],
                              capture_output=True, text=True)
        self.assertEqual((done.returncode, done.stdout), (0, ""))

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
            self.assertEqual(run("index", "--check", "--vault", str(root))[0], 0)


if __name__ == "__main__":
    unittest.main()
