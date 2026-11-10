import io
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from sb_helpers import PLUGIN
from sb.cli import main

FIXTURES = PLUGIN / "evals" / "_fixtures"


def lint_codes(root):
    out = io.StringIO()
    code = main(["lint", "--json", "--vault", str(root)], out=out, err=io.StringIO())
    return code, {f["code"] for f in json.loads(out.getvalue())}


def build(tmp, notes_dir):
    root = Path(tmp) / "vault"
    main(["init", "--vault", str(root), "--language", "en"], out=io.StringIO(), err=io.StringIO())
    shutil.copytree(FIXTURES / notes_dir, root / "wiki", dirs_exist_ok=True)
    return root


class FixtureTests(unittest.TestCase):
    def test_clean_fixture_vault_lints_clean(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(lint_codes(build(tmp, "notes")), (0, set()))

    def test_broken_fixture_reports_the_planted_problems(self):
        with tempfile.TemporaryDirectory() as tmp:
            code, codes = lint_codes(build(tmp, "notes-broken"))
        self.assertEqual(code, 1)
        self.assertTrue({"SB101", "SB102"} <= codes)

    def test_inbox_fixture_has_no_frontmatter_the_linter_would_scan(self):
        self.assertTrue((FIXTURES / "inbox" / "2026-09-30-0900-interleaving.md").is_file())


EVALS = PLUGIN / "evals"
CASES = sorted(p.parent.name for p in EVALS.glob("*/case.yaml"))


class EvalCaseTests(unittest.TestCase):
    def test_ten_cases_with_prompt_and_graders(self):
        self.assertEqual(len(CASES), 10)
        for name in CASES:
            self.assertTrue((EVALS / name / "prompt.md").is_file(), name)
            self.assertTrue(list((EVALS / name / "graders").glob("*.md")), name)

    def test_cases_name_no_removed_concept(self):
        for path in EVALS.glob("*/**/*"):
            if path.is_file() and "results" not in path.parts and path.suffix in (".sh", ".md", ".yaml"):
                text = path.read_text(encoding="utf-8")
                for word in ("index --write", "_index.md", "_log.md", "--profile", "sb log", "source_id"):
                    self.assertNotIn(word, text, "%s mentions %s" % (path, word))

    def test_ingest_gap_and_no_padding_graders(self):
        for rel in ("ingest-gap/graders/no-invention.md", "ingest-gap/graders/asks-now-or-end.md",
                    "ingest-1ton/graders/no-padding.md"):
            self.assertIn("type: llm", (EVALS / rel).read_text(encoding="utf-8"), rel)
        prompt = (EVALS / "ingest-gap" / "prompt.md").read_text(encoding="utf-8")
        self.assertIn("runs: 3", prompt)
        self.assertIn("max_turns: 40", prompt)
        clip = next((FIXTURES / "inbox-gap").glob("*-decisao.md")).read_text(encoding="utf-8")
        self.assertIn("Adotamos", clip)

    def test_every_scaffold_builds_a_vault_that_lints_clean(self):
        for scaffold in sorted(EVALS.glob("*/scaffold.sh")):
            with tempfile.TemporaryDirectory() as tmp:
                done = subprocess.run(["bash", str(scaffold)], cwd=tmp, capture_output=True, text=True)
                self.assertEqual(done.returncode, 0, "%s: %s" % (scaffold, done.stderr))
                self.assertTrue((Path(tmp) / ".agents/second-brain/config.json").is_file(), str(scaffold))
                if scaffold.parent.name != "lint-planted":
                    self.assertEqual(lint_codes(tmp)[0], 0, str(scaffold))

    def test_folder_placement_vault_has_the_decisions_folder(self):
        with tempfile.TemporaryDirectory() as tmp:
            subprocess.run(["bash", str(EVALS / "folder-placement" / "scaffold.sh")], cwd=tmp, check=True,
                           capture_output=True)
            self.assertEqual(sorted(p.name for p in (Path(tmp) / "wiki").iterdir()),
                             ["Archive", "Areas", "Decisions", "Meetings", "Projects", "Resources"])
            self.assertTrue((Path(tmp) / "wiki/Decisions/_about.md").is_file())


if __name__ == "__main__":
    unittest.main()
