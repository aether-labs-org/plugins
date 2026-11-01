import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from sb_helpers import PLUGIN, make_vault, note
from sb.guard import decide


class GuardTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = make_vault(self.tmp.name, {"Resources/A.md": note("A")})
        self.vault = self.root.resolve()

    def verdict(self, tool, cwd=None, **tool_input):
        event = {"tool_name": tool, "tool_input": tool_input}
        out = decide(event, str(cwd or self.vault))
        return out["hookSpecificOutput"]["permissionDecision"] if out else "allow"

    def bash(self, command, cwd=None):
        return self.verdict("Bash", cwd=cwd, command=command)

    def test_write_tools_deny_protected_paths(self):
        for tool, key in (("Write", "file_path"), ("Edit", "file_path"),
                          ("MultiEdit", "file_path"), ("NotebookEdit", "notebook_path")):
            for path in ("_raw/a.md", "CLAUDE.md", ".claude/settings.json", ".second-brain.json"):
                self.assertEqual(self.verdict(tool, **{key: path}), "deny", (tool, path))

    def test_write_tools_deny_absolute_and_traversal_paths(self):
        self.assertEqual(self.verdict("Write", file_path=str(self.vault / "_raw" / "a.md")), "deny")
        self.assertEqual(self.verdict("Write", file_path="wiki/../_raw/a.md"), "deny")

    def test_symlink_into_raw_is_denied(self):
        os.symlink(self.vault / "_raw", self.vault / "wiki" / "link")
        self.assertEqual(self.verdict("Write", file_path="wiki/link/a.md"), "deny")

    def test_write_tools_allow_normal_paths(self):
        for path in ("wiki/Resources/a.txt", "_index.md", "_log.md", "_inbox/x.md",
                     "wiki/sub/CLAUDE.md", "/tmp/elsewhere.txt"):
            self.assertEqual(self.verdict("Write", file_path=path, content=note("N", origin="agent")),
                             "allow", path)

    def test_works_from_a_subfolder(self):
        sub = self.vault / "wiki" / "Resources"
        self.assertEqual(self.verdict("Write", cwd=sub, file_path="../../_raw/a.md"), "deny")
        self.assertEqual(self.bash("rm ../../_raw/a.pdf", cwd=sub), "deny")

    def test_bash_denies_mutations_of_protected_paths(self):
        for command in ("echo x > _raw/a.md", "echo x >> CLAUDE.md", "rm _raw/a.pdf",
                        "rm -rf _raw", "mv _raw/a.pdf wiki/", "sed -i s/a/b/ CLAUDE.md",
                        "cp wiki/a.md _raw/", "rm -rf .", "git rm _raw/a", "touch .claude/x",
                        "echo hi | tee _raw/x", "cd . && rm _raw/x", "sudo rm _raw/x"):
            self.assertEqual(self.bash(command), "deny", command)

    def test_bash_allows_reads_and_harmless_commands(self):
        for command in ("cat _raw/a.md", "rg foo _raw", "ls", "cp _raw/a.pdf wiki/x.pdf",
                        "echo hi 2>&1", "echo x > /dev/null", "sb lint", "git status",
                        "mv _inbox/a.md _inbox/_done/a.md"):
            self.assertEqual(self.bash(command), "allow", command)

    def test_bash_asks_before_deleting_curated_notes(self):
        for command in ("rm wiki/Resources/A.md", "rm -rf wiki", "git rm wiki/Resources/A.md",
                        "rm *.md"):
            self.assertEqual(self.bash(command), "ask", command)

    def test_deny_message_tells_the_human_to_edit_directly(self):
        out = decide({"tool_name": "Write", "tool_input": {"file_path": "_raw/a.md"}}, str(self.vault))
        reason = out["hookSpecificOutput"]["permissionDecisionReason"]
        self.assertIn("_raw/a.md", reason)
        self.assertIn("human", reason)

    def test_noop_outside_a_vault(self):
        outside = tempfile.mkdtemp()
        self.addCleanup(os.rmdir, outside)
        self.assertEqual(self.verdict("Write", cwd=outside, file_path="_raw/a.md"), "allow")
        self.assertEqual(self.bash("rm -rf _raw", cwd=outside), "allow")

    def test_event_cwd_overrides_process_cwd(self):
        event = {"cwd": str(self.vault), "tool_name": "Write", "tool_input": {"file_path": "_raw/a.md"}}
        self.assertIsNotNone(decide(event, tempfile.gettempdir()))


HUMAN = note("H", body="Texto revisado.", origin="human")
AGENT = note("G", body="Texto do agente.", origin="agent")
REVIEWED = note("R", body="Texto revisado.", origin="agent", reviewed="2026-10-01")
EVERGREEN = note("E", body="Texto perene.", origin="human", status="evergreen")
BLOCK = "\n> [!agent] 2026-11-02 · url:https://x.org/a\n> Novo fato.\n"
REASON_TRUST = "Only the human sets trust fields (reviewed, reviewed_hash, protected, origin)."


class NoteGuardTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = make_vault(self.tmp.name, {
            "Resources/H.md": HUMAN, "Resources/G.md": AGENT, "Resources/R.md": REVIEWED,
            "Resources/E.md": EVERGREEN,
            "Resources/P.md": note("P", origin="agent").replace("origin: agent", "origin: agent\nprotected: true"),
        })
        self.vault = self.root.resolve()

    def decide(self, tool, path, **tool_input):
        tool_input["file_path"] = path
        return decide({"tool_name": tool, "tool_input": tool_input}, str(self.vault))

    def kind(self, tool, path, **tool_input):
        out = self.decide(tool, path, **tool_input)
        return out["hookSpecificOutput"]["permissionDecision"] if out else "allow"

    def reason(self, tool, path, **tool_input):
        return self.decide(tool, path, **tool_input)["hookSpecificOutput"]["permissionDecisionReason"]

    def text(self, name):
        return (self.vault / "wiki" / "Resources" / name).read_text(encoding="utf-8")

    # new files
    def test_new_note_with_origin_agent_is_allowed(self):
        self.assertEqual(self.kind("Write", "wiki/Resources/N.md", content=AGENT), "allow")

    def test_new_note_without_origin_agent_is_denied(self):
        for origin in ("human", "mixed"):
            content = note("N", origin=origin)
            self.assertEqual(self.kind("Write", "wiki/Resources/N.md", content=content), "deny")
            self.assertTrue(self.reason("Write", "wiki/Resources/N.md", content=content)
                            .startswith("New notes written by the agent must have origin: agent."))
        no_origin = AGENT.replace("origin: agent\n", "")
        self.assertEqual(self.kind("Write", "wiki/Resources/N.md", content=no_origin), "deny")

    def test_new_note_cannot_set_trust_fields(self):
        for extra in ("reviewed: 2026-11-02", "reviewed_hash: sha256:00", "protected: true"):
            content = AGENT.replace("origin: agent", "origin: agent\n" + extra)
            self.assertEqual(self.kind("Write", "wiki/Resources/N.md", content=content), "deny", extra)
            self.assertTrue(self.reason("Write", "wiki/Resources/N.md", content=content)
                            .startswith(REASON_TRUST))

    FENCE_VARIANTS = ("\x1c", "\x1f", "\x85", "\xa0", "\x0b", "\x0c", " ", "\u3000", "\t", "\u2003")

    def test_new_note_fence_lookalikes_cannot_hide_trust_fields(self):
        # a line the guard's old str.strip() took for a fence, but the parser did not (or the reverse)
        for ch in self.FENCE_VARIANTS:
            content = ("---\norigin: agent\ntitle: x\n%s---\nreviewed: 2026-01-01\n"
                       "reviewed_hash: sha256:00\n---\nbody" % ch)
            self.assertEqual(self.kind("Write", "wiki/Resources/N.md", content=content), "deny", repr(ch))
            self.assertTrue(self.reason("Write", "wiki/Resources/N.md", content=content)
                            .startswith(REASON_TRUST), repr(ch))

    def test_new_note_trust_key_in_parsed_data_is_denied(self):
        # the parser reads `reviewed` here; whatever the line scan thinks the frontmatter is
        content = "---\norigin: agent\n\x1c---\nprotected: true\n---\nbody"
        self.assertEqual(self.kind("Write", "wiki/Resources/N.md", content=content), "deny")

    def test_t1_edit_with_fence_lookalike_never_allows(self):
        for ch in self.FENCE_VARIANTS:
            new = "title: G\n%s---\ntags: [x]\nstatus: evergreen\n---\n" % ch
            self.assertNotEqual(self.kind("Edit", "wiki/Resources/H.md", old_string="title: H\n",
                                          new_string=new), "allow", repr(ch))
            content = "---\ntitle: H\n%s---\n---\nREWRITTEN\n" % ch
            self.assertNotEqual(self.kind("Write", "wiki/Resources/H.md", content=content),
                                "allow", repr(ch))

    def test_t0_edit_adding_lookalike_fence_and_reviewed_is_denied(self):
        for ch in self.FENCE_VARIANTS:
            self.assertEqual(self.kind("Edit", "wiki/Resources/G.md", old_string="origin: agent",
                                       new_string="origin: agent\n%s---\nreviewed: 2026-01-01" % ch),
                             "deny", repr(ch))

    def test_new_note_regular_forms_stay_allowed(self):
        for content in ("---\r\norigin: agent\r\n---\r\nbody\r\n",
                        "---\norigin: \"agent\"\nupdated: 2026-10-31\naliases:\n  - Foo\n---\nbody\n",
                        "---\norigin: agent\n---\nbody\n\n---\n\nmore\n"):
            self.assertEqual(self.kind("Write", "wiki/Resources/N.md", content=content), "allow", content)

    def test_new_note_with_duplicate_origin_key_is_denied(self):
        content = AGENT.replace("origin: agent", "origin: agent\norigin: human")
        self.assertEqual(self.kind("Write", "wiki/Resources/N.md", content=content), "deny")

    # trust fields on existing notes
    def test_trust_field_changes_are_denied_in_every_tier(self):
        for name, text in (("G.md", AGENT), ("H.md", HUMAN), ("R.md", REVIEWED), ("E.md", EVERGREEN)):
            new = text.replace("origin: agent", "origin: human") if "origin: agent" in text \
                else text.replace("origin: human", "origin: mixed")
            self.assertEqual(self.kind("Write", "wiki/Resources/" + name, content=new), "deny", name)

    def test_agent_cannot_mark_its_own_note_reviewed(self):
        new = AGENT.replace("origin: agent", "origin: agent\nreviewed: 2026-11-02")
        self.assertEqual(self.kind("Write", "wiki/Resources/G.md", content=new), "deny")
        self.assertTrue(self.reason("Write", "wiki/Resources/G.md", content=new).startswith(REASON_TRUST))

    def test_edit_clearing_reviewed_is_denied(self):
        self.assertEqual(self.kind("Edit", "wiki/Resources/R.md",
                                   old_string="reviewed: 2026-10-01\n", new_string=""), "deny")

    def test_edit_adding_protected_is_denied(self):
        self.assertEqual(self.kind("Edit", "wiki/Resources/G.md", old_string="origin: agent",
                                   new_string="origin: agent\nprotected: true"), "deny")

    # T0
    def test_t0_edits_are_free(self):
        self.assertEqual(self.kind("Edit", "wiki/Resources/G.md", old_string="do agente",
                                   new_string="reescrito"), "allow")
        self.assertEqual(self.kind("Write", "wiki/Resources/G.md",
                                   content=AGENT.replace("Texto", "Outro texto")), "allow")

    # T1
    def test_t1_rewrite_asks(self):
        for name in ("H.md", "R.md"):
            self.assertEqual(self.kind("Edit", "wiki/Resources/" + name, old_string="revisado",
                                       new_string="revisto"), "ask", name)
        self.assertTrue(self.reason("Edit", "wiki/Resources/H.md", old_string="revisado",
                                    new_string="revisto").startswith(
            'wiki/Resources/H.md is a human or reviewed note (T1). Prefer appending a "> [!agent]" block;'))

    def test_t1_append_block_via_write_is_allowed(self):
        self.assertEqual(self.kind("Write", "wiki/Resources/H.md", content=HUMAN + BLOCK), "allow")

    def test_t1_append_block_via_edit_is_allowed(self):
        self.assertEqual(self.kind("Edit", "wiki/Resources/H.md", old_string="Texto revisado.\n",
                                   new_string="Texto revisado.\n" + BLOCK), "allow")

    def test_append_plus_typo_asks(self):
        new = HUMAN.replace("revisado", "revisto") + BLOCK
        self.assertEqual(self.kind("Write", "wiki/Resources/H.md", content=new), "ask")

    def test_t1_loose_text_append_asks(self):
        self.assertEqual(self.kind("Write", "wiki/Resources/H.md",
                                   content=HUMAN + "\nSolto.\n"), "ask")

    def test_t1_link_only_is_allowed(self):
        self.assertEqual(self.kind("Edit", "wiki/Resources/H.md", old_string="revisado",
                                   new_string="[[revisado]]"), "allow")

    def test_t1_link_plus_text_change_asks(self):
        self.assertEqual(self.kind("Edit", "wiki/Resources/H.md", old_string="Texto revisado",
                                   new_string="Texto [[revisado]] e mais"), "ask")

    def test_noop_write_is_allowed(self):
        self.assertEqual(self.kind("Write", "wiki/Resources/H.md", content=HUMAN), "allow")

    # T2
    def test_t2_rewrite_asks_for_evergreen_and_protected(self):
        for name in ("E.md", "P.md"):
            out = self.kind("Write", "wiki/Resources/" + name,
                            content=self.text(name).rstrip("\n") + "\nMudado.\n")
            self.assertEqual(out, "ask", name)
        self.assertTrue(self.reason("Write", "wiki/Resources/E.md",
                                    content=EVERGREEN.replace("perene", "x")).startswith(
            "wiki/Resources/E.md is protected (T2: protected, evergreen or protected folder)."))

    def test_t2_append_still_asks(self):
        self.assertEqual(self.kind("Write", "wiki/Resources/E.md", content=EVERGREEN + BLOCK), "ask")

    def test_t2_link_only_still_asks(self):
        self.assertEqual(self.kind("Edit", "wiki/Resources/E.md", old_string="perene",
                                   new_string="[[perene]]"), "ask")

    def protect_folder(self, folder="Areas"):
        about = self.vault / "wiki" / folder / "_about.md"
        about.parent.mkdir(parents=True, exist_ok=True)
        about.write_text("---\ndescription: Mine.\nprotected: true\n---\n", encoding="utf-8")

    def test_folder_protected_note_asks(self):
        self.protect_folder()
        path = self.vault / "wiki" / "Areas" / "Saude" / "G.md"
        path.parent.mkdir(parents=True)
        path.write_text(AGENT, encoding="utf-8")        # an unreviewed agent note: T0 elsewhere
        out = self.kind("Write", "wiki/Areas/Saude/G.md", content=AGENT.replace("agente", "x"))
        self.assertEqual(out, "ask")
        self.assertIn("protected", self.reason("Write", "wiki/Areas/Saude/G.md",
                                               content=AGENT.replace("agente", "x")))
        self.assertEqual(self.kind("Write", "wiki/Resources/G.md",
                                   content=AGENT.replace("agente", "x")), "allow")

    def test_new_note_in_protected_folder_asks(self):
        self.protect_folder()
        self.assertEqual(self.kind("Write", "wiki/Areas/N.md", content=AGENT), "ask")
        self.assertEqual(self.kind("Write", "wiki/Areas/N.md", content=note("N", origin="human")),
                         "deny")

    # simulation
    def test_unsimulatable_edit_on_an_existing_note_asks(self):
        for name in ("H.md", "G.md"):
            self.assertEqual(self.kind("Edit", "wiki/Resources/" + name,
                                       old_string="nao existe", new_string="x"), "ask", name)
        self.assertIn("could not", self.reason("Edit", "wiki/Resources/H.md",
                                               old_string="nao existe", new_string="x"))

    def test_edit_on_missing_file_is_allowed(self):
        self.assertIsNone(self.decide("Edit", "wiki/Resources/Nope.md", old_string="a", new_string="b"))

    def test_multiedit_applies_edits_in_order(self):
        # the second edit only matches because of the first
        edits = [{"old_string": "revisado", "new_string": "X"},
                 {"old_string": "Texto X", "new_string": "Texto revisado"}]
        self.assertEqual(self.kind("MultiEdit", "wiki/Resources/H.md", edits=edits), "allow")
        edits = [{"old_string": "revisado", "new_string": "X"}]
        self.assertEqual(self.kind("MultiEdit", "wiki/Resources/H.md", edits=edits), "ask")

    def test_multiedit_with_a_missing_old_string_asks(self):
        edits = [{"old_string": "revisado", "new_string": "X"},
                 {"old_string": "ausente", "new_string": "Y"}]
        self.assertEqual(self.kind("MultiEdit", "wiki/Resources/H.md", edits=edits), "ask")

    # M8: quote-normalised matching
    def test_edit_matches_across_straight_and_curly_quotes(self):
        path = self.vault / "wiki" / "Resources" / "Q.md"
        path.write_text(HUMAN.replace("Texto revisado.", "Ele disse \u201col\u00e1\u201d e \u2018tchau\u2019."),
                        encoding="utf-8")
        # the straight-quote edit finds the curly text: a T1 body change asks, it is not waved through
        self.assertEqual(self.kind("Edit", "wiki/Resources/Q.md", old_string='disse "ol\u00e1" e \'tchau\'',
                                   new_string="x"), "ask")
        # a link-only change through the normalised match is simulated as link-only
        self.assertEqual(self.kind("Edit", "wiki/Resources/Q.md", old_string='"ol\u00e1"',
                                   new_string='"[[ol\u00e1]]"'), "ask")        # quotes changed: not link-only
        self.assertEqual(self.kind("Edit", "wiki/Resources/Q.md", old_string="tchau",
                                   new_string="[[tchau]]"), "allow")
        # and a trust change is still caught
        path.write_text(AGENT.replace("Texto do agente.", "\u201cx\u201d"), encoding="utf-8")
        self.assertEqual(self.kind("Edit", "wiki/Resources/Q.md", old_string='"x"\n',
                                   new_string='"x"\n\n> [!agent] n\n> y\n'), "allow")
        self.assertEqual(self.kind("MultiEdit", "wiki/Resources/Q.md", edits=[
            {"old_string": "origin: agent", "new_string": "origin: agent\nreviewed: 2026-01-01"}]), "deny")

    def test_edit_that_still_does_not_match_asks_on_t0_too(self):
        self.assertEqual(self.kind("Edit", "wiki/Resources/G.md", old_string="nada disso",
                                   new_string="x"), "ask")

    def test_edit_replace_all(self):
        path = self.vault / "wiki" / "Resources" / "H.md"
        path.write_text(HUMAN.replace("Texto revisado.", "a b a"), encoding="utf-8")
        self.assertEqual(self.kind("Edit", "wiki/Resources/H.md", old_string="a b a",
                                   new_string="x", replace_all=True), "ask")
        self.assertEqual(self.kind("Edit", "wiki/Resources/H.md", old_string="a b a",
                                   new_string="[[a]] b [[a]]", replace_all=True), "allow")

    def test_crlf_note_with_lf_append_is_allowed(self):
        path = self.vault / "wiki" / "Resources" / "H.md"
        path.write_bytes(HUMAN.replace("\n", "\r\n").encode("utf-8"))
        self.assertEqual(self.kind("Write", "wiki/Resources/H.md", content=HUMAN + BLOCK), "allow")

    # L1: a note the guard cannot decode
    def test_undecodable_note_asks(self):
        path = self.vault / "wiki" / "Resources" / "Bin.md"
        path.write_bytes(b"---\ntitle: x\norigin: agent\n---\ncaf\xe9\n")        # latin-1, not UTF-8
        self.assertEqual(self.kind("Write", "wiki/Resources/Bin.md", content=AGENT), "ask")
        self.assertEqual(self.kind("Edit", "wiki/Resources/Bin.md", old_string="x", new_string="y"), "ask")
        self.assertEqual(self.kind("MultiEdit", "wiki/Resources/Bin.md",
                                   edits=[{"old_string": "x", "new_string": "y"}]), "ask")

    # L2: case-insensitive file systems
    def test_case_is_folded_on_a_case_insensitive_vault(self):
        from unittest import mock
        content = note("N", origin="human")
        self.assertEqual(self.kind("Write", "WIKI/Resources/N.md", content=content), "allow")  # Linux
        self.assertEqual(self.kind("Write", "_RAW/a.md", content="x"), "allow")
        with mock.patch("sb.guard._case_insensitive", return_value=True):
            self.assertEqual(self.kind("Write", "WIKI/Resources/N.md", content=content), "deny")
            self.assertEqual(self.kind("Write", "Wiki/resources/N.md", content=AGENT), "allow")
            for path in ("_RAW/a.md", ".Claude/settings.json", "claude.MD", ".SECOND-brain.json"):
                self.assertEqual(self.kind("Write", path, content="x"), "deny", path)
            self.assertEqual(self.kind("Write", "WIKI/Resources/_About.md",
                                       content="---\nprotected: true\n---\n"), "deny")

    # paths
    def test_non_note_paths_keep_v01_rules(self):
        self.assertEqual(self.kind("Write", "wiki/Resources/_assets/x.md", content="x"), "allow")
        self.assertEqual(self.kind("Write", "_inbox/x.md", content="x"), "allow")
        self.assertEqual(self.kind("Write", "_index.md", content="x"), "allow")
        self.assertEqual(self.kind("Write", "_raw/x.md", content="x"), "deny")
        self.assertEqual(self.kind("Write", "wiki/Resources/d.excalidraw.md", content="x"), "allow")

    def test_notes_are_found_through_absolute_and_dotdot_paths(self):
        absolute = str(self.vault / "wiki/Resources/H.md")
        self.assertEqual(self.kind("Edit", absolute, old_string="revisado", new_string="x"), "ask")
        self.assertEqual(self.kind("Edit", "wiki/Resources/../Resources/H.md",
                                   old_string="revisado", new_string="x"), "ask")

    # H1: sb review through every wrapper the lexer can see
    def test_sb_review_bypasses_are_denied(self):
        for command in ("(sb review N)", "echo $(sb review N)", "echo `sb review N`",
                        "echo x &sb review N", "echo x & sb review N", "timeout 5 sb review N",
                        "nice -n 5 sb review N", "stdbuf -oL sb review N", "echo N | xargs sb review",
                        "sudo -u x sb review N", "env -i FOO=1 sb review N", "command sb review N",
                        "bash -lc 'sb review N'", "sh -ec 'sb review N'", "zsh -c 'sb review N'",
                        "dash -c \"sb review N\"", "eval 'sb review N'", "eval sb review N",
                        "python3 bin/sb review N", "python3 -m sb.cli review N",
                        "python3 -W error -m sb review N", "{ sb review N; }",
                        "if true; then sb review N; fi", "echo \"$(bash -c 'sb review N')\"",
                        "bash -c \"eval 'sb review N'\"", "timeout 5 bash -lc 'sb review N'",
                        "bash <<EOF\nsb review N\nEOF", "SB=sb; $SB review N", "./bin/sb review N",
                        "(cd x && /p/bin/sb review N)", "xargs -I{} sh -c 'sb review {}' < list"):
            self.assertEqual(self.bash(command), "deny", command)

    def test_sb_review_lookalikes_are_allowed(self):
        for command in ("sb search review", "echo review sb", "grep -rn 'sb review' docs/",
                        "python3 -m json.tool review.json", "bash -c 'sb lint'",
                        "echo $(sb search review)", "bash -lc 'ls review'"):
            self.assertEqual(self.bash(command), "allow", command)

    # H2: an empty old_string creates the file
    def test_edit_with_empty_old_string_on_a_missing_note_applies_new_note_rules(self):
        bad = "---\ntitle: x\norigin: agent\nreviewed: 2026-01-01\n---\nx"
        for path in ("wiki/Resources/New.md",):
            self.assertEqual(self.kind("Edit", path, old_string="", new_string=bad), "deny")
            self.assertEqual(self.kind("MultiEdit", path,
                                       edits=[{"old_string": "", "new_string": bad}]), "deny")
            self.assertEqual(self.kind("Edit", path, old_string="",
                                       new_string=note("N", origin="human")), "deny")
            self.assertEqual(self.kind("Edit", path, old_string="", new_string=AGENT), "allow")
            self.assertEqual(self.kind("MultiEdit", path,
                                       edits=[{"old_string": "", "new_string": AGENT},
                                              {"old_string": "agente", "new_string": "robo"}]), "allow")

    def test_edit_with_empty_old_string_on_an_empty_note_applies_new_note_rules(self):
        (self.vault / "wiki" / "Resources" / "Empty.md").write_text("", encoding="utf-8")
        self.assertEqual(self.kind("Edit", "wiki/Resources/Empty.md", old_string="",
                                   new_string=note("N", origin="human")), "deny")
        self.assertEqual(self.kind("Edit", "wiki/Resources/Empty.md", old_string="",
                                   new_string=AGENT), "allow")

    # H3: trust keys the restricted parser ignores but a YAML reader sees
    def test_new_note_with_hidden_trust_keys_is_denied(self):
        for extra in ('"reviewed": 2026-11-02', "'reviewed_hash': sha256:00", "Reviewed : 2026",
                      "reviewed :2026", '" protected ": true', "{reviewed: 2026-11-02}",
                      "{ origin: human }", '"re\\u0076iewed": 2026', "? reviewed", "REVIEWED: x",
                      "reviewed:2026"):
            content = AGENT.replace("origin: agent", "origin: agent\n" + extra)
            self.assertEqual(self.kind("Write", "wiki/Resources/N.md", content=content), "deny", extra)
            self.assertTrue(self.reason("Write", "wiki/Resources/N.md", content=content)
                            .startswith(REASON_TRUST), extra)

    def test_edit_adding_a_hidden_trust_key_to_an_existing_note_is_denied(self):
        for name, anchor in (("G.md", "origin: agent"), ("H.md", "origin: human")):
            for extra in ('"reviewed": 2026-11-02', "{reviewed: 2026-11-02}", '"protected": false'):
                self.assertEqual(self.kind("Edit", "wiki/Resources/" + name, old_string=anchor,
                                           new_string=anchor + "\n" + extra), "deny", (name, extra))

    def test_unchanged_hidden_trust_keys_do_not_block_body_edits(self):
        path = self.vault / "wiki" / "Resources" / "G.md"
        path.write_text(AGENT.replace("origin: agent", 'origin: agent\n"reviewed": x'), encoding="utf-8")
        self.assertEqual(self.kind("Edit", "wiki/Resources/G.md", old_string="Texto do agente.",
                                   new_string="Outro."), "allow")

    # H4: origin must be exactly lowercase agent
    def test_new_note_origin_is_case_sensitive(self):
        for origin in ("Agent", "AGENT"):
            content = AGENT.replace("origin: agent", "origin: " + origin)
            self.assertEqual(self.kind("Write", "wiki/Resources/N.md", content=content), "deny", origin)
            self.assertTrue(self.reason("Write", "wiki/Resources/N.md", content=content)
                            .startswith("New notes written by the agent must have origin: agent."))

    # bash: sb review
    def bash(self, command):
        out = decide({"tool_name": "Bash", "tool_input": {"command": command}}, str(self.vault))
        return out["hookSpecificOutput"]["permissionDecision"] if out else "allow"

    def test_sb_review_via_bash_is_denied(self):
        for command in ("sb review wiki/Resources/A.md", "python3 /p/bin/sb review A",
                        "/p/bin/sb review A", "cd . && sb review A", "sudo sb review A",
                        "bash -c 'sb review A'", "env X=1 sb review A", "python3 -m sb.cli review A"):
            self.assertEqual(self.bash(command), "deny", command)
        self.assertIn("! prefix", decide({"tool_name": "Bash", "tool_input": {"command": "sb review A"}},
                                         str(self.vault))["hookSpecificOutput"]["permissionDecisionReason"])

    def test_sb_other_commands_via_bash_are_allowed(self):
        for command in ("sb search review", "sb lint", "python3 /p/bin/sb lint",
                        "echo x | sb source save sha256:0011223344556677 --tool t --origin y",
                        "sb inbox done _inbox/a.md --title T", "grep review wiki/Resources/H.md"):
            self.assertEqual(self.bash(command), "allow", command)


