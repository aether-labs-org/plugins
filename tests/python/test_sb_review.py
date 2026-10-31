import json
import re
import unittest

from sb_helpers import ROOT
from sb.review import review_body, review_hash, split_trailing_agent_blocks

VECTORS = json.loads((ROOT / "tests/fixtures/review-hash/vectors.json").read_text(encoding="utf-8"))
REQUIRED_NAMES = {"plain", "crlf", "bom", "trailing-spaces", "leading-trailing-blank-lines",
                  "trailing-agent-block", "two-trailing-agent-blocks", "agent-block-in-middle",
                  "empty-body", "frontmatter-reformatted"}


class VectorTests(unittest.TestCase):
    def test_fixture_has_the_required_vectors(self):
        names = {v["name"] for v in VECTORS}
        self.assertEqual(len(VECTORS), 16)
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


if __name__ == "__main__":
    unittest.main()
