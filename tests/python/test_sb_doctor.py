import io
import json
import shutil
import subprocess
import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path
from unittest import mock

import sb_helpers  # noqa: F401
from sb import doctor, init
from sb.cli import main

NOW = datetime(2026, 11, 10, 12, 0, 0)


def all_present(name):
    return "/usr/bin/" + name


PLUGIN = ".obsidian/plugins/second-brain-companion"
ENABLE_FIX = ('Obsidian → Settings → Community plugins → turn off Restricted mode → '
              'enable "Second Brain Companion"')


def statuses(results):
    return {r["check"]: r["status"] for r in results}


@unittest.skipUnless(shutil.which("git"), "git not installed")
class DoctorTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.root = self.base / "vault"
        init.run(self.root, profile="personal", git=True)
        self.beat(NOW - timedelta(days=1))
        for patcher in (mock.patch.object(doctor, "_has_fts5", return_value=True),
                        mock.patch.object(doctor, "_importable", return_value=True)):
            patcher.start()
            self.addCleanup(patcher.stop)

    def beat(self, when):
        (self.root / ".sb").mkdir(exist_ok=True)
        (self.root / ".sb/heartbeat.json").write_text(
            json.dumps({"session_start": when.isoformat(), "session_id": "s"}), encoding="utf-8")

    def run_doctor(self, which=all_present):
        return doctor.run(self.root, now=NOW, which=which)

    def by_check(self, results):
        return {r["check"]: r for r in results}

    def enable_companion(self, ids=("second-brain-companion",)):
        (self.root / ".obsidian").mkdir(exist_ok=True)
        (self.root / ".obsidian/community-plugins.json").write_text(json.dumps(list(ids)), encoding="utf-8")

    def set_installed_version(self, version):
        path = self.root / PLUGIN / "manifest.json"
        data = json.loads(path.read_text(encoding="utf-8"))
        data["version"] = version
        path.write_text(json.dumps(data), encoding="utf-8")

    def test_clean_vault_all_ok(self):
        self.enable_companion()
        results = self.run_doctor()
        self.assertEqual([r["check"] for r in results],
                         ["python", "settings", "extraction", "hooks", "git", "companion"])
        self.assertEqual(set(statuses(results).values()), {"ok"}, results)
        for r in results:
            self.assertEqual(set(r), {"check", "status", "detail", "fix"})

    def test_python_without_fts5_warns_slow_search(self):
        with mock.patch.object(doctor, "_has_fts5", return_value=False):
            r = self.by_check(self.run_doctor())["python"]
        self.assertEqual(r["status"], "warn")
        self.assertIn("slow search", r["detail"])

    def test_settings_missing_deny_rule_fails(self):
        path = self.root / ".claude/settings.json"
        data = json.loads(path.read_text(encoding="utf-8"))
        data["permissions"]["deny"].remove("Bash(git clean*)")
        path.write_text(json.dumps(data), encoding="utf-8")
        r = self.by_check(self.run_doctor())["settings"]
        self.assertEqual(r["status"], "fail")
        self.assertIn("Bash(git clean*)", r["detail"])

    def test_settings_missing_plugin_fails(self):
        path = self.root / ".claude/settings.json"
        data = json.loads(path.read_text(encoding="utf-8"))
        del data["enabledPlugins"]["obsidian@obsidian-skills"]
        path.write_text(json.dumps(data), encoding="utf-8")
        r = self.by_check(self.run_doctor())["settings"]
        self.assertEqual(r["status"], "fail")
        self.assertIn("obsidian@obsidian-skills", r["detail"])
        self.assertEqual(r["fix"], "sb init --upgrade --yes")

    def test_settings_absent_points_to_upgrade(self):
        (self.root / ".claude/settings.json").unlink()
        r = self.by_check(self.run_doctor())["settings"]
        self.assertEqual(r["status"], "fail")
        self.assertEqual(r["fix"], "sb init --upgrade --yes")

    def test_settings_malformed_fails(self):
        (self.root / ".claude/settings.json").write_text("{nope", encoding="utf-8")
        self.assertEqual(self.by_check(self.run_doctor())["settings"]["status"], "fail")

    def test_extraction_lists_every_missing_tool_with_hints(self):
        r = self.by_check(self.run_doctor(which=lambda name: None))["extraction"]
        self.assertEqual(r["status"], "warn")
        for name in ("pandoc", "markitdown", "pdftotext", "npx"):
            self.assertIn(name, r["detail"])
        self.assertIn("uv tool install 'markitdown[all]'", r["fix"])
        self.assertIn("sudo apt install pandoc poppler-utils", r["fix"])
        self.assertIn("Node.js", r["fix"])
        with mock.patch.object(doctor, "_importable", return_value=False):
            r = self.by_check(self.run_doctor())["extraction"]
        self.assertIn("pypdf", r["detail"])
        self.assertIn("pip install pypdf", r["fix"])

    def test_old_or_missing_heartbeat_warns(self):
        self.beat(NOW - timedelta(days=8))
        r = self.by_check(self.run_doctor())["hooks"]
        self.assertEqual(r["status"], "warn")
        self.assertIn("hooks may not be running: is the plugin installed for this project?",
                      r["detail"])
        (self.root / ".sb/heartbeat.json").unlink()
        self.assertEqual(self.by_check(self.run_doctor())["hooks"]["status"], "warn")

    def test_vault_inside_another_repo_fails(self):
        outer = self.base / "outer"
        outer.mkdir()
        subprocess.run(["git", "init", "-q", str(outer)], check=True)
        nested = outer / "brain"
        init.run(nested, profile="personal")
        r = doctor.run(nested, now=NOW, which=all_present)
        git = self.by_check(r)["git"]
        self.assertEqual(git["status"], "fail")
        self.assertIn("top-level", git["detail"])

    def test_local_vault_without_git_warns(self):
        plain = self.base / "plain"
        init.run(plain, profile="personal")
        self.assertEqual(self.by_check(doctor.run(plain, now=NOW, which=all_present))["git"]["status"],
                         "warn")

    def test_squad_without_remote_or_upstream_warns(self):
        squad = self.base / "squad"
        init.run(squad, profile="squad", git=True)
        git = self.by_check(doctor.run(squad, now=NOW, which=all_present))["git"]
        self.assertEqual(git["status"], "warn")
        self.assertIn("remote", git["detail"])

    def test_squad_with_push_pending_warns(self):
        bare = self.base / "r.git"
        subprocess.run(["git", "init", "-q", "--bare", str(bare)], check=True)
        squad = self.base / "squad"
        init.run(squad, profile="squad", git=True, remote=str(bare))
        subprocess.run(["git", "-C", str(squad), "symbolic-ref", "HEAD", "refs/heads/main"], check=True)
        for args in (("config", "user.email", "t@e.com"), ("config", "user.name", "T"),
                     ("config", "commit.gpgsign", "false"), ("add", "-A"),
                     ("commit", "-q", "-m", "x"), ("push", "-q", "-u", "origin", "main")):
            subprocess.run(["git", "-C", str(squad), *args], check=True, capture_output=True)
        self.assertEqual(self.by_check(doctor.run(squad, now=NOW, which=all_present))["git"]["status"], "ok")
        (squad / ".sb").mkdir(exist_ok=True)
        (squad / ".sb/push-pending").write_text("offline\n", encoding="utf-8")
        git = self.by_check(doctor.run(squad, now=NOW, which=all_present))["git"]
        self.assertEqual(git["status"], "warn")
        self.assertIn("push-pending", git["detail"])

    def test_companion_installed_but_not_enabled_warns_with_the_obsidian_steps(self):
        for setup in (lambda: None, lambda: self.enable_companion(["other-plugin"])):
            with self.subTest():
                (self.root / ".obsidian/community-plugins.json").unlink(missing_ok=True)
                setup()
                companion = self.by_check(self.run_doctor())["companion"]
                self.assertEqual(companion["status"], "warn")
                self.assertIn("installed but not enabled", companion["detail"])
                self.assertEqual(companion["fix"], ENABLE_FIX)

    def test_companion_with_an_unreadable_community_plugins_file_counts_as_not_enabled(self):
        (self.root / ".obsidian/community-plugins.json").write_text("{nope", encoding="utf-8")
        companion = self.by_check(self.run_doctor())["companion"]
        self.assertEqual(companion["status"], "warn")
        self.assertEqual(companion["fix"], ENABLE_FIX)

    def test_companion_missing_points_to_upgrade(self):
        shutil.rmtree(self.root / PLUGIN)
        companion = self.by_check(self.run_doctor())["companion"]
        self.assertEqual(companion["status"], "warn")
        self.assertIn("not installed", companion["detail"])
        self.assertEqual(companion["fix"], "sb init --upgrade --yes")

    def test_companion_older_than_the_bundle_warns_to_upgrade(self):
        self.enable_companion()
        self.set_installed_version("0.0.1")
        companion = self.by_check(self.run_doctor())["companion"]
        self.assertEqual(companion["status"], "warn")
        self.assertIn("0.0.1", companion["detail"])
        self.assertEqual(companion["fix"], "sb init --upgrade --yes")

    def test_companion_newer_than_the_bundle_is_ok(self):
        self.enable_companion()
        self.set_installed_version("99.0.0")
        self.assertEqual(self.by_check(self.run_doctor())["companion"]["status"], "ok")

    def test_companion_old_and_not_enabled_reports_both_fixes(self):
        self.set_installed_version("0.0.1")
        companion = self.by_check(self.run_doctor())["companion"]
        self.assertEqual(companion["status"], "warn")
        self.assertIn("sb init --upgrade --yes", companion["fix"])
        self.assertIn(ENABLE_FIX, companion["fix"])

    def test_companion_warning_does_not_fail_the_exit_code(self):
        out = io.StringIO()
        with mock.patch.object(doctor, "_which", all_present):
            code = main(["doctor", "--vault", str(self.root)], out=out, err=io.StringIO())
        self.assertEqual(code, 0)
        self.assertIn("warn companion", out.getvalue())

    def test_obsidian_setup_table_describes_the_bundled_companion(self):
        self.assertNotIn("BRAT", doctor.OBSIDIAN_SETUP)
        self.assertIn("sb init", doctor.OBSIDIAN_SETUP)

    def test_cli_text_json_and_exit_code(self):
        out = io.StringIO()
        with mock.patch.object(doctor, "_which", all_present):
            code = main(["doctor", "--vault", str(self.root)], out=out, err=io.StringIO())
        self.assertEqual(code, 0)
        text = out.getvalue()
        self.assertIn("Recommended Obsidian setup", text)
        self.assertIn("Terminal", text)
        (self.root / ".claude/settings.json").unlink()
        out = io.StringIO()
        with mock.patch.object(doctor, "_which", all_present):
            code = main(["doctor", "--json", "--vault", str(self.root)], out=out, err=io.StringIO())
        self.assertEqual(code, 1)
        data = json.loads(out.getvalue())
        self.assertEqual({r["check"]: r["status"] for r in data}["settings"], "fail")

    def test_all_planted_failures_are_flagged(self):
        (self.root / ".claude/settings.json").unlink()
        self.beat(NOW - timedelta(days=30))
        outer = self.base / "outer"
        outer.mkdir()
        subprocess.run(["git", "init", "-q", str(outer)], check=True)
        nested = outer / "brain"
        init.run(nested)
        (nested / ".claude/settings.json").unlink()
        with mock.patch.object(doctor, "_has_fts5", return_value=False):
            results = doctor.run(nested, now=NOW, which=lambda name: None)
        self.assertEqual(statuses(results), {"python": "warn", "settings": "fail",
                                             "extraction": "warn", "hooks": "warn", "git": "fail",
                                             "companion": "warn"})


if __name__ == "__main__":
    unittest.main()
