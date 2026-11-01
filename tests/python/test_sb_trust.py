import unittest

import sb_helpers  # noqa: F401
from sb.sanitize import clean_inline
from sb.trust import (TRUST_FIELDS, append_only, label, link_only, tier, trust_fields_changed,
                      trust_fields_changed_text)


class TrustTests(unittest.TestCase):
    def test_labels(self):
        self.assertEqual(label({"origin": "agent"}, "x"), "unreviewed")
        self.assertEqual(label({"origin": "mixed", "reviewed": ""}, "x"), "unreviewed")
        self.assertEqual(label({"origin": "agent", "reviewed": "2026-10-01"}, "x"), "reviewed")
        self.assertEqual(label({}, "x"), "reviewed")                       # no origin = human
        self.assertEqual(label({"origin": "human"}, "a\n> [!agent] 2026-11-02 · url:x\n> b"),
                         "has-agent-blocks")
        self.assertEqual(label({"origin": "agent"}, "> [!agent] x"), "unreviewed")

    def test_missing_null_empty_and_empty_list_reviewed_are_all_unreviewed(self):
        # parity with the companion's trustState: [] , "" , null and a missing key mean not reviewed
        for data in ({"origin": "agent"}, {"origin": "agent", "reviewed": None},
                     {"origin": "agent", "reviewed": ""}, {"origin": "agent", "reviewed": []}):
            self.assertEqual(label(data, "x"), "unreviewed", data)

    def test_agent_marker_must_start_the_line(self):
        self.assertEqual(label({"origin": "human"}, "text > [!agent] not a callout"), "reviewed")
        self.assertEqual(label({"origin": "human"}, "> [!AGENT] x"), "has-agent-blocks")

BASE = "---\ntitle: A\norigin: human\n---\nTexto revisado.\n"
BLOCK = "\n> [!agent] 2026-11-02 · url:https://x.org/a\n> Novo fato.\n"


class TierTests(unittest.TestCase):
    def test_trust_fields(self):
        self.assertEqual(TRUST_FIELDS, ("reviewed", "reviewed_hash", "protected", "origin"))

    def test_tier(self):
        self.assertEqual(tier({"origin": "agent"}), "T0")
        self.assertEqual(tier({"origin": "agent", "reviewed": "2026-10-01"}), "T1")
        self.assertEqual(tier({}), "T1")
        self.assertEqual(tier({"origin": "Agent"}), "T1")      # only the exact lowercase value
        self.assertEqual(tier({"origin": "AGENT"}), "T1")
        self.assertEqual(tier({"origin": "mixed"}), "T1")
        self.assertEqual(tier({"origin": "agent", "status": "evergreen"}), "T2")
        self.assertEqual(tier({"origin": "human", "protected": "true"}), "T2")
        self.assertEqual(tier({"origin": "human", "protected": "false"}), "T1")
        self.assertEqual(tier({"origin": "agent"}, folder_protected=True), "T2")

    def test_trust_fields_changed(self):
        self.assertEqual(trust_fields_changed({"origin": "human"}, {"origin": "mixed"}), ["origin"])
        self.assertEqual(trust_fields_changed({"reviewed": ""}, {}), [])
        self.assertEqual(trust_fields_changed({"title": "a"}, {"title": "b"}), [])

    def test_trust_fields_changed_text_sees_duplicate_keys(self):
        dup = BASE.replace("origin: human", "origin: human\norigin: agent")
        self.assertEqual(trust_fields_changed_text(BASE, BASE), [])
        self.assertEqual(trust_fields_changed_text(BASE, dup), ["origin"])
        self.assertEqual(trust_fields_changed_text(BASE, BASE.replace("human", "agent")), ["origin"])


class ChangeClassificationTests(unittest.TestCase):
    def test_append_only(self):
        self.assertTrue(append_only(BASE, BASE + BLOCK))
        self.assertTrue(append_only(BASE, BASE.replace("origin: human", "origin: human\nupdated: 2026-11-02") + BLOCK))
        self.assertFalse(append_only(BASE, BASE.replace("revisado", "revisto") + BLOCK))   # rewrite
        self.assertFalse(append_only(BASE, BASE + "\nTexto solto do agente.\n"))           # not a block
        self.assertFalse(append_only(BASE, BASE.replace("title: A", "title: B") + BLOCK))  # other key
        self.assertFalse(append_only(BASE, BASE))                                          # no-op

    def test_append_only_rejects_text_glued_to_the_last_line(self):
        glued = BASE.rstrip("\n") + "> [!agent] 2026-11-02 · url:x\n> y\n"
        self.assertFalse(append_only(BASE, glued))

    def test_append_only_rejects_unparsed_frontmatter_edits(self):
        old = "---\ntitle: A\ntags: {x}\n---\nTexto.\n"
        self.assertFalse(append_only(old, old.replace("{x}", "{y}") + BLOCK))

    def test_append_only_ignores_line_endings(self):
        self.assertTrue(append_only(BASE.replace("\n", "\r\n"), BASE + BLOCK))

    def test_link_only(self):
        old = "---\ntitle: A\n---\nVer Active Recall e Zettelkasten.\n"
        self.assertTrue(link_only(old, old.replace("Active Recall", "[[Active Recall]]")))
        self.assertTrue(link_only(old, old.replace("Zettelkasten", "[[Zettelkasten|Zettelkasten]]")))
        self.assertFalse(link_only(old, old.replace("Ver", "Veja [[Active Recall]]")))
        self.assertFalse(link_only(old, old))

    def test_link_only_rejects_retargeting_an_existing_link(self):
        old = "---\ntitle: A\n---\nVer [[Real|isto]].\n"
        self.assertFalse(link_only(old, old.replace("[[Real|", "[[Outro|")))


class SanitizeTests(unittest.TestCase):
    def test_clean_inline(self):
        self.assertEqual(clean_inline("a​b‮c\n\td  e", 160), "abc d e")
        self.assertEqual(clean_inline("x" * 200, 160), "x" * 159 + "…")
        self.assertEqual(clean_inline("ok\x07", 160), "ok")


if __name__ == "__main__":
    unittest.main()
