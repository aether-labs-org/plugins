"""Squad sync (spec 6.4, D30, D32): pull --rebase at SessionStart, push at SessionEnd.

Never `--autostash`: a dirty tree is committed first. Any failure aborts the rebase and is
reported, never resolved. Only vaults whose git top-level is the vault root take part.
"""
import os
import subprocess
from pathlib import Path

from .sanitize import clean_inline
from .vault import VaultError, load_config

PULL_TIMEOUT = 20
PUSH_TIMEOUT = 45
GIT_TIMEOUT = 30
PENDING = Path(".sb") / "push-pending"
PRE_SYNC_MESSAGE = "sb: local changes before sync"


def _git(root, *args, timeout=GIT_TIMEOUT):
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0", GIT_EDITOR="true")
    return subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True,
                          timeout=timeout, env=env)


def _first_line(done):
    text = (done.stderr or done.stdout or "").strip()
    return clean_inline(text.splitlines()[0] if text else "git failed", 200)


def enabled(root):
    """`sync == "squad"` and the git top-level is the vault root."""
    root = Path(root)
    try:
        if load_config(root).get("sync") != "squad":
            return False
        done = _git(root, "rev-parse", "--show-toplevel")
    except (VaultError, OSError, subprocess.SubprocessError):
        return False
    return done.returncode == 0 and os.path.realpath(done.stdout.strip()) == os.path.realpath(root)


def pending(root):
    return (Path(root) / PENDING).exists()


def _has_upstream(root):
    return _git(root, "rev-parse", "--abbrev-ref", "@{u}").returncode == 0


def ahead(root):
    """Commits not yet on the upstream (0 when there is no upstream)."""
    done = _git(root, "rev-list", "--count", "@{u}..HEAD")
    return int(done.stdout.strip() or 0) if done.returncode == 0 else 0


REBASE_STATES = ("rebase-merge", "rebase-apply")
REBASE_LEFT = "conflict: rebase in progress (run git rebase --abort or finish it)"


def _in_progress(root, names=None):
    from . import autocommit

    gitdir = _git(root, "rev-parse", "--absolute-git-dir")
    return gitdir.returncode == 0 and any(
        (Path(gitdir.stdout.strip()) / name).exists() for name in names or autocommit.IN_PROGRESS)


def pull(root, session_id="", env=None):
    """`ok`, `skipped: <why>` or `conflict: <comma-separated files | rebase in progress>`.
    Never raises."""
    from . import autocommit

    root = Path(root)
    try:
        if not enabled(root):
            return "skipped: not a squad vault"
        if _in_progress(root, REBASE_STATES):
            return REBASE_LEFT                # left by a killed hook: the human decides
        if _in_progress(root):
            return "skipped: merge or rebase in progress"
        if not _has_upstream(root):
            return "skipped: no upstream"
        if _git(root, "status", "--porcelain").stdout.strip():
            autocommit.run(str(root), env=env, session_id=session_id, message=PRE_SYNC_MESSAGE,
                           push=False)
            if _git(root, "status", "--porcelain").stdout.strip():
                return "skipped: uncommitted changes (auto_commit is off or git commit failed)"
        try:
            done = _git(root, "pull", "--rebase", "--no-autostash", timeout=PULL_TIMEOUT)
        except subprocess.TimeoutExpired:
            _abort_rebase(root)
            return "skipped: pull timed out"
        if done.returncode == 0:
            return "ok"
        files = _git(root, "diff", "--name-only", "--diff-filter=U").stdout.split("\n")
        files = [f for f in files if f.strip()]
        _abort_rebase(root)
        if files:
            return "conflict: " + ", ".join(files)
        return "skipped: pull failed: %s" % _first_line(done)
    except (OSError, subprocess.SubprocessError, ValueError) as exc:
        return "skipped: %s" % clean_inline(exc, 200)


def _abort_rebase(root):
    try:
        _git(root, "rebase", "--abort")
    except (OSError, subprocess.SubprocessError):
        pass


def push(root):
    """`ok`, `pending: <stderr first line>` or `skipped: <why>`. Failure leaves `.sb/push-pending`."""
    root = Path(root)
    marker = root / PENDING
    try:
        if not enabled(root):
            return "skipped: not a squad vault"
        args = ("push", "-q") if _has_upstream(root) else ("push", "-q", "-u", "origin", "HEAD")
        done = _git(root, *args, timeout=PUSH_TIMEOUT)
        failure = None if done.returncode == 0 else _first_line(done)
    except subprocess.TimeoutExpired:
        failure = "push timed out"
    except (OSError, subprocess.SubprocessError) as exc:
        failure = clean_inline(exc, 200)
    if failure is None:
        try:
            marker.unlink()
        except FileNotFoundError:
            pass
        except OSError:
            pass
        return "ok"
    try:
        marker.parent.mkdir(exist_ok=True)
        marker.write_text(failure + "\n", encoding="utf-8")
    except OSError:
        pass
    return "pending: %s" % failure
