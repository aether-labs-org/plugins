package protect

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/aether-labs-org/plugins/cli/kh/internal/config"
)

func repo(t *testing.T) string {
	t.Helper()
	d, _ := filepath.EvalSymlinks(t.TempDir())
	for _, dir := range []string{".agents/baselines", ".agents/bin", ".agents/plans", ".agents/skills/x", "docs/adr", "docs", "src"} {
		os.MkdirAll(filepath.Join(d, dir), 0o755)
	}
	os.WriteFile(filepath.Join(d, ".agents/keel.yml"), []byte("version: 1\n"), 0o644)
	t.Setenv("HOME", filepath.Join(d, "home"))
	return d
}

func cfg(t *testing.T) *config.Config {
	t.Helper()
	c, err := config.Parse([]byte(`version: 1
adr_dir: docs/adr
guides: [AGENTS.md, CLAUDE.md, docs/architecture.md, docs/review.md]
scripts:
  arch: { run: depcruise, config: [.dependency-cruiser.cjs] }
`))
	if err != nil {
		t.Fatal(err)
	}
	return c
}

func TestMatch(t *testing.T) {
	d := repo(t)
	s := Load(d, cfg(t), false)
	os.Symlink(filepath.Join(d, ".agents/keel.yml"), filepath.Join(d, "link.yml"))
	os.Symlink(filepath.Join(d, "docs"), filepath.Join(d, "src/docs-link"))
	cases := []struct {
		path  string
		class string // "" = not protected
	}{
		{".agents/keel.yml", Engine},
		{".agents/keel.lock", Engine},
		{".agents/bin/kh", Engine},
		{".agents/baselines/lint.tsv", Engine},
		{".agents/githooks/pre-commit", Engine},
		{".dependency-cruiser.cjs", Config},
		{".claude/settings.json", AgentHooks},
		{".claude/settings.local.json", AgentHooks},
		{".claude/agents/keel-reviewer.md", AgentHooks},
		{".github/hooks/keel.json", AgentHooks},
		{".github/copilot/settings.json", AgentHooks},
		{".github/copilot/settings.local.json", AgentHooks},
		{".github/agents/keel-reviewer.agent.md", AgentHooks},
		{".devin/config.json", AgentHooks},
		{".git/hooks/pre-commit", AgentHooks},
		{".git/config", AgentHooks},
		{"AGENTS.md", Guides},
		{"CLAUDE.md", Guides},
		{"docs/architecture.md", Guides},
		{"docs/review.md", Guides},
		{".github/pull_request_template.md", Guides},
		{"docs/adr/0001-x.md", ADR},
		{"docs/adr/My ADR.md", ADR},
		{"docs/adr/sub/0002.md", ADR},
		{"docs/adr", ADR},
		// not protected
		{".agents/skills/x/SKILL.md", ""},
		{".agents/plans/a.md", ""},
		{".agents/progress.md", ""},
		{".agents/run/runs/x", ""},
		{"docs/other.md", ""},
		{"src/main.go", ""},
		{"README.md", ""},
		{".claude/commands/x.md", ""},
		// tricks
		{"docs/../AGENTS.md", Guides},
		{"./AGENTS.md", Guides},
		{filepath.Join(d, "AGENTS.md"), Guides},
		{filepath.Join(d, "docs/../.agents/keel.yml"), Engine},
		{"link.yml", Engine},
		{"src/docs-link/review.md", Guides},
		{"src/../.agents/keel.lock", Engine},
		{"new/dir/../../AGENTS.md", Guides},
	}
	for _, c := range cases {
		class, ok := s.Match(c.path)
		if c.class == "" && ok || c.class != "" && (!ok || class != c.class) {
			t.Errorf("Match(%q) = %q, %v; want %q", c.path, class, ok, c.class)
		}
	}
}

func TestMatchViaSymlinkedRoot(t *testing.T) {
	d := repo(t)
	link := filepath.Join(t.TempDir(), "rootlink")
	if err := os.Symlink(d, link); err != nil {
		t.Skip("symlinks unavailable")
	}
	s := Load(link, cfg(t), false)
	for _, p := range []string{filepath.Join(link, "AGENTS.md"), filepath.Join(d, "AGENTS.md"), "AGENTS.md"} {
		if _, ok := s.Match(p); !ok {
			t.Errorf("%s not protected", p)
		}
	}
}