NOTE_WRITE_REASON = ('Notes under wiki/ are written only with the Write/Edit tools, where the guard '
                     'checks trust tiers. Use Edit to append a "> [!agent]" block instead of shell '
                     'redirection.')


class BashNoteWriteTests(unittest.TestCase):
    """D33: any detectable Bash write to a note under wiki/ is denied, in every tier."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = make_vault(self.tmp.name, {
            "Resources/A.md": note("A", origin="human"),
            "Resources/Active Recall.md": note("Active Recall", origin="human", status="evergreen"),
            "Resources/G.md": note("G", origin="agent"),
            "Resources/_about.md": "folder notes\n",
        })
        self.vault = self.root.resolve()
        self.sub = self.vault / "wiki" / "Resources"

    def result(self, command, cwd=None):
        out = decide({"tool_name": "Bash", "tool_input": {"command": command}},
                     str(cwd or self.vault))
        return out["hookSpecificOutput"] if out else None

    def bash(self, command, cwd=None):
        out = self.result(command, cwd)
        return out["permissionDecision"] if out else "allow"

    def assertDenied(self, commands, cwd=None):
        for command in commands:
            self.assertEqual(self.bash(command, cwd), "deny", command)
            self.assertEqual(self.result(command, cwd)["permissionDecisionReason"],
                             NOTE_WRITE_REASON, command)

    def assertAllowed(self, commands, cwd=None):
        for command in commands:
            self.assertEqual(self.bash(command, cwd), "allow", command)

    def test_observed_haiku_bypass_is_denied(self):
        command = ('f="wiki/Resources/Active Recall.md" && [ -n "$(tail -c1 "$f")" ] && echo >> "$f"; '
                   "printf '\\n> [!agent] 2026-11-02 · url:https://x.org/a\\n> Novo fato.\\n' >> \"$f\"")
        self.assertDenied([command])

    def test_reason_is_the_exact_text(self):
        self.assertEqual(self.result("echo x >> wiki/Resources/A.md")["permissionDecisionReason"],
                         NOTE_WRITE_REASON)

    def test_output_redirections_are_denied(self):
        self.assertDenied([
            "echo x > wiki/Resources/A.md", "echo x >> wiki/Resources/A.md",
            "echo x &> wiki/Resources/A.md", "echo x &>> wiki/Resources/A.md",
            "echo x 2> wiki/Resources/A.md", "echo x 1>> wiki/Resources/A.md",
            "echo x >| wiki/Resources/A.md", "echo x>wiki/Resources/A.md",
            "echo x >>wiki/Resources/A.md", "echo x 2>&1 >> wiki/Resources/A.md",
            "echo x > wiki/Resources/New.md", "echo x > 'wiki/Resources/Active Recall.md'",
            "echo x > wiki/Resources/G.md", "echo x > ./wiki/../wiki/Resources/A.md",
            "echo x > " + str(self.vault / "wiki/Resources/A.md"),
            "cat <<EOF > wiki/Resources/A.md\nbody\nEOF",
            "echo x | cat >> wiki/Resources/A.md",
            "true && echo x >> wiki/Resources/A.md",
            "echo x > >(tee wiki/Resources/A.md)",
        ])

    def test_tee_with_any_operand_is_denied(self):
        self.assertDenied(["echo x | tee wiki/Resources/A.md", "echo x | tee -a wiki/Resources/A.md",
                           "echo x | tee /tmp/o.txt wiki/Resources/A.md",
                           "echo x | sudo tee -a wiki/Resources/A.md",
                           "echo x | env -i tee wiki/Resources/A.md"])

    def test_sed_and_perl_in_place_are_denied(self):
        self.assertDenied(["sed -i s/a/b/ wiki/Resources/A.md",
                           "sed -i.bak s/a/b/ wiki/Resources/A.md",
                           "sed --in-place s/a/b/ wiki/Resources/A.md",
                           "sed --in-place=.bak s/a/b/ wiki/Resources/A.md",
                           "sed -ni 1p wiki/Resources/A.md",
                           "sed -i -e 's/a/b/' wiki/Resources/A.md",
                           "perl -i -pe 's/a/b/' wiki/Resources/A.md",
                           "perl -pi -e 's/a/b/' wiki/Resources/A.md",
                           "perl -pi.bak -e 's/a/b/' wiki/Resources/A.md"])

    def test_copy_install_rsync_destinations_are_denied(self):
        self.assertDenied(["cp /tmp/x.md wiki/Resources/A.md", "cp -f /tmp/x.md wiki/Resources/New.md",
                           "install -m 644 /tmp/x.md wiki/Resources/A.md",
                           "rsync -a /tmp/x.md wiki/Resources/A.md",
                           "cp /tmp/x.md wiki/Resources/", "cp /tmp/x.md wiki/Resources",
                           "cp -t wiki/Resources /tmp/x.md", "cp --target-directory=wiki/Resources /tmp/x.md",
                           "cp wiki/Resources/A.md wiki/Resources/B.md"])

    def test_move_with_a_note_as_source_or_destination_is_denied(self):
        self.assertDenied(["mv wiki/Resources/A.md /tmp/a.md", "mv /tmp/a.md wiki/Resources/A.md",
                           "mv /tmp/a.md wiki/Resources/", "mv wiki/Resources/A.md wiki/Resources/B.md",
                           "mv -f wiki/Resources/A.md /tmp/"])

    def test_link_truncate_touch_dd_are_denied(self):
        self.assertDenied(["ln -s /tmp/x.md wiki/Resources/L.md", "ln wiki/Resources/A.md /tmp/h.md",
                           "truncate -s 0 wiki/Resources/A.md", "touch wiki/Resources/A.md",
                           "touch wiki/Resources/New.md", "dd if=/tmp/x of=wiki/Resources/A.md",
                           "echo x | dd of=wiki/Resources/A.md conv=notrunc"])

    def test_cd_changes_where_relative_paths_resolve(self):
        self.assertDenied(["cd wiki/Resources && echo x >> A.md", "cd wiki && tee Resources/A.md",
                           "cd wiki; cd Resources; touch A.md", "cd wiki/Resources && sed -i s/a/b/ A.md"])
        self.assertDenied(["echo x >> A.md", "cd .. && echo x >> Resources/A.md"], cwd=self.sub)
        self.assertDenied(["cd ../.. && echo x >> wiki/Resources/A.md"], cwd=self.sub)

    def test_cd_inside_a_subshell_does_not_leak(self):
        self.assertAllowed(["(cd wiki/Resources && ls); echo x > A.md"])
        self.assertDenied(["(cd wiki/Resources && echo x > A.md)"])

    def test_shell_variables_are_resolved(self):
        self.assertDenied([
            'f="wiki/Resources/A.md"; echo x >> "$f"', "f=wiki/Resources/A.md; echo x >> $f",
            "f='wiki/Resources/A.md' && echo x >> ${f}", 'd=wiki/Resources; f="$d/A.md"; tee "$f" </dev/null',
            'export f="wiki/Resources/A.md"; echo x >> $f', 'f="wiki/Resources/A.md"\necho x >> "$f"',
            "FILE=wiki/Resources/A.md sed -i s/a/b/ $FILE",
            "for f in wiki/Resources/A.md wiki/Resources/G.md; do echo x >> \"$f\"; done",
            "for f in wiki/Resources/*.md; do echo x >> \"$f\"; done",
        ])

    def test_nested_shells_and_command_substitution_are_inspected(self):
        self.assertDenied(["bash -c 'echo x >> wiki/Resources/A.md'",
                           "sh -c \"cd wiki/Resources && tee A.md\"",
                           "echo $(echo x >> wiki/Resources/A.md)", "echo `touch wiki/Resources/A.md`"])

    def test_globs_that_could_match_notes_are_denied(self):
        self.assertDenied(["tee wiki/**/*.md", "tee wiki/Resources/*.md", "sed -i s/a/b/ wiki/*/*.md",
                           "touch wiki/Resources/A.m?", "echo x | tee wiki/Resources/[A-G]*.md",
                           "echo x | tee wiki/Resources/{A,B}.md", "cp /tmp/x.md wiki/Resources/*.md"])
        self.assertDenied(["tee *.md", "sed -i s/a/b/ *.md", "echo x > *.md"], cwd=self.sub)

    def test_reads_and_other_paths_are_allowed(self):
        self.assertAllowed([
            "echo x > _inbox/x.md", "echo x >> _inbox/_done/x.md", "echo x > _index.md",
            "cat wiki/Resources/A.md", "grep -rn foo wiki/", "grep -n foo wiki/Resources/A.md > /tmp/o.txt",
            'sb search "x" > /tmp/out.json', "sb links --suggest wiki/Resources/A.md",
            "ls wiki/*.md wiki/Resources/*.md", "head -5 wiki/Resources/A.md | wc -l",
            "sed s/a/b/ wiki/Resources/A.md", "sed -n 1p wiki/Resources/A.md",
            "cp wiki/Resources/A.md /tmp/a.md", "cp wiki/Resources/*.md /tmp/",
            "echo 'echo x >> wiki/Resources/A.md'", 'printf "%s" "a > wiki/Resources/A.md"',
            "echo x > wiki/Resources/notes.txt",
            "echo x > wiki/Resources/d.excalidraw.md", "echo x > /tmp/wiki/Resources/A.md",
            "tee /tmp/o.txt < wiki/Resources/A.md", "cat <<EOF > /tmp/o.txt\necho x >> wiki/Resources/A.md\nEOF",
            "diff wiki/Resources/A.md wiki/Resources/G.md", "mkdir -p wiki/NewFolder",
            "chmod 644 wiki/Resources/A.md", "echo 'unterminated",
        ])
        self.assertAllowed(["ls *.md", "tee /tmp/o.txt"], cwd=self.sub)

    def test_deletion_keeps_the_v01_ask(self):
        for command in ("rm wiki/Resources/A.md", "git rm wiki/Resources/A.md", "rm -rf wiki"):
            self.assertEqual(self.bash(command), "ask", command)

    def test_protected_paths_keep_the_v01_reason(self):
        out = self.result("echo x >> _raw/a.md")
        self.assertEqual(out["permissionDecision"], "deny")
        self.assertIn("_raw/a.md is protected", out["permissionDecisionReason"])

    def test_sb_review_is_still_denied(self):
        self.assertIn("! prefix", self.result("sb review wiki/Resources/A.md")["permissionDecisionReason"])


UNRESOLVED = "second-brain cannot resolve this write target; confirm with the user."
INTERPRETER_REASON = ("This interpreter command may modify notes; notes are written only with "
                      "Write/Edit. Confirm with the user.")


class BashHardeningTests(unittest.TestCase):
    """M5, M6: unresolvable targets ask; find, xargs, git, curl, tar, editors and interpreters."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = make_vault(self.tmp.name, {
            "Resources/A.md": note("A", origin="human"),
            "Resources/G.md": note("G", origin="agent"),
        })
        self.vault = self.root.resolve()
        (self.vault / "_raw" / "a.pdf").write_text("x", encoding="utf-8")
        (self.vault / "wiki" / "Resources" / "pic.png").write_text("x", encoding="utf-8")
        self.sub = self.vault / "wiki" / "Resources"

    def result(self, command, cwd=None):
        out = decide({"tool_name": "Bash", "tool_input": {"command": command}}, str(cwd or self.vault))
        return out["hookSpecificOutput"] if out else None

    def kinds(self, commands, expected, reason=None, cwd=None):
        for command in commands:
            out = self.result(command, cwd)
            self.assertEqual(out["permissionDecision"] if out else "allow", expected, command)
            if reason and out:
                self.assertEqual(out["permissionDecisionReason"], reason, command)

    # M5
    def test_unresolved_write_targets_ask(self):
        self.kinds(["echo x > $UNSET", 'echo x > "${F}/A.md"', "echo x > $(echo A).md",
                    "tee `echo A`.md", "cd $D && echo x > A.md", 'rm "$f"', "cp /tmp/x $DEST",
                    "echo x > $'wiki/Resources/A.md'", "touch $1.md", "cd `pwd`/x; echo y > A.md",
                    "echo x >> /tmp/$$.log"], "ask", UNRESOLVED)

    def test_resolvable_and_read_only_variables_do_not_ask(self):
        self.kinds(["echo $VAR > /tmp/o.txt", "ls $HOME", "echo $(date) > /dev/null",
                    "cat $F | wc -l", "f=/tmp/x; echo y > $f"], "allow")
        self.assertEqual(self.result("echo x > $PWD/wiki/Resources/A.md")["permissionDecision"], "deny")

    def test_bash_folds_case_on_a_case_insensitive_vault(self):
        from unittest import mock
        self.assertEqual(self.kinds(["echo x > WIKI/Resources/A.md", "rm _RAW/a.pdf"], "allow"), None)
        with mock.patch("sb.guard._case_insensitive", return_value=True):
            self.kinds(["echo x > WIKI/Resources/A.md", "tee Wiki/Resources/new.md"],
                       "deny", NOTE_WRITE_REASON)
            self.kinds(["rm _RAW/a.pdf", "echo x > Claude.md"], "deny")
            self.kinds(["rm Wiki/Resources/A.md"], "ask")

    def test_deny_wins_over_ask(self):
        self.assertEqual(self.result("echo x > $UNSET; echo y > _raw/a.pdf")["permissionDecision"], "deny")

    # M6 shells and eval
    def test_c_flags_and_eval_are_inspected(self):
        self.kinds(["bash -lc 'echo x > wiki/Resources/A.md'", "sh -ec 'echo x > wiki/Resources/A.md'",
                    "zsh -c 'cd wiki/Resources && tee A.md'", "eval 'echo x > wiki/Resources/A.md'",
                    "eval echo x '>' wiki/Resources/A.md", "timeout 5 bash -c 'echo x > wiki/Resources/A.md'",
                    "sudo -u bob sed -i s/a/b/ wiki/Resources/A.md",
                    "nice -n 5 tee wiki/Resources/A.md", "stdbuf -oL tee wiki/Resources/A.md",
                    "env -i X=1 tee wiki/Resources/A.md", "timeout 5 touch wiki/Resources/A.md"],
                   "deny", NOTE_WRITE_REASON)

    # find
    def test_find_exec_is_scanned_with_the_found_paths(self):
        self.kinds(["find wiki -name '*.md' -exec sed -i s/a/b/ {} +",
                    "find wiki/Resources -name A.md -exec tee {} \;",
                    "find wiki -name '*.md' -execdir sed -i s/a/b/ {} \;",
                    "find wiki -name '*.md' -exec sh -c 'echo x > wiki/Resources/A.md' _ {} \;",
                    "find wiki -fprint wiki/Resources/A.md"], "deny", NOTE_WRITE_REASON)
        self.kinds(["find . -name '*.md' -exec sed -i s/a/b/ {} +"], "deny")    # the root holds wiki/ and _raw/
        self.kinds(["find wiki -name '*.md' -exec grep foo {} +", "find wiki -name '*.md'",
                    "find wiki -name pic.png -exec chmod 644 {} \;",
                    "find wiki -name '*.md' -exec cp {} /tmp/ \;", "find _inbox -name x -delete",
                    "find wiki -type f -exec wc -l {} +"], "allow")

    def test_find_exec_unresolved_commands_ask(self):
        self.kinds(["find wiki -exec sh -c 'echo x > \"$1\"' _ {} \;"], "ask", UNRESOLVED)

    def test_find_delete_follows_the_deletion_rules(self):
        self.kinds(["find _raw -delete", "find _raw -name '*.pdf' -exec rm {} \;",
                    "find .claude -delete"], "deny")
        self.kinds(["find wiki -delete", "find wiki/Resources -name A.md -delete", "find . -delete",
                    "find wiki -name '*.md' -exec rm {} +"], "ask")

    # xargs
    def test_xargs_commands_are_scanned(self):
        self.kinds(["xargs rm _raw/a.pdf"], "deny")
        self.kinds(["xargs tee wiki/Resources/A.md"], "deny", NOTE_WRITE_REASON)
        self.kinds(["grep -l hello wiki/Resources/*.md | xargs sed -i s/hello/bye/",
                    "ls *.md | xargs sed -i s/a/b/", "find wiki -name '*.md' -print0 | xargs -0 rm",
                    "echo wiki/Resources/A.md | xargs -I{} tee {}",
                    "echo wiki/Resources/A.md | xargs -n1 touch", "echo _raw/a.pdf | xargs rm"],
                   "ask", UNRESOLVED)
        self.kinds(["ls | xargs sed -i s/a/b/", "echo a | xargs echo", "ls | xargs -I{} cp {} /tmp/",
                    "grep -l hello wiki/Resources/*.md | xargs grep -c x"], "allow")

    def test_xargs_arg_file_is_read(self):
        (self.vault / "list.txt").write_text("wiki/Resources/A.md\n", encoding="utf-8")
        self.kinds(["xargs -a list.txt sed -i s/a/b/"], "deny", NOTE_WRITE_REASON)

    # git
    def test_git_mv_rm_apply(self):
        self.kinds(["git mv wiki/Resources/A.md wiki/Resources/B.md", "git mv _inbox/a.md wiki/Resources/N.md",
                    "git -C wiki mv Resources/A.md Resources/B.md", "git mv _raw/a.pdf _inbox/"],
                   "deny")
        self.kinds(["git -C wiki rm Resources/A.md", "git -C wiki rm -r Resources",
                    "git -c core.x=y rm wiki/Resources/A.md"], "ask")
        self.kinds(["git -C wiki rm ../_raw/a.pdf"], "deny")
        self.kinds(["git mv _inbox/a.md _inbox/b.md", "git -C _inbox mv a.md b.md", "git status",
                    "git apply --check x.patch", "git diff"], "allow")
        self.kinds(["git apply x.patch", "git apply -p1 --index x.patch", "patch -p1 < x.patch",
                    "cat x.patch | patch -p0"], "ask", UNRESOLVED)
        self.kinds(["patch --dry-run -p1 < x.patch"], "allow")
        self.kinds(["patch wiki/Resources/A.md < x.patch"], "deny")

    # downloads and archives
    def test_download_and_extract_targets(self):
        self.kinds(["curl -o wiki/Resources/A.md http://x", "curl -sL http://x --output wiki/Resources/New.md",
                    "curl -owiki/Resources/A.md http://x", "wget -O wiki/Resources/A.md http://x",
                    "wget --output-document=wiki/Resources/A.md http://x",
                    "curl --output=wiki/Resources/A.md http://x"], "deny", NOTE_WRITE_REASON)
        self.kinds(["curl -o _raw/a.pdf http://x", "tar -xf a.tar -C _raw", "unzip a.zip -d _raw"], "deny")
        self.kinds(["wget -P wiki/Resources http://x", "tar -xf a.tar -C wiki/Resources",
                    "tar xzf a.tgz --directory=wiki", "unzip a.zip -d wiki/Resources",
                    "tar -C wiki/Resources -xf a.tar", "unzip -o a.zip -d wiki"], "ask")
        self.kinds(["curl -o /tmp/x http://x", "curl -o wiki/Resources/n.png http://x",
                    "wget -O- http://x", "tar -czf /tmp/a.tgz -C wiki/Resources .",
                    "unzip -l a.zip", "tar -xf a.tar -C /tmp", "curl http://x | tar -xz -C /tmp"], "allow")

    # editors and interpreters
    def test_scripted_editors_are_denied_or_ask(self):
        self.kinds(["ex -sc '%s/a/b/|x' wiki/Resources/A.md", "vim -es wiki/Resources/A.md",
                    "ed -s wiki/Resources/A.md <<< w", "vim -Es -c 'wq' wiki/Resources/A.md"],
                   "deny", NOTE_WRITE_REASON)
        self.kinds(["ed -s <<'EOF'\nr wiki/Resources/A.md\nEOF", "ex -s <<< 'w wiki/Resources/B.md'"],
                   "ask", UNRESOLVED)
        self.kinds(["ed -s /tmp/x <<< w", "vim -es /tmp/x"], "allow")

    def test_interpreters_that_mention_notes_ask(self):
        self.kinds(["python3 -c \"open('wiki/Resources/A.md','w').write('x')\"",
                    "python -c \"import pathlib; pathlib.Path('a.md').write_text('x')\"",
                    "python3 - <<EOF\nopen('wiki/Resources/A.md','w')\nEOF",
                    "node -e \"require('fs').writeFileSync('wiki/a.md','')\"",
                    "perl -e 'open F, \">wiki/Resources/A.md\"'", "ruby -e 'File.write(\"x.md\", 1)'",
                    "deno eval \"Deno.writeTextFileSync('wiki/a.md','')\"",
                    "bun -e \"Bun.write('wiki/a.md','')\"",
                    "echo \"open('wiki/a.md','w')\" | python3", "python3.11 -c \"open('wiki/a.md','w')\"",
                    "timeout 5 python3 -c \"open('wiki/a.md','w')\""],
                   "ask", INTERPRETER_REASON)
        self.kinds(["python3 -c 'print(1)'", "python3 script.py", "python3 -m sb.cli lint wiki/",
                    "python3 /p/bin/sb search x.md", "node app.js wiki/", "echo hi | python3 -c 'import sys'",
                    "perl -ne 'print' /tmp/x.txt"], "allow")


