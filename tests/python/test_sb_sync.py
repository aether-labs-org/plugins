import json
import os
import re
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

from sb_helpers import PLUGIN, make_vault, note
from sb import autocommit, init, session, sync

LIB = PLUGIN / "lib" / "sb"


def git(path, *args, check=True):
    done = subprocess.run(["git", "-C", str(path), *args], capture_output=True, text=True)
    if check and done.returncode != 0:
        raise AssertionError("git %s failed: %s" % (" ".join(args), done.stderr))
    return done.stdout


def configure(path, who):
    git(path, "config", "user.email", "%s@example.com" % who)
    git(path, "config", "user.name", who)
    git(path, "config", "commit.gpgsign", "false")


@unittest.skipUnless(shutil.which("git"), "git not installed")
class PullSyncTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        base = Path(self.tmp.name)
        self.bare = base / "remote.git"
        subprocess.run(["git", "init", "-q", "--bare", str(self.bare)], check=True)
        subprocess.run(["git", "-C", str(self.bare), "symbolic-ref", "HEAD", "refs/heads/main"],
                       check=True)
        self.a = base / "A"
        init.run(self.a, language="en", git=True, remote=str(self.bare))
        git(self.a, "symbolic-ref", "HEAD", "refs/heads/main")
        configure(self.a, "ana")
        self.write(self.a, "Resources/X.md", note("X", body="line one\nline two\nline three"))
        git(self.a, "add", "-A")
        git(self.a, "commit", "-q", "-m", "init vault")
        git(self.a, "push", "-q", "-u", "origin", "main")
        self.b = base / "B"
        subprocess.run(["git", "clone", "-q", str(self.bare), str(self.b)], check=True)
        configure(self.b, "bruno")

    def write(self, clone, rel, text):
        path = Path(clone) / "wiki" / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def end(self, clone, session_id):
        return autocommit.run(str(clone), env={}, today="2026-11-02", session_id=session_id)

    def start(self, clone, session_id="s", source="startup"):
        out = session.start({"cwd": str(clone), "session_id": session_id, "source": source},
                            str(clone), {})
        return out["hookSpecificOutput"]["additionalContext"]

    def push_by_hand(self, clone):
        git(clone, "push", "-q")

    def remote_files(self):
        return git(self.bare, "ls-tree", "-r", "--name-only", "main").split("\n")

    def assert_clean_state(self, clone):
        gitdir = Path(clone) / ".git"
        self.assertFalse((gitdir / "rebase-merge").exists())
        self.assertFalse((gitdir / "rebase-apply").exists())
        self.assertEqual(git(clone, "stash", "list"), "")

    def test_trailers(self):
        self.write(self.a, "Resources/New.md", note("New"))
        status = self.end(self.a, "sess-42")
        self.assertEqual(status, "committed: sb: session 2026-11-02 (1 files)")
        body = git(self.a, "log", "-1", "--format=%B")
        self.assertIn("Sb-Session: sess-42", body)
        self.assertIn("Sb-Files: 1", body)
        self.assertTrue(body.startswith("sb: session 2026-11-02 (1 files)\n\nSb-Session"))

    def test_enabled_needs_pull_and_toplevel(self):
        self.assertTrue(sync.enabled(self.a))
        base = Path(self.tmp.name)
        (base / "local").mkdir()
        local = make_vault(base / "local", config={"sync": "local"})
        subprocess.run(["git", "init", "-q", str(local)], check=True)
        self.assertFalse(sync.enabled(local))
        self.assertTrue(sync.pull(local).startswith("skipped"))
        (base / "squad").mkdir()
        squad = make_vault(base / "squad", config={"sync": "squad"})   # the v0.2 value counts as local
        subprocess.run(["git", "init", "-q", str(squad)], check=True)
        self.assertFalse(sync.enabled(squad))
        outer = base / "outer"
        outer.mkdir()
        subprocess.run(["git", "init", "-q", str(outer)], check=True)
        (outer / "vault").mkdir()
        nested = make_vault(outer / "vault", config={"sync": "pull"})
        self.assertFalse(sync.enabled(nested))
        self.assertTrue(sync.pull(nested).startswith("skipped"))

    def test_pull_rebases_clean_history(self):
        self.write(self.a, "Resources/FromA.md", note("FromA"))
        self.end(self.a, "a1")
        self.push_by_hand(self.a)
        self.write(self.b, "Resources/FromB.md", note("FromB"))
        git(self.b, "add", "-A")
        git(self.b, "commit", "-q", "-m", "b local")
        self.assertEqual(sync.pull(self.b), "ok")
        self.assertTrue((self.b / "wiki/Resources/FromA.md").exists())
        self.assertEqual(git(self.b, "rev-list", "--merges", "--count", "HEAD").strip(), "0")
        self.assertEqual(git(self.b, "log", "-1", "--format=%s").strip(), "b local")
        self.assert_clean_state(self.b)

    def test_dirty_tree_is_skipped_not_committed(self):
        self.write(self.a, "Resources/FromA.md", note("FromA"))
        self.end(self.a, "a1")
        self.push_by_hand(self.a)
        self.write(self.b, "Resources/Dirty.md", note("Dirty"))
        before = git(self.b, "rev-parse", "HEAD")
        self.assertEqual(sync.pull(self.b),
                         "skipped: uncommitted changes (auto_commit is off or git commit failed)")
        self.assertEqual(git(self.b, "rev-parse", "HEAD"), before)
        self.assertIn("?? wiki/Resources/Dirty.md", git(self.b, "status", "--porcelain"))
        self.assertFalse((self.b / "wiki/Resources/FromA.md").exists())
        self.assert_clean_state(self.b)

    def test_session_start_commits_outside_changes_then_pulls(self):
        self.write(self.a, "Resources/FromA.md", note("FromA"))
        self.end(self.a, "a1")
        self.push_by_hand(self.a)
        self.write(self.b, "Resources/Dirty.md", note("Dirty"))
        context = self.start(self.b)
        self.assertIn("sync ok", context)
        subjects = git(self.b, "log", "--format=%s").splitlines()
        self.assertIn("sb: changes outside sessions (1 files)", subjects)
        self.assertTrue((self.b / "wiki/Resources/Dirty.md").exists())
        self.assertTrue((self.b / "wiki/Resources/FromA.md").exists())
        self.assertEqual(git(self.b, "status", "--porcelain"), "")
        self.assertIn("unpushed 1", context)

    def test_conflict_aborts_and_keeps_both_commits(self):
        self.write(self.a, "Resources/X.md", note("X", body="line one\nA changed\nline three"))
        self.end(self.a, "a1")
        self.push_by_hand(self.a)
        self.write(self.b, "Resources/X.md", note("X", body="line one\nB changed\nline three"))
        git(self.b, "add", "-A")
        git(self.b, "commit", "-q", "-m", "b edit")
        self.assertEqual(sync.pull(self.b), "conflict: wiki/Resources/X.md")
        self.assert_clean_state(self.b)
        self.assertEqual(git(self.b, "log", "-1", "--format=%s").strip(), "b edit")
        self.assertIn("B changed", (self.b / "wiki/Resources/X.md").read_text(encoding="utf-8"))
        self.assertIn("sb: session", git(self.bare, "log", "main", "--format=%s"))

    def test_conflict_shows_in_the_session_status_line(self):
        self.write(self.a, "Resources/X.md", note("X", body="line one\nA changed\nline three"))
        self.end(self.a, "a1")
        self.push_by_hand(self.a)
        self.write(self.b, "Resources/X.md", note("X", body="line one\nB changed\nline three"))
        git(self.b, "add", "-A")
        git(self.b, "commit", "-q", "-m", "b edit")
        self.assertIn("sync conflict: wiki/Resources/X.md", self.start(self.b))
        self.assert_clean_state(self.b)

    def test_session_start_pulls(self):
        self.write(self.a, "Resources/FromA.md", note("FromA"))
        self.end(self.a, "a1")
        self.push_by_hand(self.a)
        self.assertIn("sync ok", self.start(self.b))
        self.assertTrue((self.b / "wiki/Resources/FromA.md").exists())

    def test_unpushed_shows_in_the_status_line(self):
        self.assertNotIn("unpushed", self.start(self.a))
        self.write(self.a, "Resources/Later.md", note("Later"))
        self.end(self.a, "a1")
        self.assertIn("unpushed 1", self.start(self.a, "a2"))
        self.assertNotIn("Later", self.remote_files())
        self.push_by_hand(self.a)
        self.assertNotIn("unpushed", self.start(self.a, "a3"))
        self.assertIn("wiki/Resources/Later.md", self.remote_files())

    def test_clear_does_not_pull_or_report_unpushed(self):
        self.write(self.a, "Resources/FromA.md", note("FromA"))
        self.end(self.a, "a1")
        self.push_by_hand(self.a)
        context = self.start(self.b, source="clear")
        self.assertIn("sync not checked", context)
        self.assertFalse((self.b / "wiki/Resources/FromA.md").exists())

    def test_rebase_left_in_progress_is_reported_and_nothing_else_runs(self):
        gitdir = self.b / ".git"
        (gitdir / "rebase-merge").mkdir()
        self.write(self.b, "Resources/Dirty.md", note("Dirty"))      # must not be committed
        before = git(self.b, "rev-parse", "HEAD")
        self.assertEqual(sync.pull(self.b),
                         "conflict: rebase in progress (run git rebase --abort or finish it)")
        self.assertIn("sync conflict: rebase in progress (run git rebase --abort or finish it)",
                      self.start(self.b))
        self.assertEqual(git(self.b, "rev-parse", "HEAD"), before)
        self.assertTrue((gitdir / "rebase-merge").exists())          # left for the human
        self.assertIn("?? wiki/Resources/Dirty.md", git(self.b, "status", "--porcelain"))

    def test_merge_in_progress_is_skipped(self):
        (self.b / ".git" / "MERGE_HEAD").write_text("0" * 40 + "\n", encoding="utf-8")
        self.assertEqual(sync.pull(self.b), "skipped: merge or rebase in progress")

    def test_simulation_two_clones_twenty_sessions(self):
        started = time.time()
        clones = {"A": self.a, "B": self.b}
        shared = "Resources/X.md"
        conflicts = 0
        for i in range(20):
            for name, clone in clones.items():
                self.start(clone, "%s-%d" % (name, i))
                self.write(clone, "Resources/%s-%d.md" % (name, i), note("%s %d" % (name, i)))
                self.end(clone, "%s-%d" % (name, i))
                self.push_by_hand(clone)
            if i in (5, 10, 15):
                conflicts += 1
                for name, clone in clones.items():
                    self.start(clone, "%s-%d-x" % (name, i))
                for name, clone in clones.items():
                    self.write(clone, shared, note("X", body="line one\n%s edit %d\nline three"
                                                   % (name, i)))
                    self.end(clone, "%s-%d-x" % (name, i))
                self.push_by_hand(self.a)
                result = sync.pull(self.b)
                self.assertTrue(result.startswith("conflict: "), result)
                self.assert_clean_state(self.b)
                # the human resolves it the way git says: rebase, fix, continue, push
                subprocess.run(["git", "-C", str(self.b), "pull", "--rebase", "-q"],
                               capture_output=True)
                self.write(self.b, shared, note("X", body="line one\nresolved %d\nline three" % i))
                git(self.b, "add", "-A")
                subprocess.run(["git", "-C", str(self.b), "rebase", "--continue"],
                               capture_output=True, env=dict(os.environ, GIT_EDITOR="true"))
                self.push_by_hand(self.b)
                self.assert_clean_state(self.b)
        self.assertEqual(conflicts, 3)
        for name, clone in clones.items():
            self.start(clone, "%s-final" % name)
            self.assert_clean_state(clone)
        remote = self.remote_files()
        for name in clones:
            for i in range(20):
                self.assertIn("wiki/Resources/%s-%d.md" % (name, i), remote)
        for clone in clones.values():
            for path in (Path(clone) / "wiki").rglob("*.md"):
                self.assertNotIn("<<<<<<<", path.read_text(encoding="utf-8"), str(path))
        for sha in git(self.bare, "rev-list", "main").split():
            message = git(self.bare, "log", "-1", "--format=%B", sha)
            if message.startswith("sb: session"):
                self.assertRegex(message, r"Sb-Session: \S+")
                self.assertRegex(message, r"Sb-Files: \d+")
        self.assertEqual(git(self.a, "rev-parse", "HEAD"), git(self.b, "rev-parse", "HEAD"))
        self.assertLess(time.time() - started, 60)


class StaticSyncTests(unittest.TestCase):
    def test_no_module_runs_git_push(self):
        sources = list(LIB.glob("*.py")) + list((PLUGIN / "hooks").glob("*.py"))
        self.assertGreater(len(sources), 10)
        for path in sources:
            text = path.read_text(encoding="utf-8")
            self.assertIsNone(re.search(r"""["']push["']""", text), str(path))

    def test_removed_push_machinery_is_gone(self):
        for name in ("push", "pending", "PENDING", "PRE_SYNC_MESSAGE"):
            self.assertFalse(hasattr(sync, name), name)

    def test_hook_timeouts_and_matcher(self):
        spec = json.loads((PLUGIN / "hooks" / "hooks.json").read_text(encoding="utf-8"))["hooks"]
        self.assertEqual(spec["SessionStart"][0]["hooks"][0]["timeout"], 60)
        self.assertEqual(spec["SessionEnd"][0]["hooks"][0]["timeout"], 30)
        self.assertEqual(spec["SessionStart"][0]["matcher"], "startup|resume|clear|compact|fork")


if __name__ == "__main__":
    unittest.main()