func TestMatchUserLevel(t *testing.T) {
	d := repo(t)
	home, _ := filepath.EvalSymlinks(t.TempDir())
	t.Setenv("HOME", home)
	s := Load(d, cfg(t), false)
	for _, rel := range []string{".claude/settings.json", ".claude/settings.local.json", ".copilot/settings.json", ".copilot/hooks/x.json", ".config/devin/config.json", ".devin/x"} {
		if class, ok := s.Match(filepath.Join(home, rel)); !ok || class != AgentHooks {
			t.Errorf("%s not protected", rel)
		}
	}
	if _, ok := s.Match(filepath.Join(home, ".claude/commands/x.md")); ok {
		t.Error("an unrelated user file is not protected")
	}
	if _, ok := s.Match("/etc/passwd"); ok {
		t.Error("/etc/passwd")
	}
	if _, ok := s.Match(filepath.Join(filepath.Dir(d), "elsewhere/AGENTS.md")); ok {
		t.Error("an AGENTS.md outside the repository is not ours")
	}
}

func TestMatchTree(t *testing.T) {
	d := repo(t)
	s := Load(d, cfg(t), false)
	for _, p := range []string{".agents", ".agents/baselines", ".agents/bin", "docs", "docs/adr", ".claude", ".git"} {
		if _, ok := s.MatchTree(p); !ok {
			t.Errorf("MatchTree(%q) = false", p)
		}
	}
	for _, p := range []string{"src", ".agents/plans", ".agents/skills", "node_modules"} {
		if _, ok := s.MatchTree(p); ok {
			t.Errorf("MatchTree(%q) = true", p)
		}
	}
	if _, ok := s.Match("docs"); ok {
		t.Error("Match (not tree) must not flag the docs directory itself")
	}
}

func TestSetupMode(t *testing.T) {
	d := repo(t)
	s := Load(d, nil, true)
	for _, p := range []string{"AGENTS.md", "CLAUDE.md", "docs/architecture.md", "docs/adr/0001.md", ".agents/keel.yml", ".agents/anything.txt",
		".github/agents/keel-reviewer.agent.md", ".github/pull_request_template.md", ".claude/settings.json", ".claude/agents/keel-reviewer.md", "docs/review.md", ".git/hooks/pre-commit"} {
		if _, ok := s.Match(p); !ok {
			t.Errorf("setup mode: %s not protected", p)
		}
	}
	for _, p := range []string{".agents/skills/x/SKILL.md", ".agents/plans/p.md", ".agents/run/handoff.md", ".agents/progress.md", ".agents/lessons.md", "src/a.ts", "README.md", "docs/notes.txt"} {
		if _, ok := s.Match(p); ok {
			t.Errorf("setup mode: %s protected", p)
		}
	}
}

func TestScriptConfigGlobs(t *testing.T) {
	d := repo(t)
	c, _ := config.Parse([]byte("version: 1\nscripts:\n  a: { run: x, config: [eslint.config.js, \"conf/**\"] }\n"))
	s := Load(d, c, false)
	for _, p := range []string{"eslint.config.js", "conf/a/b.json"} {
		if class, ok := s.Match(p); !ok || class != Config {
			t.Errorf("%s: %q %v", p, class, ok)
		}
	}
}

func TestOddNames(t *testing.T) {
	d := repo(t)
	s := Load(d, cfg(t), false)
	os.WriteFile(filepath.Join(d, "docs/adr/-rf.md"), nil, 0o644)
	for _, p := range []string{"docs/adr/-rf.md", "docs/adr/ação ünï.md", "docs/adr/a b/c d.md"} {
		if _, ok := s.Match(p); !ok {
			t.Errorf("%q", p)
		}
	}
	if _, ok := s.Match("src/-rf.md"); ok {
		t.Error("src/-rf.md")
	}
}

func TestLoadUserOnly(t *testing.T) {
	d := repo(t)
	home := filepath.Join(d, "home")
	s := LoadUser()
	if _, ok := s.Match(filepath.Join(home, ".claude/settings.json")); !ok {
		t.Error("user-level settings must be protected in a set without a repository")
	}
	if _, ok := s.Match(filepath.Join(d, "AGENTS.md")); ok {
		t.Error("a repository file is not protected by the user-only set")
	}
	if _, ok := s.Match("relative/path"); ok {
		t.Error("relative path")
	}
}

func TestUserLevelStaysProtectedWhenHomeIsInsideTheRepository(t *testing.T) {
	d := repo(t) // HOME is d/home, inside the root
	s := Load(d, cfg(t), false)
	if _, ok := s.Match(filepath.Join(d, "home/.claude/settings.json")); !ok {
		t.Error("a home directory inside the repository (a dotfiles repository) must keep its protection")
	}
}
