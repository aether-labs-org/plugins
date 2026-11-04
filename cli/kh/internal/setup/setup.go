// Package setup is kh setup: the per-clone step that a repository cannot carry
// in git. Native git hooks are activated (core.hooksPath is local
// configuration); with an external hook manager, kh only says which manager
// config must call the wrapper.
package setup

import (
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/aether-labs-org/plugins/cli/kh/internal/config"
	"github.com/aether-labs-org/plugins/cli/kh/internal/scope"
)

// HooksDir is where the native git hooks live.
const HooksDir = ".agents/githooks"

// Run performs the setup of one clone and prints what it did. It writes only
// local git configuration and the exec bits of the hook files.
func Run(root string, cfg *config.Config, out io.Writer) error {
	g := cfg.Githooks
	if g.Mode == "" && g.PreCommit == "" && g.PrePush == "" && g.CommitMsg == "" {
		fmt.Fprintln(out, "git hooks: not adopted (no githooks: in .agents/keel.yml)")
		return nil
	}
	if g.Mode == "external" {
		fmt.Fprintln(out, "git hooks: external mode - call .agents/bin/kh from your hook manager's config (husky, lefthook, pre-commit):")
		for _, l := range externalLines(g) {
			fmt.Fprintln(out, "  "+l)
		}
		return nil
	}
	dir := filepath.Join(root, filepath.FromSlash(HooksDir))
	entries, err := os.ReadDir(dir)
	if err != nil {
		return fmt.Errorf("native git hooks are configured but %s is missing", HooksDir)
	}
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		p := filepath.Join(dir, e.Name())
		if err := os.Chmod(p, 0o755); err != nil {
			return fmt.Errorf("chmod %s: %w", p, err)
		}
	}
	if _, err := scope.Git(root, "config", "core.hooksPath", HooksDir); err != nil {
		return fmt.Errorf("git config core.hooksPath: %w", err)
	}
	fmt.Fprintf(out, "git hooks: core.hooksPath = %s (%d hook files executable)\n", HooksDir, countFiles(entries))
	return nil
}

func countFiles(es []os.DirEntry) int {
	n := 0
	for _, e := range es {
		if !e.IsDir() {
			n++
		}
	}
	return n
}

func externalLines(g config.Githooks) []string {
	var l []string
	if g.PreCommit != "" {
		l = append(l, `pre-commit:  sh .agents/bin/kh gate `+g.PreCommit)
	}
	if g.CommitMsg != "" {
		l = append(l, `commit-msg:  sh .agents/bin/kh hook commit-msg "$1"`)
	}
	if g.PrePush != "" {
		l = append(l, `pre-push:    sh .agents/bin/kh gate `+g.PrePush)
	}
	return l
}
