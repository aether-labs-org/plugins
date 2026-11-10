"""Git logic of the session hooks: commit vault changes locally (spec D7, D46). Local commits only."""
import os
import subprocess
from datetime import date
from pathlib import Path

from .vault import find_vault

OFF_VALUES = {"false", "0", "no", "off"}
IN_PROGRESS = ("MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge", "rebase-apply")


def enabled(env):
    return env.get("CLAUDE_PLUGIN_OPTION_AUTO_COMMIT", "true").strip().lower() not in OFF_VALUES


def _git(vault, *args):
    return subprocess.run(["git", "-C", str(vault), *args], capture_output=True, text=True,
                          timeout=30)


def run(cwd, env=None, today=None, session_id="", outside=False):
    """Return 'committed: <message>' or 'skipped: <reason>'. Never raises.

    The session commit is `sb: session YYYY-MM-DD (N files)` with the Sb-Session and Sb-Files
    trailers. With `outside=True` (changes made between sessions) it is
    `sb: changes outside sessions (N files)` with the Sb-Files trailer only.
    """
    env = os.environ if env is None else env
    vault = find_vault(cwd)
    if vault is None:
        return "skipped: not a vault"
    if not enabled(env):
        return "skipped: auto_commit is off"
    if not (vault / ".git").exists():
        return "skipped: no .git"
    try:
        gitdir = _git(vault, "rev-parse", "--absolute-git-dir")
        if gitdir.returncode != 0:
            return "skipped: not a git work tree"
        if any((Path(gitdir.stdout.strip()) / name).exists() for name in IN_PROGRESS):
            return "skipped: merge or rebase in progress"
        status = _git(vault, "status", "--porcelain", "-uall")
        if status.returncode != 0:
            return "skipped: git status failed: %s" % status.stderr.strip()
        changed = [line for line in status.stdout.splitlines() if line.strip()]
        if not changed:
            return "skipped: no changes"
        added = _git(vault, "add", "-A")
        if added.returncode != 0:
            return "skipped: git add failed: %s" % added.stderr.strip()
        if outside:
            message = "sb: changes outside sessions (%d files)" % len(changed)
            trailers = "Sb-Files: %d" % len(changed)
        else:
            message = "sb: session %s (%d files)" % (today or date.today().isoformat(), len(changed))
            trailers = "Sb-Session: %s\nSb-Files: %d" % (session_id or "unknown", len(changed))
        committed = _git(vault, "commit", "-q", "-m", message, "-m", trailers)
        if committed.returncode != 0:
            return "skipped: git commit failed: %s" % (committed.stderr.strip()
                                                       or committed.stdout.strip())
        return "committed: %s" % message
    except (OSError, subprocess.SubprocessError) as exc:
        return "skipped: %s" % exc
