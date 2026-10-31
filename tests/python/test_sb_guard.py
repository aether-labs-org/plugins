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

    # simulation
    def test_unsimulatable_edit_is_allowed(self):
        self.assertIsNone(self.decide("Edit", "wiki/Resources/H.md",
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

    def test_multiedit_with_a_missing_old_string_is_allowed(self):
        edits = [{"old_string": "revisado", "new_string": "X"},
                 {"old_string": "ausente", "new_string": "Y"}]
        self.assertEqual(self.kind("MultiEdit", "wiki/Resources/H.md", edits=edits), "allow")

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

    # paths
    def test_non_note_paths_keep_v01_rules(self):
        self.assertEqual(self.kind("Write", "wiki/Resources/_about.md", content="x"), "allow")
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
