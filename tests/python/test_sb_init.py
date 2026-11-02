import io
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from sb_helpers import make_vault, note
from sb import init
from sb.cli import main
from sb.lint import INFO_CODES, lint
from sb.tree import load, render_compact
from sb.vault import MARKER, load_config

TEMPLATES = init.TEMPLATES

PROFILES = {
    "personal": ["Archive", "Areas", "Projects", "Resources"],
    "work": ["Archive", "Areas", "Decisions", "Meetings", "Projects", "Resources"],
    "project": ["Archive", "Context", "Decisions", "Glossary", "Meetings", "References"],
    "squad": ["Archive", "Context", "Decisions", "Glossary", "Meetings", "References"],
}
DENY = ["Edit(/_raw/**)", "Bash(git push --force*)", "Bash(git push -f*)",
        "Bash(git reset --hard*)", "Bash(git clean*)"]


def cli(*argv):
    out, err = io.StringIO(), io.StringIO()
    return main(list(argv), out=out, err=err), out.getvalue(), err.getvalue()


class InitTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / "vault"

    def test_creates_layout_marker_and_a_clean_vault(self):
        result = init.run(self.root, language="pt-BR", areas=["Saúde", "Finanças"])
        self.assertEqual(result["status"], "created")
        for rel in ("_inbox/_done", "_raw", "wiki/Projects", "wiki/Areas/Saúde",
                    "wiki/Areas/Finanças", "wiki/Resources", "wiki/Archive"):
            self.assertTrue((self.root / rel).is_dir(), rel)
        for rel in ("CLAUDE.md", "_index.md", "_log.md", ".gitignore", MARKER):
            self.assertTrue((self.root / rel).is_file(), rel)
        self.assertEqual(load_config(self.root),
                         {"schema_version": 2, "language": "pt-BR", "profile": "personal", "sync": "local",
                          "areas": ["Saúde", "Finanças"]})
        self.assertIn("pt-BR", (self.root / "CLAUDE.md").read_text(encoding="utf-8"))
        self.assertIn("init | vault created", (self.root / "_log.md").read_text(encoding="utf-8"))
        self.assertEqual([f for f in lint(self.root, load_config(self.root)) if f.code not in INFO_CODES], [])

    def test_installs_the_bundled_companion_without_enabling_it(self):
        result = init.run(self.root)
        plugin = self.root / COMPANION
        for name in ("main.js", "manifest.json", "styles.css"):
            self.assertEqual((plugin / name).read_bytes(), (init.BUNDLE / name).read_bytes(), name)
        self.assertIn(COMPANION, result["created"])
        self.assertEqual(json.loads((plugin / "manifest.json").read_text(encoding="utf-8"))["id"],
                         "second-brain-companion")
        # the human enables it in Obsidian: no community-plugins.json, nothing else under .obsidian
        self.assertFalse((self.root / ".obsidian/community-plugins.json").exists())
        self.assertEqual({p.relative_to(self.root / ".obsidian").parts[0]
                          for p in (self.root / ".obsidian").rglob("*") if p.is_file()}, {"plugins"})
        self.assertFalse((plugin / "data.json").exists())

    def test_run_keeps_a_companion_that_is_already_installed(self):
        plugin = self.root / COMPANION
        plugin.mkdir(parents=True)
        (plugin / "manifest.json").write_text('{"version": "9.9.9"}', encoding="utf-8")
        (plugin / "main.js").write_text("mine", encoding="utf-8")
        result = init.run(self.root)
        self.assertEqual((plugin / "main.js").read_text(encoding="utf-8"), "mine")
        self.assertIn(COMPANION, result["kept"])
        self.assertNotIn(COMPANION, result["created"])

    def test_missing_bundle_warns_and_still_creates_the_vault(self):
        with mock.patch.object(init, "BUNDLE", Path(self.tmp.name) / "nope"):
            result = init.run(self.root)
        self.assertEqual(result["status"], "created")
        self.assertTrue(any("companion" in w for w in result["warnings"]), result["warnings"])
        self.assertFalse((self.root / COMPANION).exists())

    def test_vault_claude_md_is_under_200_lines(self):
        init.run(self.root)
        self.assertLess(len((self.root / "CLAUDE.md").read_text(encoding="utf-8").splitlines()), 200)

    def test_is_idempotent_and_never_touches_an_existing_marker_vault(self):
        init.run(self.root, language="en")
        (self.root / "CLAUDE.md").write_text("mine", encoding="utf-8")
        again = init.run(self.root, language="pt-BR")
        self.assertEqual(again["status"], "exists")
        self.assertEqual((self.root / "CLAUDE.md").read_text(encoding="utf-8"), "mine")
        self.assertEqual(load_config(self.root)["language"], "en")

    def test_never_overwrites_an_existing_claude_md(self):
        self.root.mkdir()
        (self.root / "CLAUDE.md").write_text("mine", encoding="utf-8")
        result = init.run(self.root)
        self.assertIn("CLAUDE.md", result["kept"])
        self.assertEqual((self.root / "CLAUDE.md").read_text(encoding="utf-8"), "mine")

    def test_gitignore_lines_are_appended_once(self):
        self.root.mkdir()
        (self.root / ".gitignore").write_text("node_modules/\n", encoding="utf-8")
        init.run(self.root)
        text = (self.root / ".gitignore").read_text(encoding="utf-8")
        self.assertEqual(text.splitlines(),
                         ["node_modules/", ".sb/", ".obsidian/workspace*", ".smart-env/"])

    def test_invalid_area_names_are_skipped_with_a_warning(self):
        result = init.run(self.root, areas=["ok", "../escape", ".hidden", "a/b", "  "])
        self.assertEqual(load_config(self.root)["areas"], ["ok"])
        self.assertEqual(len(result["warnings"]), 3)
        self.assertFalse((Path(self.tmp.name) / "escape").exists())

    def test_marker_is_written_last(self):
        calls = []
        real = init.write_atomic

        def spy(path, text):
            calls.append(Path(path).name)
            real(path, text)

        with mock.patch.object(init, "write_atomic", spy):
            init.run(self.root)
        self.assertEqual(calls[-1], MARKER)
        self.assertLess(calls.index("CLAUDE.md"), calls.index(MARKER))

    @unittest.skipUnless(shutil.which("git"), "git not installed")
    def test_git_flag_runs_git_init(self):
        init.run(self.root, git=True)
        self.assertTrue((self.root / ".git").exists())

    # --- milestone C: profiles ---------------------------------------------------------------
    def test_each_profile_creates_a_clean_vault(self):
        for name, folders in PROFILES.items():
            root = Path(self.tmp.name) / name
            init.run(root, language="pt-BR", profile=name, git=True)
            self.assertEqual([f for f in lint(root, load_config(root)) if f.code not in INFO_CODES], [])
            self.assertEqual([f for f in lint(root, load_config(root)) if f.code == "SB111"], [], name)
            self.assertLessEqual(len(render_compact(load(root))), 2000)
            self.assertEqual([f["path"] for f in load(root)], folders)
            config = json.loads((root / ".second-brain.json").read_text(encoding="utf-8"))
            self.assertEqual(config["sync"], "squad" if name == "squad" else "local")
            self.assertEqual((config["schema_version"], config["profile"]), (2, name))
            for rel in (".claude/settings.json", "_meta/web-clipper-template.json",
                        "_views/unreviewed.base"):
                self.assertTrue((root / rel).is_file(), (name, rel))

    def test_unknown_profile_is_an_error(self):
        with self.assertRaises(ValueError):
            init.load_profile("nope")

    def test_about_md_carries_description_and_sections(self):
        init.run(self.root, profile="work")
        folders = {f["path"]: f for f in load(self.root)}
        decisions = folders["Decisions"]
        self.assertEqual(decisions["description"],
                         "One note per decision: context, options, choice, consequences.")
        self.assertIn("Meeting minutes (they go in Meetings/ and link to the decision).",
                      decisions["anti_examples"])
        self.assertTrue(decisions["conventions"])
        self.assertFalse(decisions["protected"])

    def test_settings_json_content(self):
        init.run(self.root)
        s = json.loads((self.root / ".claude/settings.json").read_text(encoding="utf-8"))
        self.assertEqual(s["permissions"]["deny"], DENY)
        self.assertEqual(s["enabledPlugins"], {"second-brain@aether-labs": True,
                                               "document-skills@anthropic-agent-skills": True,
                                               "obsidian@obsidian-skills": True})
        repos = {k: v["source"]["repo"] for k, v in s["extraKnownMarketplaces"].items()}
        self.assertEqual(repos, {"aether-labs": "aether-labs-org/plugins",
                                 "anthropic-agent-skills": "anthropics/skills",
                                 "obsidian-skills": "kepano/obsidian-skills"})

    def test_existing_settings_json_is_kept(self):
        (self.root / ".claude").mkdir(parents=True)
        (self.root / ".claude/settings.json").write_text("{}", encoding="utf-8")
        result = init.run(self.root)
        self.assertIn(".claude/settings.json", result["kept"])
        self.assertEqual((self.root / ".claude/settings.json").read_text(encoding="utf-8"), "{}")

    def test_web_clipper_template_and_base_formats(self):
        init.run(self.root)
        clip = json.loads((self.root / "_meta/web-clipper-template.json").read_text(encoding="utf-8"))
        self.assertEqual(clip["behavior"], "create")
        self.assertEqual(clip["path"], "_inbox")
        self.assertEqual([p["name"] for p in clip["properties"]], ["title", "url", "captured"])
        base = (self.root / "_views/unreviewed.base").read_text(encoding="utf-8")
        self.assertIn('origin == "agent"', base)
        self.assertIn("reviewed", base)

    def test_gitignore_by_sync_mode(self):
        init.run(self.root / "a", profile="personal")
        init.run(self.root / "b", profile="squad")
        local = (self.root / "a/.gitignore").read_text(encoding="utf-8").splitlines()
        squad = (self.root / "b/.gitignore").read_text(encoding="utf-8").splitlines()
        self.assertEqual(local, [".sb/", ".obsidian/workspace*", ".smart-env/"])
        self.assertEqual(squad, [".sb/", ".obsidian/workspace*", ".smart-env/", "_index.md", "_log.md"])

    def test_areas_without_an_areas_folder_are_ignored_with_a_warning(self):
        result = init.run(self.root, profile="project", areas=["x"])
        self.assertFalse((self.root / "wiki/Areas").exists())
        self.assertEqual(len(result["warnings"]), 1)

    def test_refuses_inside_another_git_repo(self):
        parent = Path(self.tmp.name) / "repo"
        parent.mkdir()
        subprocess.run(["git", "init", "-q", str(parent)], check=True)
        target = parent / "brain"
        code, _, err = cli("init", "--vault", str(target))
        self.assertEqual(code, 2)
        self.assertIn("inside the git repository", err)
        self.assertFalse((target / MARKER).exists())
        # a vault that is itself a repository is fine
        subprocess.run(["git", "init", "-q", str(target)], check=True)
        self.assertEqual(cli("init", "--vault", str(target))[0], 0)

    def test_cli_profile_and_remote(self):
        bare = Path(self.tmp.name) / "bare.git"
        subprocess.run(["git", "init", "-q", "--bare", str(bare)], check=True)
        code, _, err = cli("init", "--vault", str(self.root), "--profile", "squad", "--git",
                           "--remote", str(bare))
        self.assertEqual(code, 0, err)
        url = subprocess.run(["git", "-C", str(self.root), "remote", "get-url", "origin"],
                             capture_output=True, text=True).stdout.strip()
        self.assertEqual(url, str(bare))

    def test_remote_needs_git(self):
        code, _, err = cli("init", "--vault", str(self.root), "--remote", "/x/y.git")
        self.assertEqual(code, 2)
        self.assertIn("--git", err)

    def test_sb107_message_points_to_upgrade(self):
        init.run(self.root)
        marker = json.loads((self.root / MARKER).read_text(encoding="utf-8"))
        marker["schema_version"] = 1
        (self.root / MARKER).write_text(json.dumps(marker), encoding="utf-8")
        found = [f for f in lint(self.root, load_config(self.root)) if f.code == "SB107"]
        self.assertEqual(found[0].message, "schema_version 1 is older than 2; run sb init --upgrade")


