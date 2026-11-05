package hook

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/aether-labs-org/plugins/cli/bmax/internal/builtin"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/config"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/protect"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/root"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/shell"
)

var classWhy = map[string]string{
	protect.Engine:     "the harness engine or configuration",
	protect.AgentHooks: "the agent hook settings",
	protect.Guides:     "a guide",
	protect.ADR:        "an ADR (accepted ADRs are immutable)",
	protect.Config:     "a tool configuration a script protects with config:",
}

func isFileTool(tool string) bool {
	switch tool {
	case "Write", "Edit", "MultiEdit", "NotebookEdit":
		return true
	}
	return false
}

// absPath resolves a path as written by the agent against its working directory.
func absPath(rootDir, cwd, p string) string {
	if filepath.IsAbs(p) {
		return filepath.Clean(p)
	}
	if cwd == "" {
		cwd = rootDir
	}
	return filepath.Clean(filepath.Join(cwd, p))
}

func protectedWrite(shown, path, class, mode, how string) Decision {
	rel := path
	if shown != "" {
		if r, err := filepath.Rel(shown, path); err == nil && !strings.HasPrefix(r, "..") {
			rel = filepath.ToSlash(r)
		}
	}
	why := classWhy[class]
	if how == "shell" {
		return Decision{"deny", fmt.Sprintf("%s is protected (%s: %s). The agent may not change it through the shell: explain the change you want, and let the human confirm the edit or make it.", rel, class, why)}
	}
	if bypassMode(mode) {
		return Decision{"deny", fmt.Sprintf("%s is protected (%s: %s). The permission mode is %s, where asking is not guaranteed to prompt: the human has to switch mode or make the change.", rel, class, why, mode)}
	}
	return Decision{"ask", fmt.Sprintf("%s is protected (%s: %s). Writes to the harness need the human's confirmation: say what you want to change and why.", rel, class, why)}
}

// invalidRepoWrite: the repository that contains the target has a .agents/bmax.yml
// bmax cannot read, so bmax cannot tell what is protected there: everything is.
func invalidRepoWrite(top, path, problem, mode, how string) Decision {
	msg := fmt.Sprintf("%s is in the repository %s, whose .agents/bmax.yml cannot be used (%s), so bmax cannot tell what is protected there.", path, top, problem)
	if how == "shell" {
		return Decision{"deny", msg + " The agent may not write there through the shell: the human has to fix the file or make the change."}
	}
	if bypassMode(mode) {
		return Decision{"deny", msg + " The permission mode is " + mode + ", where asking is not guaranteed to prompt: the human has to switch mode or make the change."}
	}
	return Decision{"ask", msg + " Say what you want to change and why."}
}

// repos resolves, once per invocation, the protected set of the repository that
// contains a target. The project (root, cfg) is the repository the hook is
// registered in; a target in another repository (a nested one, a worktree, a
// sibling checkout) is judged by that repository's own bmax.yml, because a write
// there is a write to that harness, whatever the working directory is.
type repos struct {
	root  string // the project root; "" when the session has none
	cfg   *config.Config
	setup bool
	sets  map[string]*repoSet
}

type repoSet struct {
	set     protect.Set
	invalid string // the problem with the repository's bmax.yml; "" when usable
	cfg     *config.Config
}

func newRepos(rootDir string, cfg *config.Config, setup bool) *repos {
	if rootDir != "" {
		if r, err := filepath.EvalSymlinks(rootDir); err == nil {
			rootDir = r
		}
	}
	return &repos{root: filepath.Clean(rootDir), cfg: cfg, setup: setup, sets: map[string]*repoSet{}}
}

// of returns the set of the repository whose top-level is top ("" = in no repository).
func (r *repos) of(top string) *repoSet {
	if rs, ok := r.sets[top]; ok {
		return rs
	}
	rs := &repoSet{}
	switch {
	case top == "":
		rs.set = protect.LoadUser()
	case r.root != "" && top == r.root:
		rs.cfg = r.cfg
		rs.set = protect.Load(top, r.cfg, r.setup)
	default:
		if _, err := os.Stat(filepath.Join(top, ".agents", "bmax.yml")); err == nil {
			cfg, err := config.LoadValid(top, builtin.Default().Validator())
			switch {
			case err == nil:
				rs.cfg = cfg
				rs.set = protect.Load(top, cfg, r.setup)
			case r.setup:
				rs.set = protect.Load(top, nil, true) // the setup session is how a broken config gets fixed
			default:
				rs.invalid = firstLine(err.Error())
			}
		} else if r.setup {
			rs.set = protect.Load(top, nil, true)
		} else {
			rs.set = protect.LoadUser()
		}
	}
	r.sets[top] = rs
	return rs
}

