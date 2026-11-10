import os
import tempfile
import unittest

from sb_helpers import make_vault, note
from sb.lint import INFO_CODES, Finding, lint, render_text
from sb.vault import load_config

PAIR = {
    "Resources/A.md": note("A", body="see [[B]]"),
    "Resources/B.md": note("B", body="see [[A]]"),
}


def run(root):
    return lint(root, load_config(root))


class LintTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def vault(self, extra=None, **kwargs):
        notes = dict(PAIR)
        notes.update(extra or {})
        return make_vault(self.tmp.name, notes, **kwargs)

    def codes(self, findings, path=None):
        return [f.code for f in findings if path is None or f.path == path]

    def test_clean_vault_has_no_findings(self):
        self.assertEqual([f for f in run(self.vault()) if f.code not in INFO_CODES], [])

    def test_sb101_broken_link_reports_the_body_line(self):
        root = self.vault({"Resources/C.md": note("C", body="x\n[[Missing]] and [[A]]")})
        found = [f for f in run(root) if f.code == "SB101"]
        self.assertEqual([(f.path, f.line) for f in found], [("wiki/Resources/C.md", 11)])

    def test_links_in_code_are_not_broken_links(self):
        root = self.vault({"Resources/C.md": note("C", body="`[[Nope]]`\n```\n[[Nope2]]\n```\n[[A]]")})
        self.assertNotIn("SB101", self.codes(run(root)))

    def test_sb102_missing_or_empty_summary_without_a_duplicate_sb108(self):
        root = self.vault({"Resources/C.md": note("C", summary=None, body="[[A]]"),
                           "Resources/D.md": note("D", summary="", body="[[A]]")})
        findings = run(root)
        for name in ("C", "D"):
            codes = self.codes(findings, "wiki/Resources/%s.md" % name)
            self.assertIn("SB102", codes, name)
            self.assertNotIn("SB108", codes, name)

    def test_sb103_orphan(self):
        root = self.vault({"Resources/C.md": note("C")})
        orphans = [f.path for f in run(root) if f.code == "SB103"]
        self.assertEqual(orphans, ["wiki/Resources/C.md"])

    def test_a_self_link_does_not_save_an_orphan(self):
        root = self.vault({"Resources/C.md": note("C", body="[[C]]")})
        self.assertIn("SB103", self.codes(run(root), "wiki/Resources/C.md"))

    def test_sb104_duplicate_basename_and_duplicate_title(self):
        root = self.vault({"Areas/A.md": note("Other", body="[[A]]"),
                           "Resources/X.md": note("Same", body="[[A]]"),
                           "Resources/Y.md": note("same", body="[[A]]")})
        paths = sorted(f.path for f in run(root) if f.code == "SB104")
        self.assertEqual(paths, ["wiki/Areas/A.md", "wiki/Resources/A.md",
                                 "wiki/Resources/X.md", "wiki/Resources/Y.md"])

    def test_sb106_agent_note_needs_review(self):
        root = self.vault({"Resources/C.md": note("C", origin="agent", body="[[A]]"),
                           "Resources/D.md": note("D", origin="agent", reviewed="2026-10-01", body="[[A]]")})
        findings = run(root)
        self.assertIn("SB106", self.codes(findings, "wiki/Resources/C.md"))
        self.assertNotIn("SB106", self.codes(findings, "wiki/Resources/D.md"))

    def test_sb107_outdated_schema_version(self):
        root = self.vault(config={"schema_version": 0})
        self.assertIn("SB107", self.codes(run(root)))

    def test_sb108_frontmatter_problems(self):
        root = self.vault({
            "Resources/E1.md": note("E1", status="done", body="[[A]]"),
            "Resources/E2.md": note("E2", created="2026-13-45", body="[[A]]"),
            "Resources/E3.md": note("E3", created=None, body="[[A]]"),
            "Resources/E4.md": "---\ntitle: E4\nsummary: s\nextra:\n  nested: 1\n---\n[[A]]\n",
            "Resources/E5.md": "# no frontmatter\n[[A]]\n",
        })
        findings = run(root)
        for name in ("E1", "E2", "E3", "E4", "E5"):
            self.assertIn("SB108", self.codes(findings, "wiki/Resources/%s.md" % name), name)

    def test_sb109_source_must_exist(self):
        root = self.vault({
            "Resources/S1.md": note("S1", source="_raw/missing.pdf", body="[[A]]"),
            "Resources/S2.md": note("S2", source="_raw/here.pdf", body="[[A]]"),
            "Resources/S3.md": note("S3", source="[[Nope]]", body="[[A]]"),
            "Resources/S4.md": note("S4", source="[[A]]", body="[[A]]"),
            "Resources/S5.md": note("S5", source="https://example.com/x", body="[[A]]"),
        })
        (root / "_raw" / "here.pdf").write_bytes(b"%PDF")
        findings = run(root)
        flagged = sorted(f.path for f in findings if f.code == "SB109")
        self.assertEqual(flagged, ["wiki/Resources/S1.md", "wiki/Resources/S3.md"])

    def test_accented_and_spaced_names_resolve(self):
        root = make_vault(self.tmp.name, {
            "Resources/Café Noir.md": note("Café Noir", body="see [[B]]"),
            "Resources/B.md": note("B", body="see [[Café Noir]] and [[café noir|alias]]"),
        })
        broken = [f.message for f in run(root) if f.code == "SB101"]
        self.assertEqual(broken, ["broken link: [[café noir]]"])

    def test_binary_note_is_reported_without_aborting(self):
        root = self.vault()
        (root / "wiki" / "Resources" / "Bin.md").write_bytes(b"\xff\xfe\x00bad")
        findings = run(root)
        self.assertIn("SB108", self.codes(findings, "wiki/Resources/Bin.md"))
        self.assertIn("SB108", self.codes(findings))

    def test_embedded_asset_is_not_a_broken_link(self):
        root = make_vault(self.tmp.name,
                          {"Resources/A.md": note("A", body="![[curva.png]] ![[falta.png]]")})
        (root / "wiki/Resources/_assets").mkdir(parents=True)
        (root / "wiki/Resources/_assets/curva.png").write_bytes(b"x")
        sb101 = [f.message for f in lint(root, {"schema_version": 1}) if f.code == "SB101"]
        self.assertEqual(sb101, ["broken link: [[falta.png]]"])

    def test_render_text_aggregates_codes_over_20(self):
        fs = [Finding("SB103", "wiki/N%d.md" % i, 1, "orphan note: nothing links here")
              for i in range(21)]
        fs.append(Finding("SB101", "wiki/A.md", 3, "broken link: [[X]]"))
        text = render_text(fs)
        self.assertIn("SB103 orphan note: nothing links here: 21 notes (run with --verbose)", text)
        self.assertIn("wiki/A.md:3: SB101 broken link: [[X]]", text)
        self.assertEqual(len(render_text(fs, verbose=True).splitlines()), 22)

    def test_render_text_aggregates_differing_messages_without_a_misleading_target(self):
        fs = [Finding("SB101", "wiki/N%d.md" % i, 1, "broken link: [[T%d]]" % i) for i in range(21)]
        self.assertEqual(render_text(fs), "SB101 broken link: 21 findings (run with --verbose)")


if __name__ == "__main__":
    unittest.main()
