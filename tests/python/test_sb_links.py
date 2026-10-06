import unittest

import sb_helpers  # noqa: F401
from sb.links import extract, target_name


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


if __name__ == "__main__":
    unittest.main()
