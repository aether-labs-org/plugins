import io
import json
import shutil
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
    main(["index", "--write", "--vault", str(root)], out=io.StringIO(), err=io.StringIO())
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


if __name__ == "__main__":
    unittest.main()
