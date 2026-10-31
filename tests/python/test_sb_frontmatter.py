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

    def test_block_list(self):
        p = parse("---\ntags:\n  - estudo\n  - memória\n---\n")
        self.assertEqual(p.errors, [])
        self.assertEqual(p.data, {"tags": ["estudo", "memória"]})

    def test_block_list_without_indent_and_quoted_items(self):
        p = parse("---\naliases:\n- \"Repetição espaçada\"\n- 'SRS'\ntitle: X\n---\n")
        self.assertEqual(p.errors, [])
        self.assertEqual(p.data, {"aliases": ["Repetição espaçada", "SRS"], "title": "X"})

    def test_empty_key_without_items_stays_empty_string(self):
        self.assertEqual(parse("---\nreviewed:\ntitle: X\n---\n").data,
                         {"reviewed": "", "title": "X"})

    def test_stray_list_item_is_rejected(self):
        p = parse("---\n- a\ntitle: X\n---\n")
        self.assertEqual([line for line, _ in p.errors], [2])

    def test_obsidian_properties_sample(self):
        text = ("---\ntitle: Repetição\nsummary: Revisar em intervalos.\ntags:\n  - estudo\n"
                "aliases:\n  - SRS\ncssclasses:\ntype: conceito\nstatus: draft\norigin: human\n"
                "created: 2026-10-01\n---\nCorpo\n")
        p = parse(text)
        self.assertEqual(p.errors, [])
        self.assertEqual(p.data["aliases"], ["SRS"])
        self.assertEqual(p.data["cssclasses"], "")
        self.assertEqual(p.body_line, 14)

    def test_block_list_item_comment_is_stripped(self):
        self.assertEqual(parse("---\ntags:\n  - a # c\n---\n").data, {"tags": ["a"]})

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
