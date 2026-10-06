import inspect
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from sb_helpers import PLUGIN, make_vault, note
from sb import autocommit
from sb.postcheck import check


class PostCheckTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = make_vault(self.tmp.name, {"Resources/A.md": note("A")})

    def event(self, path):
        return {"cwd": str(self.root), "tool_name": "Write", "tool_input": {"file_path": path}}

    def test_reports_frontmatter_problems_of_a_touched_wiki_note(self):
        bad = self.root / "wiki" / "Resources" / "Bad.md"
        bad.write_text(note("Bad", summary=None), encoding="utf-8")
        out = check(self.event(str(bad)), str(self.root))
        context = out["hookSpecificOutput"]["additionalContext"]
        self.assertEqual(out["hookSpecificOutput"]["hookEventName"], "PostToolUse")
        self.assertIn("SB102", context)
        self.assertIn("wiki/Resources/Bad.md", context)

    def test_silent_for_valid_notes_other_files_and_non_vaults(self):
        self.assertIsNone(check(self.event("wiki/Resources/A.md"), str(self.root)))
        self.assertIsNone(check(self.event("_inbox/x.md"), str(self.root)))
        self.assertIsNone(check(self.event("wiki/Resources/notes.txt"), str(self.root)))
        outside = tempfile.gettempdir()
        self.assertIsNone(check({"tool_input": {"file_path": "wiki/a.md"}}, outside))


@unittest.skipUnless(shutil.which("git"), "git not installed")
class AutoCommitTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = make_vault(self.tmp.name, {"Resources/A.md": note("A")})
        self.git("init", "-q")
        self.git("config", "user.email", "t@example.com")
        self.git("config", "user.name", "Test")
        self.git("add", "-A")
        self.git("commit", "-q", "-m", "init")

    def git(self, *args):
        return subprocess.run(["git", "-C", str(self.root), *args], capture_output=True, text=True)

    def commits(self):
        return int(self.git("rev-list", "--count", "HEAD").stdout.strip())

    def dirty(self):
        (self.root / "wiki" / "Resources" / "New.md").write_text(note("New"), encoding="utf-8")

    def test_commits_changes_by_default_when_env_is_unset(self):
        self.dirty()
        status = autocommit.run(str(self.root), env={}, today="2026-10-01")
        self.assertEqual(status, "committed: sb: session 2026-10-01 (1 files)")
        self.assertEqual(self.commits(), 2)
        self.assertEqual(self.git("status", "--porcelain").stdout, "")

    def test_disabled_by_userconfig(self):
        for value in ("false", "FALSE", "0", "no", "off"):
            self.dirty()
            status = autocommit.run(str(self.root), env={"CLAUDE_PLUGIN_OPTION_AUTO_COMMIT": value})
            self.assertEqual(status, "skipped: auto_commit is off", value)
        self.assertEqual(self.commits(), 1)

    def test_explicitly_enabled(self):
        self.dirty()
        status = autocommit.run(str(self.root), env={"CLAUDE_PLUGIN_OPTION_AUTO_COMMIT": "true"})
        self.assertTrue(status.startswith("committed:"))

    def test_no_changes(self):
        self.assertEqual(autocommit.run(str(self.root), env={}), "skipped: no changes")
        self.assertEqual(self.commits(), 1)

    def test_no_git_directory(self):
        shutil.rmtree(self.root / ".git")
        self.assertEqual(autocommit.run(str(self.root), env={}), "skipped: no .git")

    def test_not_a_vault(self):
        self.assertEqual(autocommit.run(tempfile.gettempdir(), env={}), "skipped: not a vault")

    def test_merge_in_progress(self):
        self.dirty()
        (self.root / ".git" / "MERGE_HEAD").write_text("0" * 40 + "\n", encoding="utf-8")
        self.assertEqual(autocommit.run(str(self.root), env={}),
                         "skipped: merge or rebase in progress")
        self.assertEqual(self.commits(), 1)

    def test_commit_failure_is_reported_not_raised(self):
        self.dirty()
        self.git("config", "--unset", "user.email")
        self.git("config", "user.useConfigOnly", "true")
        old = os.environ.copy()
        os.environ.update({"GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_SYSTEM": os.devnull,
                           "HOME": self.tmp.name})
        for key in ("GIT_AUTHOR_EMAIL", "GIT_COMMITTER_EMAIL", "EMAIL"):
            os.environ.pop(key, None)
        self.addCleanup(lambda: (os.environ.clear(), os.environ.update(old)))
        self.assertTrue(autocommit.run(str(self.root), env={}).startswith("skipped: git commit failed"))

    def test_source_never_pushes(self):
        self.assertNotIn("push", inspect.getsource(autocommit))


class HookScriptTests(unittest.TestCase):
    def run_script(self, name, stdin, cwd, env=None):
        return subprocess.run([sys.executable, str(PLUGIN / "hooks" / name)], input=stdin,
                              cwd=cwd, capture_output=True, text=True, env=env)

    def test_validate_note_script_outputs_context(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = make_vault(tmp, {"R/Bad.md": note("Bad", summary=None)})
            event = json.dumps({"cwd": str(root), "tool_name": "Edit",
                                "tool_input": {"file_path": str(root / "wiki/R/Bad.md")}})
            done = self.run_script("validate_note.py", event, root)
        self.assertEqual(done.returncode, 0)
        self.assertIn("SB102", json.loads(done.stdout)["hookSpecificOutput"]["additionalContext"])

    def test_validate_note_script_fails_open(self):
        done = self.run_script("validate_note.py", "garbage", tempfile.gettempdir())
        self.assertEqual((done.returncode, done.stdout), (0, ""))

    def test_autocommit_script_always_exits_zero(self):
        done = self.run_script("autocommit.py", "{}", tempfile.gettempdir())
        self.assertEqual(done.returncode, 0)

    def test_hooks_json_wires_the_three_events(self):
        spec = json.loads((PLUGIN / "hooks" / "hooks.json").read_text(encoding="utf-8"))["hooks"]
        self.assertEqual(sorted(spec), ["PostToolUse", "PreToolUse", "SessionEnd"])
        self.assertEqual(spec["PreToolUse"][0]["matcher"], "Write|Edit|MultiEdit|NotebookEdit|Bash")
        self.assertEqual(spec["PostToolUse"][0]["matcher"], "Write|Edit|MultiEdit")
        self.assertNotIn("matcher", spec["SessionEnd"][0])
        for event in spec.values():
            for hook in event[0]["hooks"]:
                self.assertIn("${CLAUDE_PLUGIN_ROOT}/hooks/", hook["command"])
                script = hook["command"].split("/hooks/")[1].rstrip('"')
                self.assertTrue((PLUGIN / "hooks" / script).is_file(), script)


if __name__ == "__main__":
    unittest.main()