COMPANION = ".obsidian/plugins/second-brain-companion"


def fake_bundle(base, version):
    """A stand-in for plugins/second-brain/obsidian/dist with a given manifest version."""
    dist = Path(base) / ("dist-" + version)
    dist.mkdir(parents=True)
    (dist / "manifest.json").write_text(
        json.dumps({"id": "second-brain-companion", "version": version}), encoding="utf-8")
    (dist / "main.js").write_text("// main %s\n" % version, encoding="utf-8")
    (dist / "styles.css").write_text("/* css %s */\n" % version, encoding="utf-8")
    return dist


def snapshot(root):
    return {p.relative_to(root).as_posix(): p.read_bytes()
            for p in sorted(Path(root).rglob("*")) if p.is_file() and ".git" not in p.parts}


class UpgradeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = make_vault(self.tmp.name, {
            "Resources/A.md": note("A", body="[[B]] [[C]]"),
            "Resources/B.md": note("B", body="[[A]]"),
            "Meus Estudos/C.md": note("C", body="[[A]]"),
        }, config={"schema_version": 1, "language": "pt-BR", "areas": []})
        (self.root / "CLAUDE.md").write_text("my rules", encoding="utf-8")
        (self.root / ".gitignore").write_text("node_modules/\n", encoding="utf-8")

    def git(self, *args):
        return subprocess.run(["git", "-C", str(self.root), *args], capture_output=True, text=True)

    def make_repo(self):
        self.git("init", "-q")
        self.git("config", "user.email", "t@example.com")
        self.git("config", "user.name", "T")
        self.git("add", "-A")
        self.git("commit", "-q", "-m", "v0.1")

    def test_upgrade_dry_run_changes_nothing(self):
        before = snapshot(self.root)
        result = init.upgrade(self.root)
        self.assertFalse(result["applied"])
        self.assertTrue(result["actions"])
        self.assertEqual(snapshot(self.root), before)
        code, out, _ = cli("init", "--upgrade", "--vault", str(self.root))
        self.assertEqual(code, 0)
        self.assertIn("settings.json", out)
        self.assertEqual(snapshot(self.root), before)

    def test_upgrade_keeps_user_files(self):
        (self.root / ".claude").mkdir()
        (self.root / ".claude/settings.json").write_text(
            (TEMPLATES / "settings.json").read_text(encoding="utf-8"), encoding="utf-8")
        result = init.upgrade(self.root, yes=True)
        self.assertTrue(result["applied"])
        self.assertEqual((self.root / "CLAUDE.md").read_text(encoding="utf-8"), "my rules")
        self.assertIn(".claude/settings.json", result["kept"])
        self.assertIn("CLAUDE.md", result["kept"])
        self.assertNotIn("merge", " ".join(result["actions"]))
        gitignore = (self.root / ".gitignore").read_text(encoding="utf-8").splitlines()
        self.assertEqual(gitignore, ["node_modules/", ".sb/", ".obsidian/workspace*", ".smart-env/"])

    def write_settings(self, text):
        (self.root / ".claude").mkdir(exist_ok=True)
        (self.root / ".claude/settings.json").write_text(text, encoding="utf-8")

    def read_settings(self):
        return json.loads((self.root / ".claude/settings.json").read_text(encoding="utf-8"))

    def test_upgrade_merges_missing_settings_entries_only(self):
        mine = {"model": "opus",
                "enabledPlugins": {"mine@x": True, "second-brain@aether-labs": False},
                "extraKnownMarketplaces": {"mine": {"source": {"source": "github", "repo": "a/b"}},
                                           "obsidian-skills": {"custom": True}},
                "permissions": {"allow": ["Bash(ls)"], "deny": ["Bash(rm -rf*)", "Edit(/_raw/**)"]},
                "hooks": {"Stop": []}}
        self.write_settings(json.dumps(mine))
        result = init.upgrade(self.root, yes=True)
        data = self.read_settings()
        template = json.loads((TEMPLATES / "settings.json").read_text(encoding="utf-8"))
        # existing keys, values and order are preserved
        self.assertEqual(list(data), ["model", "enabledPlugins", "extraKnownMarketplaces",
                                      "permissions", "hooks"])
        self.assertEqual(data["model"], "opus")
        self.assertEqual(data["hooks"], {"Stop": []})
        self.assertEqual(list(data["enabledPlugins"]),
                         ["mine@x", "second-brain@aether-labs", "document-skills@anthropic-agent-skills",
                          "obsidian@obsidian-skills"])
        self.assertIs(data["enabledPlugins"]["second-brain@aether-labs"], False)   # never changed
        self.assertEqual(data["extraKnownMarketplaces"]["obsidian-skills"], {"custom": True})
        self.assertEqual(data["extraKnownMarketplaces"]["mine"], mine["extraKnownMarketplaces"]["mine"])
        self.assertEqual(data["extraKnownMarketplaces"]["aether-labs"],
                         template["extraKnownMarketplaces"]["aether-labs"])
        self.assertEqual(data["permissions"]["allow"], ["Bash(ls)"])
        self.assertEqual(data["permissions"]["deny"], ["Bash(rm -rf*)", "Edit(/_raw/**)"] + DENY[1:])
        self.assertIn("merge .claude/settings.json (+8 entries)", result["actions"])
        self.assertNotIn(".claude/settings.json", result["kept"])

    def test_upgrade_merge_into_an_empty_object_adds_everything(self):
        self.write_settings("{}")
        result = init.upgrade(self.root, yes=True)
        self.assertEqual(self.read_settings(),
                         json.loads((TEMPLATES / "settings.json").read_text(encoding="utf-8")))
        self.assertIn("merge .claude/settings.json (+11 entries)", result["actions"])

    def test_upgrade_settings_merge_is_idempotent(self):
        self.write_settings('{"mine": true}')
        init.upgrade(self.root, yes=True)
        first = (self.root / ".claude/settings.json").read_bytes()
        again = init.upgrade(self.root, yes=True)
        self.assertEqual(again["actions"], [])
        self.assertIn(".claude/settings.json", again["kept"])
        self.assertEqual((self.root / ".claude/settings.json").read_bytes(), first)
        self.assertIs(self.read_settings()["mine"], True)

    def test_upgrade_settings_dry_run_reports_without_writing(self):
        self.write_settings('{"mine": true}')
        result = init.upgrade(self.root)
        self.assertTrue(any(a.startswith("merge .claude/settings.json (+") for a in result["actions"]))
        self.assertEqual((self.root / ".claude/settings.json").read_text(encoding="utf-8"),
                         '{"mine": true}')

    def test_upgrade_leaves_invalid_settings_untouched_with_a_warning(self):
        for text in ("{nope", "[1, 2]", ""):
            self.write_settings(text)
            result = init.upgrade(self.root, yes=True)
            self.assertEqual((self.root / ".claude/settings.json").read_text(encoding="utf-8"), text)
            self.assertIn(".claude/settings.json", result["kept"])
            self.assertFalse([a for a in result["actions"] if "settings.json" in a])
            self.assertTrue(any(".claude/settings.json" in w for w in result["warnings"]), text)
        code, out, _ = cli("init", "--upgrade", "--vault", str(self.root))
        self.assertIn("warning: ", out)

    def test_upgrade_skips_settings_sections_of_an_unexpected_type(self):
        self.write_settings('{"enabledPlugins": [], "permissions": {"deny": "x"}}')
        init.upgrade(self.root, yes=True)
        data = self.read_settings()
        self.assertEqual(data["enabledPlugins"], [])
        self.assertEqual(data["permissions"], {"deny": "x"})
        self.assertIn("extraKnownMarketplaces", data)

    def test_upgrade_adds_about_files_marker_and_templates(self):
        init.upgrade(self.root, yes=True)
        folders = {f["path"]: f["description"] for f in load(self.root)}
        self.assertEqual(folders["Meus Estudos"], "(describe this folder)")
        self.assertEqual(folders["Resources"], "Concepts, entities and references reused across projects.")
        config = load_config(self.root)
        self.assertEqual((config["schema_version"], config["profile"], config["sync"],
                          config["language"]), (2, "personal", "local", "pt-BR"))
        for rel in ("_meta/web-clipper-template.json", "_views/unreviewed.base"):
            self.assertTrue((self.root / rel).is_file(), rel)
        self.assertEqual([f for f in lint(self.root, load_config(self.root))
                          if f.code not in INFO_CODES], [])

    @unittest.skipUnless(shutil.which("git"), "git not installed")
    def test_upgrade_v01_vault_to_squad(self):
        self.make_repo()
        notes_before = {k: v for k, v in snapshot(self.root).items() if k.startswith("wiki/")}
        self.assertIn("_index.md", self.git("ls-files").stdout.split())
        result = init.upgrade(self.root, profile="squad", yes=True)
        tracked = self.git("ls-files").stdout.split()
        self.assertNotIn("_index.md", tracked)
        self.assertNotIn("_log.md", tracked)
        self.assertTrue((self.root / "_index.md").is_file())
        self.assertEqual(load_config(self.root)["sync"], "squad")
        self.assertEqual(load_config(self.root)["profile"], "squad")
        notes_after = {k: v for k, v in snapshot(self.root).items() if k in notes_before}
        self.assertEqual(notes_after, notes_before)
        self.assertTrue(any("git rm --cached" in a for a in result["actions"]))

    @unittest.skipUnless(shutil.which("git"), "git not installed")
    def test_squad_dry_run_does_not_touch_the_index(self):
        self.make_repo()
        init.upgrade(self.root, profile="squad")
        self.assertIn("_index.md", self.git("ls-files").stdout.split())

    def test_upgrade_is_idempotent(self):
        init.upgrade(self.root, yes=True)
        again = init.upgrade(self.root, yes=True)
        self.assertEqual(again["actions"], [])

    def test_upgrade_installs_a_missing_companion_only_with_yes(self):
        plan = init.upgrade(self.root)
        self.assertTrue(any(a.startswith("add %s" % COMPANION) for a in plan["actions"]), plan["actions"])
        self.assertFalse((self.root / ".obsidian").exists())
        result = init.upgrade(self.root, yes=True)
        self.assertTrue(result["applied"])
        for name in ("main.js", "manifest.json", "styles.css"):
            self.assertEqual((self.root / COMPANION / name).read_bytes(),
                             (init.BUNDLE / name).read_bytes(), name)
        self.assertFalse((self.root / ".obsidian/community-plugins.json").exists())
        self.assertEqual(init.upgrade(self.root, yes=True)["actions"], [])      # idempotent

    def install_companion(self, version):
        plugin = self.root / COMPANION
        plugin.mkdir(parents=True)
        (plugin / "manifest.json").write_text(
            json.dumps({"id": "second-brain-companion", "version": version}), encoding="utf-8")
        (plugin / "main.js").write_text("// installed %s" % version, encoding="utf-8")
        return plugin

    def test_upgrade_updates_an_older_companion_and_touches_nothing_else(self):
        plugin = self.install_companion("0.0.9")
        (plugin / "data.json").write_text('{"mine": true}', encoding="utf-8")
        (self.root / ".obsidian/community-plugins.json").write_text('["x"]', encoding="utf-8")
        (self.root / ".obsidian/app.json").write_text("{}", encoding="utf-8")
        bundled = json.loads((init.BUNDLE / "manifest.json").read_text(encoding="utf-8"))["version"]
        others = {k: v for k, v in snapshot(self.root / ".obsidian").items()
                  if not k.startswith("plugins/second-brain-companion/")}
        plan = init.upgrade(self.root)
        self.assertIn("update companion 0.0.9 -> %s" % bundled, plan["actions"])
        self.assertEqual((plugin / "main.js").read_text(encoding="utf-8"), "// installed 0.0.9")
        init.upgrade(self.root, yes=True)
        self.assertEqual((plugin / "main.js").read_bytes(), (init.BUNDLE / "main.js").read_bytes())
        self.assertEqual((plugin / "data.json").read_text(encoding="utf-8"), '{"mine": true}')
        self.assertEqual({k: v for k, v in snapshot(self.root / ".obsidian").items()
                          if not k.startswith("plugins/second-brain-companion/")}, others)

    def test_upgrade_never_downgrades_or_rewrites_an_equal_or_newer_companion(self):
        for installed in ("99.0.0", json.loads(
                (init.BUNDLE / "manifest.json").read_text(encoding="utf-8"))["version"]):
            with self.subTest(installed=installed):
                shutil.rmtree(self.root / ".obsidian", ignore_errors=True)
                plugin = self.install_companion(installed)
                result = init.upgrade(self.root, yes=True)
                self.assertFalse([a for a in result["actions"] if "companion" in a], result["actions"])
                self.assertIn(COMPANION, result["kept"])
                self.assertEqual((plugin / "main.js").read_text(encoding="utf-8"),
                                 "// installed %s" % installed)

    def test_upgrade_compares_versions_numerically(self):
        shutil.rmtree(self.root / ".obsidian", ignore_errors=True)
        self.install_companion("0.9.0")
        with mock.patch.object(init, "BUNDLE", fake_bundle(self.tmp.name, "0.10.0")):
            result = init.upgrade(self.root, yes=True)
        self.assertIn("update companion 0.9.0 -> 0.10.0", result["actions"])

    def test_upgrade_reinstalls_a_companion_whose_manifest_is_unreadable(self):
        plugin = self.root / COMPANION
        plugin.mkdir(parents=True)
        (plugin / "manifest.json").write_text("{not json", encoding="utf-8")
        (plugin / "main.js").write_text("old", encoding="utf-8")
        result = init.upgrade(self.root, yes=True)
        self.assertTrue(any(a.startswith("update companion ? -> ") for a in result["actions"]), result["actions"])
        self.assertEqual((plugin / "main.js").read_bytes(), (init.BUNDLE / "main.js").read_bytes())

    def test_upgrade_with_a_missing_bundle_warns(self):
        with mock.patch.object(init, "BUNDLE", Path(self.tmp.name) / "nope"):
            result = init.upgrade(self.root, yes=True)
        self.assertTrue(any("companion" in w for w in result["warnings"]), result["warnings"])
        self.assertFalse((self.root / COMPANION).exists())

    def test_upgrade_needs_a_vault(self):
        code, _, err = cli("init", "--upgrade", "--vault", str(Path(self.tmp.name) / "nothing"))
        self.assertEqual(code, 2)
        self.assertIn("not a second-brain vault", err)


if __name__ == "__main__":
    unittest.main()
