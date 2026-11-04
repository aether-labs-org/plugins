package hook

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/aether-labs-org/plugins/cli/kh/internal/config"
	"github.com/aether-labs-org/plugins/cli/kh/internal/protect"
	"github.com/aether-labs-org/plugins/cli/kh/internal/shell"
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
func absPath(root, cwd, p string) string {
	if filepath.IsAbs(p) {
		return filepath.Clean(p)
	}
	if cwd == "" {
		cwd = root
	}
	return filepath.Clean(filepath.Join(cwd, p))
}

func protectedWrite(set protect.Set, root, path, class, mode, how string) Decision {
	rel := path
	if r, err := filepath.Rel(root, path); err == nil && !strings.HasPrefix(r, "..") {
		rel = filepath.ToSlash(r)
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
// cfg may be nil (setup mode before the repository has a keel.yml).
func PreToolUse(root string, cfg *config.Config, p Payload, setup bool) Decision {
	set := protect.Load(root, cfg, setup)
	switch {
	case isFileTool(p.Tool):
		if p.FilePath == "" {
			return Decision{Kind: "allow"}
		}
		path := absPath(root, p.Cwd, p.FilePath)
		if class, ok := set.Match(path); ok {
			return protectedWrite(set, root, path, class, p.PermissionMode, "tool")
		}
	case p.Tool == "Bash":
		return bashDecision(root, cfg, set, p, setup)
	}
	return Decision{Kind: "allow"}
}

func bashDecision(root string, cfg *config.Config, set protect.Set, p Payload, setup bool) Decision {
	segs, ok := shell.Split(p.Command)
	cwd := p.Cwd
	if cwd == "" {
		cwd = root
	}
	var sigs map[string][]string
	if ok && cfg != nil && !setup {
		sigs = declaredSignatures(cfg)
	}
	for _, seg := range segs {
		if reason, bad := shell.Forbidden(seg); bad {
			return Decision{"deny", reason + ". Ask the human to run it, or to change the harness."}
		}
		if len(seg.Words) > 0 && seg.Words[0] == "cd" && len(seg.Words) > 1 {
			cwd = absPath(root, cwd, seg.Words[1])
		}
		targets := shell.WriteTargets(seg)
		targets = append(targets, patchTargets(root, cwd, seg)...)
		for _, t := range targets {
			path := absPath(root, cwd, t)
			var class string
			var hit bool
			if shell.Destructive(seg) {
				class, hit = set.MatchTree(path)
			} else {
				class, hit = set.Match(path)
			}
			if hit {
				return protectedWrite(set, root, path, class, p.PermissionMode, "shell")
			}
		}
		if sigs != nil {
			if scripts := sigs[shell.Signature(seg)]; len(scripts) > 0 {
				return Decision{"deny", fmt.Sprintf("`%s` is declared as script %q in .agents/keel.yml. Run `sh .agents/bin/kh run %s` instead, and do not pipe its output (kh already reduces it). `sh .agents/bin/kh run -- <command>` runs an undeclared command the same way.",
					shell.Signature(seg), scripts[0], scripts[0])}
			}
		}
	}
	return Decision{Kind: "allow"}
}

// patchTargets reads the patch files named by git apply / git am / patch and
// returns the paths they modify.
func patchTargets(root, cwd string, seg shell.Segment) []string {
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
		if b, err := os.ReadFile(absPath(root, cwd, f)); err == nil && len(b) < 4<<20 {
			out = append(out, shell.PatchTargets(string(b))...)
		}
	}
	return out
}
