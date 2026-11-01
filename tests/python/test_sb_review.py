import io
import json
import tempfile
import unittest
from datetime import date
from pathlib import Path
from unittest import mock

from sb_helpers import ROOT, make_vault, note
from sb.cli import main
from sb.guard import decide
from sb.lint import INFO_CODES, lint
from sb.review import review_body, review_hash, split_trailing_agent_blocks

VECTORS = json.loads((ROOT / "tests/fixtures/review-hash/vectors.json").read_text(encoding="utf-8"))
REQUIRED_NAMES = {"plain", "crlf", "bom", "trailing-spaces", "leading-trailing-blank-lines",
                  "trailing-agent-block", "two-trailing-agent-blocks", "agent-block-in-middle",
                  "empty-body", "frontmatter-reformatted"}


class VectorTests(unittest.TestCase):
    def test_fixture_has_the_required_vectors(self):
        names = {v["name"] for v in VECTORS}
        self.assertEqual(len(VECTORS), 24)
        self.assertLessEqual(REQUIRED_NAMES, names)
        self.assertTrue({"nfd-vs-nfc-nfc", "nfd-vs-nfc-nfd"} <= names)

    def test_vectors(self):
        for v in VECTORS:
            with self.subTest(v["name"]):
                self.assertEqual(review_body(v["file"]), v["review_body"])
                self.assertEqual(review_hash(v["file"]), v["hash"])

    def test_hash_format(self):
        for v in VECTORS:
            self.assertRegex(review_hash(v["file"]), r"^sha256:[0-9a-f]{16}$")

    def test_nfc_and_nfd_hash_differently(self):
        by_name = {v["name"]: v for v in VECTORS}
        self.assertNotEqual(review_hash(by_name["nfd-vs-nfc-nfc"]["file"]),
                            review_hash(by_name["nfd-vs-nfc-nfd"]["file"]))


class SplitTests(unittest.TestCase):
    def test_no_blocks(self):
        self.assertEqual(split_trailing_agent_blocks("a\n\nb\n"), ("a\n\nb\n", []))

    def test_two_blocks_are_split(self):
        body = "text\n\n> [!agent] d1\n> one\n\n> [!agent] d2\n> two\n"
        kept, blocks = split_trailing_agent_blocks(body)
        self.assertEqual(kept, "text\n")
        self.assertEqual(blocks, ["> [!agent] d1\n> one", "> [!agent] d2\n> two"])

    def test_plain_quote_before_the_first_header_stays(self):
        kept, blocks = split_trailing_agent_blocks("text\n\n> quote\n\n> [!agent] d\n> x\n")
        self.assertEqual(kept, "text\n\n> quote\n")
        self.assertEqual(blocks, ["> [!agent] d\n> x"])

    def test_header_needs_the_space_and_ignores_case(self):
        self.assertEqual(split_trailing_agent_blocks("a\n>[!agent] x\n")[1], [])
        self.assertEqual(len(split_trailing_agent_blocks("a\n\n> [!AGENT] x\n> y\n")[1]), 1)

    def test_text_after_a_block_makes_it_not_trailing(self):
        self.assertEqual(split_trailing_agent_blocks("> [!agent] d\n> x\ntext\n")[1], [])


class ReviewBodyTests(unittest.TestCase):
    def test_only_spaces_and_tabs_are_trimmed(self):
        self.assertEqual(review_body("---\na: b\n---\nx 　\n"), "x 　")
        self.assertEqual(review_body("---\na: b\n---\nx \t \n"), "x")

    def test_unclosed_frontmatter_is_all_body(self):
        self.assertEqual(review_body("---\ntitle: x\nbody\n"), "---\ntitle: x\nbody")


BLOCK = "\n> [!agent] 2026-11-06 · sha256:ab12cd34ef56ab78\n> New fact.\n"


def cli(*argv):
    out, err = io.StringIO(), io.StringIO()
    return main(list(argv), out=out, err=err), out.getvalue(), err.getvalue()


class ReviewCliTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = make_vault(self.tmp.name, {
            "Resources/A.md": note("A", origin="agent", body="Texto  \nsee [[B]]"),
            "Resources/B.md": note("B", origin="human", body="see [[A]]"),
        })
        self.path = self.root / "wiki/Resources/A.md"

    def lint(self, code=None):
        from sb.vault import load_config
        found = lint(self.root, load_config(self.root))
        return [f for f in found if code is None or f.code == code]

    def review(self, target="A"):
        return cli("review", target, "--vault", str(self.root))

    def test_review_sets_both_fields_and_prints_the_hash(self):
        with mock.patch("sb.cli.date") as fake:
            fake.today.return_value = date(2026, 11, 5)
            code, out, _ = self.review()
        self.assertEqual(code, 0)
        text = self.path.read_text(encoding="utf-8")
        digest = review_hash(text)
        self.assertIn("reviewed: 2026-11-05\n", text)
        self.assertIn("reviewed_hash: %s\n" % digest, text)
        self.assertIn(digest, out)
        self.assertEqual(review_body(text), "Texto\nsee [[B]]")

    def test_json_output_and_path_target(self):
        code, out, _ = cli("review", "wiki/Resources/A.md", "--vault", str(self.root), "--json")
        data = json.loads(out)
        self.assertEqual((code, data["note"]), (0, "wiki/Resources/A.md"))
        self.assertRegex(data["reviewed_hash"], r"^sha256:[0-9a-f]{16}$")

    def test_missing_note_exits_2(self):
        code, _, err = self.review("Nope")
        self.assertEqual(code, 2)
        self.assertIn("note not found", err)

    def test_about_and_non_notes_are_not_reviewable(self):
        (self.root / "wiki/Resources/_about.md").write_text("---\ndescription: x\n---\n")
        self.assertEqual(self.review("wiki/Resources/_about.md")[0], 2)
        self.assertEqual(self.review("_index.md")[0], 2)

    def test_note_without_frontmatter_exits_2_and_is_untouched(self):
        (self.root / "wiki/Resources/C.md").write_text("no frontmatter\n")
        code, _, err = self.review("C")
        self.assertEqual(code, 2)
        self.assertEqual((self.root / "wiki/Resources/C.md").read_text(), "no frontmatter\n")

    def test_review_then_edit_triggers_sb110(self):
        self.assertEqual(self.lint("SB110"), [])
        self.assertEqual(self.lint("SB106")[0].path, "wiki/Resources/A.md")
        self.review()
        self.assertEqual(self.lint("SB110"), [])
        self.assertEqual(self.lint("SB106"), [])
        text = self.path.read_text(encoding="utf-8")
        self.path.write_text(text.replace("Texto", "Outro texto"), encoding="utf-8")
        found = self.lint("SB110")
        self.assertEqual([f.path for f in found], ["wiki/Resources/A.md"])
        self.assertIn("reviewed text changed since", found[0].message)
        self.assertIn("sb review", found[0].message)
        code, _, _ = cli("lint", "--vault", str(self.root))
        self.assertEqual(code, 1)

    def test_sb110_is_not_raised_for_whitespace_crlf_or_frontmatter_changes(self):
        self.review()
        text = self.path.read_text(encoding="utf-8")
        edited = text.replace("Texto  ", "Texto").replace("title: A", "title: 'A'").replace("\n", "\r\n")
        self.path.write_bytes(edited.encode("utf-8"))
        self.assertEqual(self.lint("SB110"), [])

    def test_agent_block_after_review_is_sb112_not_sb110(self):
        self.review()
        self.path.write_text(self.path.read_text(encoding="utf-8") + BLOCK, encoding="utf-8")
        self.assertEqual(self.lint("SB110"), [])
        found = self.lint("SB112")
        self.assertEqual([f.path for f in found], ["wiki/Resources/A.md"])
        self.assertEqual(found[0].message, "1 agent block(s) waiting for review")
        self.assertIn("SB112", INFO_CODES)
        self.assertEqual(cli("lint", "--vault", str(self.root))[0], 0)

    def test_agent_block_on_a_human_note_is_sb112(self):
        b = self.root / "wiki/Resources/B.md"
        b.write_text(b.read_text(encoding="utf-8") + BLOCK, encoding="utf-8")
        self.assertEqual([f.path for f in self.lint("SB112")], ["wiki/Resources/B.md"])

    def test_unreviewed_agent_note_with_a_block_has_no_sb112(self):
        self.path.write_text(self.path.read_text(encoding="utf-8") + BLOCK, encoding="utf-8")
        self.assertEqual(self.lint("SB112"), [])

    def test_reviewed_without_hash_is_not_sb110(self):
        text = self.path.read_text(encoding="utf-8").replace("source: \n", "source: \nreviewed: 2026-10-01\n")
        self.path.write_text(text, encoding="utf-8")
        self.assertIn("reviewed: 2026-10-01", text)
        self.assertEqual(self.lint("SB110"), [])
        self.assertEqual(self.lint("SB106"), [])

    def test_review_keeps_all_other_bytes(self):
        before = self.path.read_text(encoding="utf-8")
        self.review()
        after = self.path.read_text(encoding="utf-8")
        kept = [l for l in after.split("\n") if not l.startswith(("reviewed:", "reviewed_hash:"))]
        self.assertEqual(kept, before.split("\n"))


class GuardStillDeniesReviewTests(unittest.TestCase):
    def test_guard_still_denies_agent_sb_review(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = make_vault(tmp, {"Resources/A.md": note("A", origin="agent")}).resolve()
            for command in ("sb review A", "sb review wiki/Resources/A.md --json",
                            "python3 plugins/second-brain/bin/sb review A", "env X=1 sb review A",
                            "bash -c 'sb review A'", "cd wiki && sb review A", "ls; sb review A"):
                out = decide({"tool_name": "Bash", "tool_input": {"command": command}}, str(root))
                self.assertEqual(out["hookSpecificOutput"]["permissionDecision"], "deny", command)
                self.assertIn("! prefix", out["hookSpecificOutput"]["permissionDecisionReason"])

    def test_guard_denies_the_agent_writing_reviewed_hash(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = make_vault(tmp, {"Resources/A.md": note("A", origin="agent")}).resolve()
            new = (root / "wiki/Resources/A.md").read_text().replace(
                "source: \n", "source: \nreviewed_hash: sha256:0123456789abcdef\n")
            out = decide({"tool_name": "Write", "tool_input": {
                "file_path": "wiki/Resources/A.md", "content": new}}, str(root))
            self.assertEqual(out["hookSpecificOutput"]["permissionDecision"], "deny")


if __name__ == "__main__":
    unittest.main()