class BashVaultFromTargetTests(unittest.TestCase):
    """M7: the vault comes from the target path, not only from the cwd."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        os.mkdir(self.tmp.name + "/v")
        self.vault = make_vault(self.tmp.name + "/v", {"Resources/A.md": note("A", origin="human")}).resolve()
        self.elsewhere = tempfile.mkdtemp()
        self.addCleanup(os.rmdir, self.elsewhere)

    def kind(self, tool, **tool_input):
        out = decide({"tool_name": tool, "tool_input": tool_input}, self.elsewhere)
        return out["hookSpecificOutput"]["permissionDecision"] if out else "allow"

    def test_write_tools_outside_the_vault_cwd_are_guarded(self):
        self.assertEqual(self.kind("Write", file_path=str(self.vault / "_raw" / "a.md"), content="x"), "deny")
        self.assertEqual(self.kind("Write", file_path=str(self.vault / "CLAUDE.md"), content="x"), "deny")
        self.assertEqual(self.kind("Write", file_path=str(self.vault / "wiki/Resources/N.md"),
                                   content=note("N", origin="human")), "deny")
        self.assertEqual(self.kind("Write", file_path=str(self.vault / "wiki/Resources/N.md"),
                                   content=note("N", origin="agent")), "allow")
        self.assertEqual(self.kind("Edit", file_path=str(self.vault / "wiki/Resources/A.md"),
                                   old_string="A summary.", new_string="x"), "ask")
        self.assertEqual(self.kind("NotebookEdit", notebook_path=str(self.vault / "_raw" / "n.ipynb"),
                                   new_source="x"), "deny")
        self.assertEqual(self.kind("Write", file_path=self.elsewhere + "/x.md", content="x"), "allow")

    def test_bash_absolute_targets_outside_the_vault_cwd_are_guarded(self):
        v = str(self.vault)
        def bash(command):
            return self.kind("Bash", command=command)
        self.assertEqual(bash("echo x > %s/wiki/Resources/A.md" % v), "deny")
        self.assertEqual(bash("rm %s/_raw/a.pdf" % v), "deny")
        self.assertEqual(bash("rm %s/wiki/Resources/A.md" % v), "ask")
        self.assertEqual(bash("cd %s/wiki/Resources && tee A.md" % v), "deny")
        self.assertEqual(bash("cat %s/wiki/Resources/A.md" % v), "allow")
        self.assertEqual(bash("echo x > $UNSET"), "allow")             # cwd is not in a vault
        self.assertEqual(bash("echo x > /tmp/zz-not-a-vault"), "allow")

    def test_hook_script_stays_closed_when_the_target_is_in_a_vault(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location("sb_guard_hook", str(PLUGIN / "hooks" / "guard.py"))
        hook = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(hook)
        event = {"tool_name": "Write", "tool_input": {"file_path": str(self.vault / "wiki" / "x.md")}}
        self.assertTrue(any(hook.in_vault(s) for s in hook.starts(event, self.elsewhere)))
        self.assertFalse(any(hook.in_vault(s) for s in hook.starts(
            {"tool_name": "Write", "tool_input": {"file_path": self.elsewhere + "/x"}}, self.elsewhere)))



ABOUT = "---\ndescription: Notes.\nprotected: false\n---\n## Conventions\nKeep short.\n"
ABOUT_PROTECTED = ABOUT.replace("protected: false", "protected: true")
ABOUT_REASON_ASK = ("_about.md describes a folder and is edited by the human; confirm this change "
                    "with the user.")


class AboutGuardTests(unittest.TestCase):
    """D34: _about.md is guarded; its `protected` key is human-only."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = make_vault(self.tmp.name, {"Resources/A.md": note("A"),
                                               "Resources/_about.md": ABOUT})
        self.vault = self.root.resolve()

    def result(self, tool, path, **tool_input):
        tool_input["file_path"] = path
        out = decide({"tool_name": tool, "tool_input": tool_input}, str(self.vault))
        return out["hookSpecificOutput"] if out else None

    def kind(self, tool, path, **tool_input):
        out = self.result(tool, path, **tool_input)
        return out["permissionDecision"] if out else "allow"

    def test_changing_protected_is_denied(self):
        path = "wiki/Resources/_about.md"
        cases = [("Write", dict(content=ABOUT_PROTECTED)),
                 ("Edit", dict(old_string="protected: false", new_string="protected: true")),
                 ("MultiEdit", dict(edits=[{"old_string": "protected: false",
                                            "new_string": "protected: true"}])),
                 ("Edit", dict(old_string="protected: false\n", new_string="")),
                 ("Write", dict(content=ABOUT_PROTECTED.replace("protected: true",
                                                               "protected: true\nprotected: false")))]
        for tool, args in cases:
            self.assertEqual(self.kind(tool, path, **args), "deny", (tool, args))
            self.assertTrue(self.result(tool, path, **args)["permissionDecisionReason"].startswith(
                "Only the human sets trust fields (reviewed, reviewed_hash, protected, origin)."))

    def test_removing_protection_is_denied(self):
        (self.vault / "wiki/Resources/_about.md").write_text(ABOUT_PROTECTED, encoding="utf-8")
        self.assertEqual(self.kind("Write", "wiki/Resources/_about.md", content=ABOUT), "deny")

    def test_other_changes_to_an_existing_about_ask(self):
        path = "wiki/Resources/_about.md"
        for tool, args in (("Write", dict(content=ABOUT.replace("Keep short.", "Anything."))),
                           ("Edit", dict(old_string="Notes.", new_string="Other.")),
                           ("MultiEdit", dict(edits=[{"old_string": "Keep", "new_string": "Stay"}]))):
            self.assertEqual(self.kind(tool, path, **args), "ask", (tool, args))
            self.assertEqual(self.result(tool, path, **args)["permissionDecisionReason"],
                             ABOUT_REASON_ASK)

    def test_unchanged_content_is_allowed(self):
        self.assertEqual(self.kind("Write", "wiki/Resources/_about.md", content=ABOUT), "allow")

    def test_new_about_without_protected_is_allowed(self):
        self.assertEqual(self.kind("Write", "wiki/Archive/_about.md",
                                   content="---\ndescription: Old.\n---\n"), "allow")
        self.assertEqual(self.kind("Write", "wiki/Archive/_about.md", content="no frontmatter\n"),
                         "allow")

    def test_new_about_with_protected_true_is_denied(self):
        for value in ("true", "yes", "True"):
            content = "---\ndescription: Old.\nprotected: %s\n---\n" % value
            self.assertEqual(self.kind("Write", "wiki/Archive/_about.md", content=content), "deny")
            self.assertTrue(self.result("Write", "wiki/Archive/_about.md", content=content)[
                "permissionDecisionReason"].startswith("Only the human sets trust fields"))

    def test_new_about_with_protected_false_is_allowed(self):
        self.assertEqual(self.kind("Write", "wiki/Archive/_about.md", content=ABOUT), "allow")

    def test_root_about_is_guarded_too(self):
        (self.vault / "wiki/_about.md").write_text(ABOUT, encoding="utf-8")
        self.assertEqual(self.kind("Write", "wiki/_about.md", content=ABOUT_PROTECTED), "deny")

    def test_edit_of_a_missing_about_is_allowed(self):
        self.assertEqual(self.kind("Edit", "wiki/Archive/_about.md", old_string="a", new_string="b"),
                         "allow")

    def test_hidden_protected_keys_in_about_are_denied(self):
        for extra in ('"protected": true', "{protected: true}", "'protected' : true", "PROTECTED :true"):
            content = "---\ndescription: Notes.\n%s\n---\n" % extra
            self.assertEqual(self.kind("Write", "wiki/Resources/New/_about.md", content=content),
                             "deny", extra)
            self.assertEqual(self.kind("Edit", "wiki/Resources/_about.md", old_string="protected: false",
                                       new_string="protected: false\n" + extra), "deny", extra)

    def test_undecodable_about_asks(self):
        (self.vault / "wiki" / "Resources" / "_about.md").write_bytes(b"---\ndescription: caf\xe9\n---\n")
        self.assertEqual(self.kind("Write", "wiki/Resources/_about.md", content=ABOUT), "ask")

    def test_bash_writes_to_about_are_denied(self):
        for command in ("echo x > wiki/Resources/_about.md", "echo x >> wiki/Resources/_about.md",
                        "sed -i s/false/true/ wiki/Resources/_about.md",
                        "tee wiki/Resources/_about.md", "cp /tmp/x wiki/Resources/_about.md",
                        "cp /tmp/x wiki/Resources/", "mv /tmp/_about.md wiki/Resources/",
                        "printf 'protected: true' >> wiki/Resources/_about.md"):
            out = decide({"tool_name": "Bash", "tool_input": {"command": command}}, str(self.vault))
            if command == "cp /tmp/x wiki/Resources/":
                self.assertIsNone(out, command)      # copies /tmp/x, not an _about.md
                continue
            self.assertEqual(out["hookSpecificOutput"]["permissionDecision"], "deny", command)
            self.assertEqual(out["hookSpecificOutput"]["permissionDecisionReason"],
                             NOTE_WRITE_REASON, command)

    def test_bash_reads_of_about_are_allowed(self):
        for command in ("cat wiki/Resources/_about.md", "grep protected wiki/Resources/_about.md",
                        "cp wiki/Resources/_about.md /tmp/a.md", "sb tree"):
            self.assertIsNone(decide({"tool_name": "Bash", "tool_input": {"command": command}},
                                     str(self.vault)), command)


