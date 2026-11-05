// Package protect answers one question: is this path one the agent must not
// write without the human confirming it? The protected set is fixed by kh
// (spec section 8.1) apart from the files each script names in config:.
package protect

import (
	"os"
	"path/filepath"
	"strings"

	"github.com/bmatcuk/doublestar/v4"

	"github.com/aether-labs-org/plugins/cli/kh/internal/config"
)

// Classes of protected paths.
const (
	Engine     = "engine"      // keel.yml, keel.lock, the wrapper, baselines, git hooks
	AgentHooks = "agent-hooks" // agent settings that can disable the hooks
	Guides     = "guides"      // AGENTS.md and the other guides, review.md, the PR template
	ADR        = "adr"         // everything under adr_dir
	Config     = "config"      // a file a script names in config:
)

type rule struct {
	glob  string
	class string
}

// Set is the protected set of one repository.
type Set struct {
	root, rootRaw string
	rules         []rule
	user          []rule // absolute paths outside the repository
}

var engineRules = []string{".agents/keel.yml", ".agents/keel.lock", ".agents/bin/**", ".agents/baselines/**", ".agents/githooks/**"}

var agentRules = []string{
	".claude/settings.json", ".claude/settings.local.json", ".claude/agents/keel-reviewer.md",
	".github/hooks/**", ".github/copilot/settings*.json", ".github/agents/keel-reviewer.agent.md",
	".devin/**", ".git/hooks/**", ".git/config",
}

// userRules are the user-level agent settings that can switch repository hooks
// off, relative to the home directory. The exact list is chosen here (spec
// section 20): Claude Code's settings files, Copilot CLI's settings and hooks,
// and Devin CLI's configuration directories.
var userRules = []string{
	".claude/settings.json", ".claude/settings.local.json",
	".copilot/settings.json", ".copilot/hooks/**",
	".config/devin/**", ".devin/**",
}

// Load builds the protected set. With cfg nil (the setup session, before the
// repository has a keel.yml) it protects the defaults of spec section 8.1 plus
// the files the setup writes: AGENTS.md, CLAUDE.md, docs/**/*.md, .agents/**
// (but not .agents/skills, which belongs to other tools, nor local state, plans
// and memory), .github/agents/** and the PR template.
func Load(root string, cfg *config.Config, setup bool) Set {
	s := Set{rootRaw: filepath.Clean(root), root: filepath.Clean(root)}
	if r, err := filepath.EvalSymlinks(root); err == nil {
		s.root = r
	}
	add := func(class string, globs ...string) {
		for _, g := range globs {
			if g = strings.TrimPrefix(filepath.ToSlash(g), "./"); g != "" {
				s.rules = append(s.rules, rule{g, class})
			}
		}
	}
	add(Engine, engineRules...)
	add(AgentHooks, agentRules...)
	add(Guides, "docs/review.md", ".github/pull_request_template.md")
	adrDir := config.DefaultADRDir
	if cfg != nil {
		adrDir = strings.TrimSuffix(cfg.ADRDir, "/")
		add(Guides, cfg.Guides...)
		for _, sc := range cfg.Scripts {
			add(Config, sc.Config...)
		}
	}
	add(ADR, adrDir, adrDir+"/**")
	if cfg == nil || setup {
		add(Guides, "AGENTS.md", "CLAUDE.md", "docs/**/*.md", ".github/agents/**")
		add(Engine, ".agents/**")
	}
	s.addUser()
	return s
}

func (s *Set) addUser() {
	if home, err := os.UserHomeDir(); err == nil && home != "" {
		for _, g := range userRules {
			s.user = append(s.user, rule{filepath.ToSlash(filepath.Join(home, g)), AgentHooks})
		}
	}
}

// LoadUser is the protected set of a path that is in no repository, or in one
// without a harness: only the user-level agent settings (a hook switched off there
// switches it off everywhere).
func LoadUser() Set {
	var s Set
	s.addUser()
	return s
}

