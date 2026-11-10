import io
import json
import os
import tempfile
import unittest

from sb_helpers import make_vault, note
from sb.cli import main
from sb.lint import Finding, lint, render_text

PAIR = {
    "Resources/A.md": note("A", body="see [[B]]"),
    "Resources/B.md": note("B", body="see [[A]]"),
}


def run(root):
    return lint(root)


def failures(findings):
    return [f for f in findings if not f.info]


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
        self.assertEqual(failures(run(self.vault())), [])

    def test_minimal_note_passes(self):
        text = "---\nsummary: One line.\norigin: human\ncreated: 2026-11-10\n---\nbody [[B]]\n"
        root = self.vault({"Resources/M.md": text})
        self.assertEqual(failures([f for f in run(root) if f.path == "wiki/Resources/M.md"]), [])

    def test_legacy_keys_are_ignored(self):
        text = ("---\ntype: nota\nstatus: evergreen\nprotected: true\norigin: mixed\n"
                "summary: S.\ncreated: 2026-11-10\nreviewed_hash: sha256:0123456789abcdef\n"
                "source_id: sha256:0123456789abcdef\n---\nbody [[B]]\n")
        root = self.vault({"Resources/L.md": text})
        found = [f for f in run(root) if f.path == "wiki/Resources/L.md"]
        self.assertEqual(failures(found), [])
        for f in found:
            for key in ("type", "status", "protected", "mixed", "reviewed_hash", "source_id"):
                self.assertNotIn(key, f.message)

    def test_missing_required_key_is_sb108(self):
        root = self.vault({"Resources/N1.md": note("N1", created=None, body="[[A]]"),
                           "Resources/N2.md": note("N2", origin="robot", body="[[A]]")})
        found = run(root)
        self.assertIn("missing required key: created",
                      [f.message for f in found if f.path == "wiki/Resources/N1.md" and f.code == "SB108"])
        self.assertIn("SB108", self.codes(found, "wiki/Resources/N2.md"))

    def test_title_is_optional(self):
        text = "---\nsummary: S.\norigin: human\ncreated: 2026-11-10\n---\n[[B]]\n"
        root = self.vault({"Resources/NoTitle.md": text})
        self.assertEqual(self.codes(run(root), "wiki/Resources/NoTitle.md"), ["SB103"])

    def test_sb103_and_sb106_are_info(self):
        root = self.vault({"Resources/O.md": note("O", origin="agent")})
        found = [f for f in run(root) if f.path == "wiki/Resources/O.md"]
        self.assertEqual(sorted(f.code for f in found), ["SB103", "SB106"])
        self.assertTrue(all(f.info for f in found))
        out, err = io.StringIO(), io.StringIO()
        self.assertEqual(main(["lint", "--vault", str(root)], out=out, err=err), 0)
        out = io.StringIO()
        main(["lint", "--json", "--vault", str(root)], out=out, err=io.StringIO())
        self.assertTrue(all(f["info"] for f in json.loads(out.getvalue())))

    def test_failures_exit_1_and_carry_info_false(self):
        root = self.vault({"Resources/F.md": note("F", body="[[Nope]] [[A]]")})
        out = io.StringIO()
        self.assertEqual(main(["lint", "--json", "--vault", str(root)], out=out, err=io.StringIO()), 1)
        flagged = [f for f in json.loads(out.getvalue()) if f["code"] == "SB101"]
        self.assertEqual([f["info"] for f in flagged], [False])

    def test_dropped_codes_never_appear(self):
        root = self.vault({"Bare/C.md": note("C", origin="agent", body="[[Nope]]")})
        (root / "wiki" / "Resources" / "_about.md").write_text("---\ndescription: x\n---\n", encoding="utf-8")
        allowed = {"SB101", "SB102", "SB103", "SB104", "SB106", "SB108", "SB109"}
        self.assertTrue({f.code for f in run(root)} <= allowed)

    def test_sb101_broken_link_reports_the_body_line(self):
        root = self.vault({"Resources/C.md": note("C", body="x\n[[Missing]] and [[A]]")})
        found = [f for f in run(root) if f.code == "SB101"]
        self.assertEqual([(f.path, f.line) for f in found], [("wiki/Resources/C.md", 9)])

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

    def test_sb108_frontmatter_problems(self):
        root = self.vault({
            "Resources/E1.md": note("E1", origin="robot", body="[[A]]"),
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
        self.assertEqual([f.info for f in findings if f.code == "SB109"], [False, False])

    def test_sb109_external_missing_is_info(self):
        root = self.vault({
            "Resources/X1.md": note("X1", source="~/no-such-file-xyz.pdf", body="[[A]]"),
            "Resources/X2.md": note("X2", source="/tmp/no-such-file-xyz.pdf", body="[[A]]"),
            "Resources/X3.md": note("X3", source="_raw/missing.pdf", body="[[A]]"),
            "Resources/X4.md": note("X4", source="https://example.org/a", body="[[A]]"),
        })
        found = {f.path: f for f in run(root) if f.code == "SB109"}
        self.assertEqual(sorted(found), ["wiki/Resources/X1.md", "wiki/Resources/X2.md",
                                         "wiki/Resources/X3.md"])
        self.assertTrue(found["wiki/Resources/X1.md"].info)
        self.assertTrue(found["wiki/Resources/X2.md"].info)
        self.assertFalse(found["wiki/Resources/X3.md"].info)

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
        sb101 = [f.message for f in lint(root) if f.code == "SB101"]
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
