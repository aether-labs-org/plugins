import unittest

import sb_helpers  # noqa: F401
from sb.sanitize import clean_inline
from sb.trust import label


class TrustTests(unittest.TestCase):
    def test_labels(self):
        self.assertEqual(label({"origin": "agent"}, "x"), "unreviewed")
        self.assertEqual(label({"origin": "mixed", "reviewed": ""}, "x"), "reviewed")      # mixed = human
        self.assertEqual(label({"origin": "agent", "reviewed": "2026-10-01"}, "x"), "reviewed")
        self.assertEqual(label({}, "x"), "reviewed")                       # no origin = human
        self.assertEqual(label({"origin": "human"}, "a\n> [!agent] 2026-11-02 · url:x\n> b"), "reviewed")
        self.assertEqual(label({"origin": "agent"}, "> [!agent] x"), "unreviewed")

    def test_missing_null_empty_and_empty_list_reviewed_are_all_unreviewed(self):
        # [] , "" , null and a missing key all mean not reviewed
        for data in ({"origin": "agent"}, {"origin": "agent", "reviewed": None},
                     {"origin": "agent", "reviewed": ""}, {"origin": "agent", "reviewed": []}):
            self.assertEqual(label(data, "x"), "unreviewed", data)

    def test_agent_marker_must_start_the_line(self):
        self.assertEqual(label({"origin": "human"}, "text > [!agent] not a callout"), "reviewed")
        self.assertEqual(label({"origin": "human"}, "> [!AGENT] x"), "reviewed")


class SanitizeTests(unittest.TestCase):
    def test_clean_inline(self):
        self.assertEqual(clean_inline("a​b‮c\n\td  e", 160), "abc d e")
        self.assertEqual(clean_inline("x" * 200, 160), "x" * 159 + "…")
        self.assertEqual(clean_inline("ok\x07", 160), "ok")


if __name__ == "__main__":
    unittest.main()

