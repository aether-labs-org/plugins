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
