import unittest

import sb_helpers  # noqa: F401
from sb.links import extract, is_asset, target_name


class ExtractTests(unittest.TestCase):
    def test_variants_code_and_line_numbers(self):
        body = ("intro [[A]]\n```\n[[Hidden]]\n```\n"
                "use `[[Code]]` and [[B|alias]] and [[C#Head]] and [[dir/D.md]]\n")
        self.assertEqual(extract(body, first_line=10),
                         [(10, "A"), (14, "B"), (14, "C"), (14, "D")])

    def test_tilde_fence_is_ignored(self):
        self.assertEqual(extract("~~~\n[[X]]\n~~~\n[[Y]]\n"), [(4, "Y")])

    def test_target_name_strips_folder_and_extension(self):
        self.assertEqual(target_name(" wiki/Resources/Café Noir.md "), "Café Noir")

    def test_is_asset(self):
        self.assertTrue(is_asset("curva.png"))
        self.assertTrue(is_asset("Diagram.drawio"))
        self.assertFalse(is_asset("Note"))
        self.assertFalse(is_asset("Note.md"))
        self.assertFalse(is_asset("Dr. Who"))   # a suffix with a space is not an extension


if __name__ == "__main__":
    unittest.main()
