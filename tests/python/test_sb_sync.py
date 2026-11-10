import json
import os
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

from sb_helpers import PLUGIN, make_vault, note
from sb import autocommit, init, session, sync
from sb.vault import MARKER


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
class SquadSyncTests(unittest.TestCase):
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
        marker = self.a / MARKER           # until Task 9 rewrites sync: the old code reads "squad"
        marker.write_text(marker.read_text(encoding="utf-8").replace('"pull"', '"squad"'), encoding="utf-8")
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

    def start(self, clone, session_id="s"):
        out = session.start({"cwd": str(clone), "session_id": session_id}, str(clone))
        return out["hookSpecificOutput"]["additionalContext"]

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
        self.assertTrue(status.startswith("committed: sb: session 2026-11-02 (1 files)"), status)
        body = git(self.a, "log", "-1", "--format=%B")
        self.assertIn("Sb-Session: sess-42", body)
        self.assertIn("Sb-Files: 1", body)
        self.assertTrue(body.startswith("sb: session 2026-11-02 (1 files)\n\nSb-Session"))

    def test_enabled_needs_squad_and_toplevel(self):
        self.assertTrue(sync.enabled(self.a))
        (Path(self.tmp.name) / "local").mkdir()
        (Path(self.tmp.name) / "outer").mkdir()
        local = make_vault(Path(self.tmp.name) / "local", config={"sync": "local"})
        subprocess.run(["git", "init", "-q", str(local)], check=True)
        self.assertFalse(sync.enabled(local))
        self.assertTrue(sync.pull(local).startswith("skipped"))
        self.assertTrue(sync.push(local).startswith("skipped"))
        nested_parent = Path(self.tmp.name) / "outer"
        subprocess.run(["git", "init", "-q", str(nested_parent)], check=True)
        (nested_parent / "vault").mkdir()
        nested = make_vault(nested_parent / "vault", config={"sync": "squad"})
        self.assertFalse(sync.enabled(nested))
        self.assertTrue(sync.pull(nested).startswith("skipped"))

    def test_pull_rebases_clean_history(self):
        self.write(self.a, "Resources/FromA.md", note("FromA"))
        self.end(self.a, "a1")
        self.write(self.b, "Resources/FromB.md", note("FromB"))
        git(self.b, "add", "-A")
        git(self.b, "commit", "-q", "-m", "b local")
        self.assertEqual(sync.pull(self.b), "ok")
        self.assertTrue((self.b / "wiki/Resources/FromA.md").exists())
        self.assertEqual(git(self.b, "rev-list", "--merges", "--count", "HEAD").strip(), "0")
        self.assertEqual(git(self.b, "log", "-1", "--format=%s").strip(), "b local")
        self.assert_clean_state(self.b)

    def test_dirty_tree_is_committed_before_pull(self):
        self.write(self.a, "Resources/FromA.md", note("FromA"))
        self.end(self.a, "a1")
        self.write(self.b, "Resources/Dirty.md", note("Dirty"))
        self.assertEqual(sync.pull(self.b, session_id="b1"), "ok")
        subjects = git(self.b, "log", "--format=%s").splitlines()
        self.assertIn("sb: local changes before sync", subjects)
        self.assertTrue((self.b / "wiki/Resources/Dirty.md").exists())
        self.assertTrue((self.b / "wiki/Resources/FromA.md").exists())
        self.assertEqual(git(self.b, "status", "--porcelain"), "")
        self.assertIn("Sb-Session: b1", git(self.b, "log", "--grep", "local changes", "--format=%B"))
        self.assert_clean_state(self.b)

    def test_conflict_aborts_and_keeps_both_commits(self):
        self.write(self.a, "Resources/X.md", note("X", body="line one\nA changed\nline three"))
        self.end(self.a, "a1")
        self.write(self.b, "Resources/X.md", note("X", body="line one\nB changed\nline three"))
        git(self.b, "add", "-A")
        git(self.b, "commit", "-q", "-m", "b edit")
        self.assertEqual(sync.pull(self.b), "conflict: wiki/Resources/X.md")
        self.assert_clean_state(self.b)
        self.assertEqual(git(self.b, "log", "-1", "--format=%s").strip(), "b edit")
        self.assertIn("B changed", (self.b / "wiki/Resources/X.md").read_text(encoding="utf-8"))
        self.assertIn("sb: session", git(self.bare, "log", "main", "--format=%s"))

    def test_push_failure_is_retried_next_session(self):
        moved = self.bare.with_name("remote-away.git")
        self.bare.rename(moved)
        self.write(self.a, "Resources/Later.md", note("Later"))
        status = self.end(self.a, "a1")
        self.assertIn("push: pending", status)
        self.assertTrue(sync.pending(self.a))
        self.assertTrue((self.a / ".sb/push-pending").exists())
        moved.rename(self.bare)
        context = self.start(self.a, "a2")
        self.assertFalse((self.a / ".sb/push-pending").exists())
        self.assertIn("sync ok", context)
        self.assertIn("wiki/Resources/Later.md", self.remote_files())

    def test_conflict_shows_in_the_session_status_line(self):
        self.write(self.a, "Resources/X.md", note("X", body="line one\nA changed\nline three"))
        self.end(self.a, "a1")
        self.write(self.b, "Resources/X.md", note("X", body="line one\nB changed\nline three"))
        git(self.b, "add", "-A")
        git(self.b, "commit", "-q", "-m", "b edit")
        self.assertIn("sync conflict: wiki/Resources/X.md", self.start(self.b))
        self.assert_clean_state(self.b)

    def test_session_start_pulls(self):
        self.write(self.a, "Resources/FromA.md", note("FromA"))
        self.end(self.a, "a1")
        self.assertIn("sync ok", self.start(self.b))
        self.assertTrue((self.b / "wiki/Resources/FromA.md").exists())

    def test_session_end_hook_timeout_is_60(self):
        spec = json.loads((PLUGIN / "hooks" / "hooks.json").read_text(encoding="utf-8"))["hooks"]
        self.assertEqual(spec["SessionEnd"][0]["hooks"][0]["timeout"], 60)

    def test_session_start_hook_timeout_is_90(self):
        spec = json.loads((PLUGIN / "hooks" / "hooks.json").read_text(encoding="utf-8"))["hooks"]
        self.assertEqual(spec["SessionStart"][0]["hooks"][0]["timeout"], 90)

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

    def test_merge_in_progress_keeps_the_old_skip_message(self):
        (self.b / ".git" / "MERGE_HEAD").write_text("0" * 40 + "\n", encoding="utf-8")
        self.assertEqual(sync.pull(self.b), "skipped: merge or rebase in progress")

    def test_slow_pull_skips_the_push_retry(self):
        from unittest import mock
        self.write(self.a, "Resources/Later.md", note("Later"))
        moved = self.bare.with_name("remote-away.git")
        self.bare.rename(moved)
        self.end(self.a, "a1")                                      # push fails: push-pending
        moved.rename(self.bare)
        clock = iter([0.0, 41.0])
        with mock.patch("sb.session._clock", side_effect=lambda: next(clock)), \
                mock.patch("sb.sync.push", side_effect=AssertionError("push must not run")):
            context = self.start(self.a, "a2")
        self.assertIn("sync push pending", context)
        self.assertTrue(sync.pending(self.a))                       # still pending for the next session

    def test_fast_pull_still_retries_the_push(self):
        from unittest import mock
        self.write(self.a, "Resources/Later.md", note("Later"))
        moved = self.bare.with_name("remote-away.git")
        self.bare.rename(moved)
        self.end(self.a, "a1")
        moved.rename(self.bare)
        clock = iter([0.0, 3.0])
        with mock.patch("sb.session._clock", side_effect=lambda: next(clock)):
            self.start(self.a, "a2")
        self.assertFalse(sync.pending(self.a))

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
            if i in (5, 10, 15):
                conflicts += 1
                for name, clone in clones.items():
                    self.start(clone, "%s-%d-x" % (name, i))
                for name, clone in clones.items():
                    self.write(clone, shared, note("X", body="line one\n%s edit %d\nline three"
                                                   % (name, i)))
                    self.end(clone, "%s-%d-x" % (name, i))
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
                self.assertEqual(sync.push(self.b), "ok")
                self.assert_clean_state(self.b)
        self.assertEqual(conflicts, 3)
        for name, clone in clones.items():
            self.start(clone, "%s-final" % name)
            self.assert_clean_state(clone)
        remote = self.remote_files()
        for name in clones:
            for i in range(20):
                self.assertIn("wiki/Resources/%s-%d.md" % (name, i), remote)
        for sha in git(self.bare, "rev-list", "main").split():
            message = git(self.bare, "log", "-1", "--format=%B", sha)
            if message.startswith("sb:"):
                self.assertRegex(message, r"Sb-Session: \S+")
                self.assertRegex(message, r"Sb-Files: \d+")
        self.assertEqual(git(self.a, "rev-parse", "HEAD"), git(self.b, "rev-parse", "HEAD"))
        self.assertLess(time.time() - started, 60)


if __name__ == "__main__":
    unittest.main()
