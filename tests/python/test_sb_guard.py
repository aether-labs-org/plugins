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
        for path in ("wiki/Resources/a.md", "_index.md", "_log.md", "_inbox/x.md",
                     "wiki/sub/CLAUDE.md", "/tmp/elsewhere.txt"):
            self.assertEqual(self.verdict("Write", file_path=path), "allow", path)

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

    def test_script_fails_open_on_garbage_input(self):
        done = self.run_script("not json", tempfile.gettempdir())
        self.assertEqual((done.returncode, done.stdout), (0, ""))


if __name__ == "__main__":
    unittest.main()