SHELL_STDIN = ("A shell is fed a script the guard cannot read here; confirm with the user. "
               "Notes are written only with Write/Edit.")
REVIEW = ("`sb review` records a human review. The user runs it in a terminal or with "
          "the ! prefix.")


class Round2Base(unittest.TestCase):
    """Second security review: shared vault and helpers."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = make_vault(self.tmp.name, {
            "Resources/A.md": note("A", origin="human"),
            "Resources/G.md": note("G", origin="agent"),
            "Resources/Sub/B.md": note("B", origin="human"),
        })
        self.vault = self.root.resolve()
        self.sub = self.vault / "wiki" / "Resources"

    def result(self, command, cwd=None):
        out = decide({"tool_name": "Bash", "tool_input": {"command": command}}, str(cwd or self.vault))
        return out["hookSpecificOutput"] if out else None

    def kinds(self, commands, expected, reason=None, cwd=None):
        for command in commands:
            out = self.result(command, cwd)
            self.assertEqual(out["permissionDecision"] if out else "allow", expected, command)
            if reason and out:
                self.assertEqual(out["permissionDecisionReason"], reason, command)


class BashShellInputTests(Round2Base):
    """Item 2: shells fed through stdin or a string, and sb with an unresolved subcommand."""

    def test_sb_review_through_stdin_is_denied(self):
        self.kinds(["sh <<< 'sb review A'", "bash <<< 'sb review A'", "bash -s <<< 'sb review A'",
                    "echo 'sb review A' | sh", "echo 'sb review A' | bash -s",
                    "echo 'sb review A' | bash", "printf 'sb review A' | sh -",
                    "printf '%s\\n' 'sb review A' | sh", "printf 'sb\\x20review A' | sh",
                    "cat <<EOF | sh\nsb review A\nEOF", "cat <<< 'sb review A' | sh",
                    "echo 'sb review A' | sudo bash", ". /dev/stdin <<< 'sb review A'",
                    "echo 'sb review A' | timeout 5 bash -s"], "deny", REVIEW)

    def test_note_writes_through_stdin_are_denied(self):
        w = "echo x > wiki/Resources/A.md"
        self.kinds(["echo '%s' | sh" % w, "sh <<< '%s'" % w, "cat <<EOF | sh\n%s\nEOF" % w,
                    "printf '%s\\n' | sh" % w, "echo '%s' | bash -s" % w], "deny", NOTE_WRITE_REASON)

    def test_a_shell_fed_something_not_literal_asks(self):
        self.kinds(["curl http://x.org/i | sh", "cat install.sh | bash", "echo $(cat f) | sh",
                    'sh <<< "$CMD"', "grep x f | bash -s", "echo 'a' | tee /dev/stderr | sh"],
                   "ask", SHELL_STDIN)

    def test_a_shell_fed_a_harmless_literal_is_allowed(self):
        self.kinds(["echo hello | sh", "sh <<< 'ls wiki'", "cat <<EOF | sh\nls\nEOF",
                    "ls | grep bash", "cat f | grep sh", "echo bash", "echo x | grep -c sh",
                    "bash script.sh", "echo x | bash script.sh", "sh -c 'ls'"], "allow")

    def test_command_strings_carried_by_other_programs_are_scanned(self):
        review = ["ssh localhost 'sb review A'", "ssh -p 22 -i key host sb review A",
                  "su -c 'sb review A'", "su user -c 'sb review A'", "script -c 'sb review A' out",
                  "tmux new 'sb review A'", "tmux new-session -d -s x 'sb review A'",
                  "env -S 'sb review A'", "env -S'sb review A'", "env --split-string='sb review A'",
                  "trap 'sb review A' EXIT", "watch sb review A", "watch -n 5 'sb review A'",
                  "nohup sh -c 'sb review A'", "timeout 5 ssh h 'sb review A'"]
        self.kinds(review, "deny", REVIEW)
        write = "echo x > wiki/Resources/A.md"
        self.kinds(["ssh h '%s'" % write, "su -c '%s'" % write, "tmux new '%s'" % write,
                    "trap '%s' EXIT" % write, "watch '%s'" % write, "env -S '%s'" % write],
                   "deny", NOTE_WRITE_REASON)

    def test_command_strings_not_literal_ask_when_they_mention_a_protected_place(self):
        self.kinds(['ssh host "$CMD"; sb search x', 'su -c "$CMD" && cat wiki/Resources/A.md',
                    'trap "$H" EXIT; ls _raw', 'tmux new "$C" ; cat x.md'], "ask", UNRESOLVED)
        self.kinds(['ssh host "$CMD"', 'watch "$C"', "trap 'echo bye' EXIT"], "allow")

    def test_sb_followed_by_an_unresolved_word_asks(self):
        self.kinds(["sb $(echo review) A", "sb $X A", "sb $(printf 'rev')iew x", "sb ${S} x",
                    "timeout 5 sb $S", "sb -v $S x"], "ask", UNRESOLVED)

    def test_ordinary_sb_and_reading_commands_are_allowed(self):
        self.kinds(["sb search \"sb review\"", "sb search $Q", 'sb search "$Q"', "sb lint",
                    "sb source add a.pdf", "sb inbox done x", "sb log ingest t", "sb index --write",
                    "cat wiki/Resources/A.md", 'grep "sb review" wiki/Resources/A.md',
                    "rg foo wiki", "git status", "git commit -m 'sb review'",
                    "find wiki -name '*.md'", "ssh host ls", "tmux ls", "watch -n 5 ls",
                    "env FOO=1 ls"], "allow")


class GuardScriptTests(unittest.TestCase):
    script = str(PLUGIN / "hooks" / "guard.py")

    def run_script(self, stdin, cwd):
        return subprocess.run([sys.executable, self.script], input=stdin, cwd=cwd,
                              capture_output=True, text=True)

    def test_script_prints_a_deny_decision(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = make_vault(tmp)
            event = json.dumps({"cwd": str(root), "tool_name": "Write",
                                "tool_input": {"file_path": "_raw/a.md"}})
            done = self.run_script(event, root)
        self.assertEqual(done.returncode, 0)
        self.assertEqual(json.loads(done.stdout)["hookSpecificOutput"]["permissionDecision"], "deny")

    def test_script_is_silent_on_garbage_input_outside_a_vault(self):
        done = self.run_script("not json", tempfile.gettempdir())
        self.assertEqual((done.returncode, done.stdout), (0, ""))


if __name__ == "__main__":
    unittest.main()