// setupExempt are paths under .agents/ that the setup session may write freely.
func setupExempt(rel string) bool {
	for _, p := range []string{".agents/skills/", ".agents/run/", ".agents/plans/"} {
		if strings.HasPrefix(rel+"/", p) {
			return true
		}
	}
	return rel == ".agents/progress.md" || rel == ".agents/lessons.md"
}

// resolve returns p with symlinks resolved: the whole path when it exists,
// else its deepest existing parent plus the rest.
func resolve(p string) string {
	cur := filepath.Clean(p)
	var rest []string
	for {
		if r, err := filepath.EvalSymlinks(cur); err == nil {
			for i := len(rest) - 1; i >= 0; i-- {
				r = filepath.Join(r, rest[i])
			}
			return r
		}
		dir, base := filepath.Split(cur)
		dir = filepath.Clean(dir)
		if dir == cur || base == "" {
			return filepath.Clean(p)
		}
		rest = append(rest, base)
		cur = dir
	}
}

// candidates returns the slash-separated paths relative to the root that p can
// denote: as written (cleaned) and with symlinks resolved. ok=false marks an
// absolute path outside the repository in abs.
func (s Set) candidates(p string) (rels []string, abs []string) {
	if p == "" {
		return nil, nil
	}
	full := p
	if !filepath.IsAbs(p) {
		if s.rootRaw == "" {
			return nil, nil
		}
		full = filepath.Join(s.rootRaw, p)
	}
	full = filepath.Clean(full)
	seen := map[string]bool{}
	addAbs := func(a string) {
		a = filepath.ToSlash(a)
		if !seen["abs:"+a] {
			seen["abs:"+a] = true
			abs = append(abs, a)
		}
	}
	// the user-level rules are absolute: always offered as such, also when the
	// path lies inside the repository (a home directory that is itself a repository)
	addAbs(full)
	addAbs(resolve(full))
	if s.rootRaw == "" {
		return nil, abs
	}
	for _, c := range []struct{ path, root string }{
		{full, s.rootRaw}, {full, s.root}, {resolve(full), s.root},
	} {
		if r, err := filepath.Rel(c.root, c.path); err == nil && r != ".." && !strings.HasPrefix(r, ".."+string(filepath.Separator)) {
			r = filepath.ToSlash(r)
			if !seen[r] {
				seen[r] = true
				rels = append(rels, r)
			}
		}
	}
	return rels, abs
}

func globMatch(g, p string) bool {
	ok, err := doublestar.Match(g, p)
	return err == nil && ok
}

// Match reports whether path (absolute, or relative to the repository root) is
// protected, and the class that says why.
func (s Set) Match(path string) (class string, ok bool) {
	return s.match(path, false)
}

// MatchTree is Match, and also true for a directory that contains protected
// paths: removing or moving it removes them.
func (s Set) MatchTree(path string) (class string, ok bool) {
	return s.match(path, true)
}

func literalPrefix(glob string) string {
	if i := strings.IndexAny(glob, "*?[{"); i >= 0 {
		glob = glob[:i]
	}
	return glob
}

func (s Set) match(path string, tree bool) (string, bool) {
	rels, abs := s.candidates(path)
	for _, rel := range rels {
		if rel == "." {
			if tree {
				return Engine, true
			}
			continue
		}
		for _, r := range s.rules {
			if r.glob == ".agents/**" && setupExempt(rel) {
				continue
			}
			if globMatch(r.glob, rel) {
				return r.class, true
			}
			if strings.HasSuffix(r.glob, "/**") && rel == strings.TrimSuffix(r.glob, "/**") {
				return r.class, true
			}
			if tree && strings.HasPrefix(literalPrefix(r.glob), rel+"/") && !(r.glob == ".agents/**" && setupExempt(rel)) {
				return r.class, true
			}
		}
	}
	for _, a := range abs {
		for _, r := range s.user {
			if globMatch(r.glob, a) {
				return r.class, true
			}
		}
	}
	return "", false
}
