import io
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import sb_helpers  # noqa: F401
from sb import init
from sb.cli import main
from sb.lint import lint
from sb.tree import load, render_compact
from sb.vault import LEGACY_MARKER, MARKER, load_config

TEMPLATES = init.TEMPLATES

DEFAULT_FOLDERS = ["Archive", "Areas", "Projects", "Resources"]
DENY = ["Edit(/_raw/**)", "Edit(/.agents/second-brain/converted/**)", "Bash(git push --force*)",
        "Bash(git push -f*)", "Bash(git reset --hard*)", "Bash(git clean*)"]
LAYOUT_FILES = [
    "CLAUDE.md", ".claude/settings.json", "_meta/web-clipper-template.json", "_views/unreviewed.base",
    "_views/notes.base", "_inbox/_done/.gitkeep", "_raw/.gitkeep", "_assets/.gitkeep", ".gitignore", MARKER,
]
GITIGNORE = [".agents/second-brain/cache/", ".obsidian/workspace*", ".smart-env/"]


def cli(*argv, stdin=""):
    out, err = io.StringIO(), io.StringIO()
    return main(list(argv), out=out, err=err, stdin=io.StringIO(stdin)), out.getvalue(), err.getvalue()


def files(root):
    return sorted(p.relative_to(root).as_posix() for p in Path(root).rglob("*") if p.is_file())


class InitTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / "vault"

    def test_creates_the_schema_3_layout(self):
        result = init.run(self.root, language="pt-BR")
        self.assertEqual(result["status"], "created")
        expected = LAYOUT_FILES + ["wiki/%s/_about.md" % f for f in DEFAULT_FOLDERS]
        self.assertEqual(files(self.root), sorted(expected))
        for rel in ("_inbox/_done", "_raw", "_assets", "wiki/Projects", "wiki/Areas", "wiki/Resources",
                    "wiki/Archive", "_views", "_meta"):
            self.assertTrue((self.root / rel).is_dir(), rel)
        self.assertEqual(load_config(self.root), {"schema_version": 3, "language": "pt-BR", "sync": "local"})
        self.assertIn("pt-BR", (self.root / "CLAUDE.md").read_text(encoding="utf-8"))
        for absent in ("_index.md", "_log.md", ".obsidian", LEGACY_MARKER, ".sb"):
            self.assertFalse((self.root / absent).exists(), absent)
        self.assertEqual([f for f in lint(self.root) if not f.info], [])

    def test_init_does_not_touch_obsidian_plugins(self):
        init.run(self.root)
        self.assertFalse((self.root / ".obsidian").exists())

    def test_marker_is_written_last(self):
        calls = []
        real = init.write_atomic

        def spy(path, text):
            calls.append(Path(path).name)
            real(path, text)

        with mock.patch.object(init, "write_atomic", spy):
            init.run(self.root)
        self.assertEqual(calls[-1], Path(MARKER).name)
        self.assertLess(calls.index("CLAUDE.md"), calls.index(Path(MARKER).name))

    def test_is_idempotent_and_never_overwrites(self):
        init.run(self.root, language="en")
        (self.root / "CLAUDE.md").write_text("mine", encoding="utf-8")
        (self.root / "wiki/Areas/_about.md").write_text("mine", encoding="utf-8")
        (self.root / ".claude/settings.json").write_text("{}", encoding="utf-8")
        again = init.run(self.root, language="pt-BR")
        self.assertEqual(again["status"], "exists")
        for rel in ("CLAUDE.md", "wiki/Areas/_about.md"):
            self.assertEqual((self.root / rel).read_text(encoding="utf-8"), "mine")
        self.assertEqual((self.root / ".claude/settings.json").read_text(encoding="utf-8"), "{}")
        self.assertEqual(load_config(self.root)["language"], "en")

    def test_never_overwrites_files_in_a_directory_without_a_marker(self):
        (self.root / "wiki/Areas").mkdir(parents=True)
        (self.root / "wiki/Areas/_about.md").write_text("mine", encoding="utf-8")
        (self.root / "CLAUDE.md").write_text("mine", encoding="utf-8")
        (self.root / ".claude").mkdir()
        (self.root / ".claude/settings.json").write_text("{}", encoding="utf-8")
        result = init.run(self.root)
        for rel, text in (("CLAUDE.md", "mine"), ("wiki/Areas/_about.md", "mine"),
                          (".claude/settings.json", "{}")):
            self.assertIn(rel, result["kept"])
            self.assertEqual((self.root / rel).read_text(encoding="utf-8"), text, rel)

    def test_gitignore_keeps_crlf_endings(self):
        self.root.mkdir()
        (self.root / ".gitignore").write_bytes(b"node_modules/\r\ndist/\r\n")
        init.run(self.root)
        data = (self.root / ".gitignore").read_bytes()
        self.assertEqual(data, b"node_modules/\r\ndist/\r\n" + b"".join(
            line.encode() + b"\r\n" for line in GITIGNORE))
        # an LF file stays LF, and a file without a final newline gets one first
        other = Path(self.tmp.name) / "lf"
        other.mkdir()
        (other / ".gitignore").write_bytes(b"a\nb")
        init.run(other)
        self.assertEqual((other / ".gitignore").read_bytes(), b"a\nb\n" + b"".join(
            line.encode() + b"\n" for line in GITIGNORE))

    def test_kept_settings_without_the_raw_deny_rule_warn(self):
        (self.root / ".claude").mkdir(parents=True)
        (self.root / ".claude/settings.json").write_text("{}", encoding="utf-8")
        result = init.run(self.root)
        self.assertEqual(len([w for w in result["warnings"] if "Edit(/_raw/**)" in w]), 1, result["warnings"])
        self.assertEqual((self.root / ".claude/settings.json").read_text(encoding="utf-8"), "{}")
        fresh = init.run(Path(self.tmp.name) / "fresh")
        self.assertEqual(fresh["warnings"], [])
        ok = Path(self.tmp.name) / "ok"
        (ok / ".claude").mkdir(parents=True)
        (ok / ".claude/settings.json").write_text('{"permissions": {"deny": ["Edit(/_raw/**)"]}}',
                                                  encoding="utf-8")
        self.assertEqual(init.run(ok)["warnings"], [])

    def test_gitignore_lines_are_appended_once(self):
        self.root.mkdir()
        (self.root / ".gitignore").write_text("node_modules/\n", encoding="utf-8")
        init.run(self.root)
        text = (self.root / ".gitignore").read_text(encoding="utf-8")
        self.assertEqual(text.splitlines(), ["node_modules/"] + GITIGNORE)
        shutil.rmtree(self.root / ".agents")
        init.run(self.root)
        self.assertEqual((self.root / ".gitignore").read_text(encoding="utf-8"), text)

    def test_default_folders_have_about_files(self):
        init.run(self.root)
        folders = {f["path"]: f for f in load(self.root)}
        self.assertEqual(sorted(folders), DEFAULT_FOLDERS)
        for folder in folders.values():
            self.assertNotEqual(folder["description"], "(no description)")
            self.assertTrue(folder["conventions"])
            self.assertEqual((folder["examples"], folder["anti_examples"]), ("", ""))
        text = (self.root / "wiki/Projects/_about.md").read_text(encoding="utf-8")
        self.assertTrue(text.startswith("---\ndescription: "))
        self.assertNotIn("protected", text)
        self.assertLessEqual(len(render_compact(load(self.root))), 2000)
        defaults = init.default_folders()
        self.assertEqual([f["path"] for f in defaults], ["Projects", "Areas", "Resources", "Archive"])
        data = json.loads((TEMPLATES / "folders-default.json").read_text(encoding="utf-8"))
        self.assertEqual(data, defaults)

    def test_folders_from_stdin_create_exactly_those_folders(self):
        spec = [{"path": "Decisões", "description": "One note per decision.", "conventions": "Context first."},
                {"path": "Areas/Saúde", "description": "Health."},
                {"path": "Meetings", "description": "Minutes: dated # weekly [x]"}]
        code, out, err = cli("init", "--vault", str(self.root), "--folders", "-", stdin=json.dumps(spec))
        self.assertEqual(code, 0, err)
        wiki = sorted(p.relative_to(self.root / "wiki").as_posix()
                      for p in (self.root / "wiki").rglob("*") if p.is_dir())
        self.assertEqual(wiki, ["Areas", "Areas/Saúde", "Decisões", "Meetings"])
        self.assertTrue((self.root / "wiki/Decisões/_about.md").is_file())
        self.assertTrue((self.root / "wiki/Areas/Saúde/_about.md").is_file())
        self.assertFalse((self.root / "wiki/Areas/_about.md").exists())
        folders = {f["path"]: f for f in load(self.root)}
        self.assertEqual(folders["Decisões"]["conventions"], "Context first.")
        self.assertEqual(folders["Meetings"]["description"], "Minutes: dated # weekly [x]")
        self.assertEqual(folders["Areas"]["children"][0]["description"], "Health.")
        self.assertNotIn("Conventions", (self.root / "wiki/Areas/Saúde/_about.md").read_text(encoding="utf-8"))
        self.assertIn("hint:", out)

    def test_folders_from_a_file(self):
        spec_file = Path(self.tmp.name) / "folders.json"
        spec_file.write_text(json.dumps([{"path": "Inbox2", "description": "d"}]), encoding="utf-8")
        code, _, err = cli("init", "--vault", str(self.root), "--folders", str(spec_file))
        self.assertEqual(code, 0, err)
        self.assertEqual([f["path"] for f in load(self.root)], ["Inbox2"])

    def test_parse_folders_accepts_accented_names(self):
        found = init.parse_folders(json.dumps([{"path": "Ação/Reuniões", "description": "d"},
                                               {"path": "Ações", "description": "d", "conventions": "c"}]))
        self.assertEqual([f["path"] for f in found], ["Ação/Reuniões", "Ações"])
        self.assertEqual(found[0]["conventions"], "")

    def test_parse_folders_rejects_hostile_paths(self):
        def spec(**item):
            return json.dumps([dict({"path": "Ok", "description": "d"}, **item)])

        bad = [spec(path="../x"), spec(path="a/../x"), spec(path="/abs"), spec(path="_inbox"),
               spec(path=".git"), spec(path="a\\b"), spec(path="Ok/_hidden"), spec(path="a//b"),
               spec(path="a/b/c"), spec(path=""), spec(path="a/"), spec(description=""),
               spec(description="   "), spec(path=3), spec(conventions=5), spec(path="x\ny"),
               json.dumps([{"path": "Docs", "description": "d"}, {"path": "docs", "description": "d"}]),
               json.dumps([{"path": "Árvore", "description": "d"}, {"path": "ÁRVORE", "description": "d"}]),
               json.dumps({"path": "Ok", "description": "d"}), json.dumps([{"path": "Ok"}]),
               json.dumps(["Ok"]), "not json", ""]
        for text in bad:
            with self.assertRaises(ValueError, msg=text):
                init.parse_folders(text)

    def test_invalid_folders_exit_2_and_create_nothing(self):
        code, _, err = cli("init", "--vault", str(self.root), "--folders", "-",
                           stdin=json.dumps([{"path": "../x", "description": "d"}]))
        self.assertEqual(code, 2)
        self.assertIn("invalid --folders", err)
        self.assertFalse(self.root.exists())
        code, _, err = cli("init", "--vault", str(self.root), "--folders", str(Path(self.tmp.name) / "nope"))
        self.assertEqual(code, 2)

    def test_removed_flags_are_unknown(self):
        for flag in (("--profile", "work"), ("--areas", "x"), ("--upgrade",), ("--yes",)):
            self.assertEqual(cli("init", "--vault", str(self.root), *flag)[0], 2, flag)

    def test_vault_claude_md_is_under_200_lines(self):
        init.run(self.root)
        self.assertLess(len((self.root / "CLAUDE.md").read_text(encoding="utf-8").splitlines()), 200)

    def test_init_writes_gitkeep_in_done_raw_and_assets(self):
        result = init.run(self.root)
        for rel in ("_inbox/_done/.gitkeep", "_raw/.gitkeep", "_assets/.gitkeep"):
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

    def test_vault_template_is_short_and_holds_the_body_rules(self):
        init.run(self.root)
        text = (self.root / "CLAUDE.md").read_text(encoding="utf-8")
        self.assertLessEqual(len(text), 3200)
        lowered = text.lower()
        for phrase in ("never invent", "gap", "preamble", "recap", "[!agent]", "origin: agent", "_raw/"):
            self.assertIn(phrase, lowered)
        for word in ("sb log", "sb index", "sb review", "source_id", "guard", "companion", "_index.md",
                     "protected", "reviewed_hash"):
            self.assertNotIn(word, lowered)
        self.assertNotIn("{{", text)

    @unittest.skipUnless(shutil.which("git"), "git not installed")
    def test_git_flag_runs_git_init(self):
        init.run(self.root, git=True)
        self.assertTrue((self.root / ".git").exists())

    @unittest.skipUnless(shutil.which("git"), "git not installed")
    def test_remote_sets_sync_pull_and_needs_git(self):
        bare = Path(self.tmp.name) / "bare.git"
        subprocess.run(["git", "init", "-q", "--bare", str(bare)], check=True)
        code, _, err = cli("init", "--vault", str(self.root), "--git", "--remote", str(bare))
        self.assertEqual(code, 0, err)
        url = subprocess.run(["git", "-C", str(self.root), "remote", "get-url", "origin"],
                             capture_output=True, text=True).stdout.strip()
        self.assertEqual(url, str(bare))
        self.assertEqual(load_config(self.root)["sync"], "pull")
        code, _, err = cli("init", "--vault", str(Path(self.tmp.name) / "other"), "--remote", "/x/y.git")
        self.assertEqual(code, 2)
        self.assertIn("--git", err)
        self.assertEqual(init.run(Path(self.tmp.name) / "plain")["status"], "created")
        self.assertEqual(load_config(Path(self.tmp.name) / "plain")["sync"], "local")

    def test_settings_json_content(self):
        init.run(self.root)
        s = json.loads((self.root / ".claude/settings.json").read_text(encoding="utf-8"))
        self.assertEqual(s["permissions"]["deny"], DENY)
        self.assertEqual(s["enabledPlugins"], {"second-brain@aether-labs": True})
        repos = {k: v["source"]["repo"] for k, v in s["extraKnownMarketplaces"].items()}
        self.assertEqual(repos, {"aether-labs": "aether-labs-org/plugins"})

    def test_web_clipper_template_and_base_formats(self):
        init.run(self.root)
        clip = json.loads((self.root / "_meta/web-clipper-template.json").read_text(encoding="utf-8"))
        self.assertEqual(clip["behavior"], "create")
        self.assertEqual(clip["path"], "_inbox")
        self.assertEqual([p["name"] for p in clip["properties"]], ["title", "url", "captured"])
        unreviewed = (self.root / "_views/unreviewed.base").read_text(encoding="utf-8")
        self.assertIn('origin == "agent"', unreviewed)
        self.assertIn("reviewed", unreviewed)
        notes = (self.root / "_views/notes.base").read_text(encoding="utf-8")
        self.assertIn('file.inFolder("wiki")', notes)
        self.assertIn("_about", notes)
        self.assertTrue(notes.startswith("filters:\n"))
        for column in ("file.name", "summary", "origin", "created"):
            self.assertIn("      - %s\n" % column, notes)
        self.assertIn("views:", notes)

    def test_hint_names_the_assets_folder(self):
        result = init.run(self.root)
        self.assertEqual(len(result["hints"]), 1)
        self.assertIn("_assets", result["hints"][0])
        self.assertIn("Default location for new attachments", result["hints"][0])
        code, out, _ = cli("init", "--vault", str(Path(self.tmp.name) / "second"))
        self.assertEqual(code, 0)
        self.assertTrue(any(line.startswith("hint: ") and "_assets" in line for line in out.splitlines()))

    def test_refuses_inside_another_repo_or_vault(self):
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
        # inside another vault
        outer = Path(self.tmp.name) / "outer"
        init.run(outer)
        code, _, err = cli("init", "--vault", str(outer / "wiki" / "inner"))
        self.assertEqual(code, 2)
        self.assertIn("inside the existing vault", err)
        self.assertFalse((outer / "wiki" / "inner").exists())

    def test_refuses_a_legacy_vault(self):
        legacy = Path(self.tmp.name) / "legacy"
        legacy.mkdir()
        (legacy / LEGACY_MARKER).write_text('{"schema_version": 2}', encoding="utf-8")
        code, _, err = cli("init", "--vault", str(legacy))
        self.assertEqual(code, 2)
        self.assertIn("schema 2", err)
        self.assertEqual(files(legacy), [LEGACY_MARKER])


if __name__ == "__main__":
    unittest.main()
