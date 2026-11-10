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
        for rel in ("CLAUDE.md", ".gitignore", MARKER):
            self.assertTrue((self.root / rel).is_file(), rel)
        self.assertEqual(load_config(self.root),
                         {"schema_version": 2, "language": "pt-BR", "profile": "personal", "sync": "local",
                          "areas": ["Saúde", "Finanças"]})
        self.assertIn("pt-BR", (self.root / "CLAUDE.md").read_text(encoding="utf-8"))
        self.assertFalse((self.root / "_index.md").exists() or (self.root / "_log.md").exists())
        self.assertEqual([f for f in lint(self.root, load_config(self.root)) if f.code not in INFO_CODES], [])

    def test_init_does_not_touch_obsidian_plugins(self):
        init.run(self.root)
        self.assertFalse((self.root / ".obsidian").exists())

    def test_vault_claude_md_is_under_200_lines(self):
        init.run(self.root)
        self.assertLess(len((self.root / "CLAUDE.md").read_text(encoding="utf-8").splitlines()), 200)

    def test_init_writes_gitkeep_in_done_and_raw(self):
        result = init.run(self.root)
        for rel in ("_inbox/_done/.gitkeep", "_raw/.gitkeep"):
            self.assertTrue((self.root / rel).is_file(), rel)
            self.assertEqual((self.root / rel).read_text(encoding="utf-8"), "")
            self.assertIn(rel, result["created"])

    def test_gitkeep_is_not_an_inbox_item(self):
        from sb import session
        init.run(self.root)
        self.assertEqual(session._inbox_count(self.root), 0)

    def test_claude_md_rule_5_marks_general_knowledge(self):
        init.run(self.root)
        text = (self.root / "CLAUDE.md").read_text(encoding="utf-8")
        self.assertIn('marked "(conhecimento geral)"', " ".join(text.split()))

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
        self.assertEqual(squad, [".sb/", ".obsidian/workspace*", ".smart-env/"])

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


if __name__ == "__main__":
    unittest.main()