// check decides a write to path against EVERY enclosing repository, nearest first. A real
// nested repository or worktree is judged by its own set (the outer root-relative patterns
// do not match inside it); judging only the nearest one would let a fake .git entry
// (an empty directory, a gitdir file) created inside .agents/ or .claude/ unprotect the files there.
func (r *repos) check(path string, tree bool, mode, how string) (Decision, bool) {
	tops := []string{""}
	if enc := root.Enclosing(path); len(enc) > 0 {
		tops = enc
	}
	for _, top := range tops {
		rs := r.of(top)
		if rs.invalid != "" {
			return invalidRepoWrite(top, path, rs.invalid, mode, how), true
		}
		var class string
		var hit bool
		if tree {
			class, hit = rs.set.MatchTree(path)
		} else {
			class, hit = rs.set.Match(path)
		}
		if hit {
			return protectedWrite(r.root, path, class, mode, how), true
		}
	}
	return Decision{}, false
}

// configAt is the usable config of the repository that contains dir, nil when
// there is none (script interception needs a harness where the command runs).
func (r *repos) configAt(dir string) *config.Config {
	top := root.Containing(dir)
	if top == "" {
		return nil
	}
	return r.of(top).cfg
}

// declaredSignatures maps the command signature of each declared run: command
// to the scripts that declare it.
func declaredSignatures(cfg *config.Config) map[string][]string {
	m := map[string][]string{}
	if cfg == nil {
		return m
	}
	for id, s := range cfg.Scripts {
		if s.Run == "" {
			continue
		}
		if sig := shell.RunSignature(s.Run); sig != "" {
			m[sig] = append(m[sig], id)
		}
	}
	for _, ids := range m {
		sort.Strings(ids)
	}
	return m
}

// PreToolUse decides whether an agent tool call may go ahead (spec 8.2).
// rootDir and cfg are the project (cfg nil in setup mode before the repository has
// a bmax.yml; rootDir "" when the session is in no project): the fail-safe checks
// belong to the caller. Each write target is judged by the repository that contains it.
func PreToolUse(rootDir string, cfg *config.Config, p Payload, setup bool) Decision {
	if p.Cwd == "" {
		p.Cwd = rootDir
	}
	if p.Cwd == "" {
		p.Cwd, _ = os.Getwd()
	}
	rs := newRepos(rootDir, cfg, setup)
	switch {
	case isFileTool(p.Tool):
		if p.FilePath == "" {
			return Decision{Kind: "allow"}
		}
		path := absPath(rootDir, p.Cwd, p.FilePath)
		if d, hit := rs.check(path, false, p.PermissionMode, "tool"); hit {
			return d
		}
	case p.Tool == "Bash":
		return bashDecision(rootDir, rs, p, setup)
	}
	return Decision{Kind: "allow"}
}

func bashDecision(rootDir string, rs *repos, p Payload, setup bool) Decision {
	segs, ok := shell.Split(p.Command)
	cwd := p.Cwd
	var sigs map[string][]string
	if ok && !setup {
		// interception follows the harness of the repository the command runs in
		sigs = declaredSignatures(rs.configAt(cwd))
	}
	for _, seg := range segs {
		if reason, bad := shell.Forbidden(seg); bad {
			return Decision{"deny", reason + ". Ask the human to run it, or to change the harness."}
		}
		if len(seg.Words) > 0 && seg.Words[0] == "cd" && len(seg.Words) > 1 {
			cwd = absPath(rootDir, cwd, seg.Words[1])
		}
		targets := shell.WriteTargets(seg)
		targets = append(targets, patchTargets(rootDir, cwd, seg)...)
		for _, t := range targets {
			path := absPath(rootDir, cwd, t)
			if d, hit := rs.check(path, shell.Destructive(seg), p.PermissionMode, "shell"); hit {
				return d
			}
		}
		if len(sigs) > 0 && !shell.InfoOnly(seg) {
			if scripts := sigs[shell.Signature(seg)]; len(scripts) > 0 {
				return Decision{"deny", fmt.Sprintf("`%s` is declared as script %q in .agents/bmax.yml. Run `sh .agents/bin/bmax run %s` instead, and do not pipe its output (bmax already reduces it). `sh .agents/bin/bmax run -- <command>` runs an undeclared command the same way.",
					shell.Signature(seg), scripts[0], scripts[0])}
			}
		}
	}
	return Decision{Kind: "allow"}
}

// patchTargets reads the patch files named by git apply / git am / patch and
// returns the paths they modify.
func patchTargets(rootDir, cwd string, seg shell.Segment) []string {
	if len(seg.Words) == 0 {
		return nil
	}
	head := filepath.Base(seg.Words[0])
	var files []string
	switch head {
	case "git":
		sub, rest, _ := shell.GitSub(seg.Words)
		if sub == "apply" || sub == "am" {
			for _, a := range rest {
				if !strings.HasPrefix(a, "-") {
					files = append(files, a)
				}
			}
		}
	case "patch":
		for _, a := range seg.Words[1:] {
			if !strings.HasPrefix(a, "-") {
				files = append(files, a)
			}
		}
		files = append(files, seg.Redirects...)
	}
	var out []string
	for _, f := range files {
		if b, err := os.ReadFile(absPath(rootDir, cwd, f)); err == nil && len(b) < 4<<20 {
			out = append(out, shell.PatchTargets(string(b))...)
		}
	}
	return out
}
