import unittest

import sb_helpers  # noqa: F401  (sets sys.path)
from sb.frontmatter import parse


class ParseTests(unittest.TestCase):
    def test_scalars_lists_and_body(self):
        text = "---\ntitle: Foo\ntags: [a, \"b c\"]\nsource: [[Other]]\nreviewed:\n---\nBody\n"
        p = parse(text)
        self.assertEqual(p.errors, [])
        self.assertEqual(p.data, {"title": "Foo", "tags": ["a", "b c"],
                                  "source": "[[Other]]", "reviewed": ""})
        self.assertEqual(p.body, "Body\n")
        self.assertEqual(p.body_line, 7)

    def test_quotes_and_trailing_comment(self):
        p = parse('---\ntitle: "A: B"\nstatus: seed # note\n---\n')
        self.assertEqual(p.errors, [])
        self.assertEqual(p.data, {"title": "A: B", "status": "seed"})

    def test_crlf_and_bom(self):
        p = parse("﻿---\r\ntitle: Foo\r\nsummary: Bar\r\n---\r\nBody\r\n")
        self.assertEqual(p.errors, [])
        self.assertEqual(p.data, {"title": "Foo", "summary": "Bar"})

    def test_nested_mapping_is_rejected_with_line_number(self):
        p = parse("---\nkey:\n  nested: 1\n---\n")
        self.assertEqual([line for line, _ in p.errors], [3])

    def test_block_list_is_rejected(self):
        p = parse("---\ntags:\n- a\n---\n")
        self.assertEqual([line for line, _ in p.errors], [3])

    def test_block_scalar_is_rejected(self):
        p = parse("---\nsummary: |\n  x\n---\n")
        self.assertEqual([line for line, _ in p.errors], [2, 3])

    def test_missing_frontmatter(self):
        p = parse("# Title\n")
        self.assertEqual(p.errors, [(1, "missing frontmatter")])
        self.assertEqual(p.body, "# Title\n")
        self.assertEqual(p.body_line, 1)

    def test_unclosed_frontmatter(self):
        p = parse("---\ntitle: x\n")
        self.assertEqual(p.errors, [(1, "frontmatter is not closed with ---")])

    def test_duplicate_key(self):
        p = parse("---\ntitle: a\ntitle: b\n---\n")
        self.assertEqual(p.data, {"title": "a"})
        self.assertEqual([line for line, _ in p.errors], [3])


if __name__ == "__main__":
    unittest.main()
