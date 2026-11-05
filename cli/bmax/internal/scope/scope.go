// Package scope decides which files a script sees: the files changed relative
// to a base, the tracked files, glob matching and argument batching.
package scope

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"sort"
	"strings"
)

// Base is what a gate compares the work tree with.
type Base string

// The change bases of a gate.
const (
	Worktree Base = "worktree" // tracked diff against HEAD plus untracked files
	Staged   Base = "staged"   // files in the index
	Branch   Base = "branch"   // work tree against the branch base
)

func git(root string, args ...string) ([]byte, error) {
	cmd := exec.Command("git", args...)
	cmd.Dir = root
	var out, errb bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &errb
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("git %s: %v: %s", strings.Join(args, " "), err, strings.TrimSpace(errb.String()))
	}
	return out.Bytes(), nil
}

func split(b []byte) []string {
	var out []string
	for _, p := range bytes.Split(b, []byte{0}) {
		if len(p) > 0 {
			out = append(out, string(p))
		}
	}
	return out
}

func hasHead(root string) bool {
	_, err := git(root, "rev-parse", "-q", "--verify", "HEAD^{commit}")
	return err == nil
}

func normalize(files []string) []string {
	seen := map[string]bool{}
	out := make([]string, 0, len(files))
	for _, f := range files {
		if !seen[f] {
			seen[f] = true
			out = append(out, f)
		}
	}
	sort.Strings(out)
	return out
}

// existing keeps the paths that exist in the work tree (a staged file that was
// deleted again, or a submodule, is dropped).
func existing(root string, files []string) []string {
	out := files[:0]
	for _, f := range files {
		if _, err := os.Lstat(root + "/" + f); err == nil {
			out = append(out, f)
		}
	}
	return out
}

// Changed lists the files changed under b: repo-relative, slash-separated,
// sorted, without duplicates, without deleted files.
func Changed(root string, b Base) ([]string, error) {
	var all []string
	add := func(args ...string) error {
		out, err := git(root, args...)
		if err != nil {
			return err
		}
		all = append(all, split(out)...)
		return nil
	}
	diff := func(extra ...string) error {
		args := append([]string{"diff", "--name-only", "-z", "--no-renames", "--diff-filter=d"}, extra...)
		return add(args...)
	}
	untracked := func() error { return add("ls-files", "-z", "--others", "--exclude-standard") }

	switch b {
	case Staged:
		if err := diff("--cached"); err != nil {
			return nil, err
		}
	case Worktree, Branch:
		base := "HEAD"
		if b == Branch {
			bb, err := BranchBase(root)
			if err != nil {
				return nil, err
			}
			base = bb
		}
		if base == "" || (base == "HEAD" && !hasHead(root)) {
			// unborn HEAD: everything in the index or untracked counts
			if err := add("ls-files", "-z", "--cached"); err != nil {
				return nil, err
			}
		} else if err := diff(base); err != nil {
			return nil, err
		}
		if err := untracked(); err != nil {
			return nil, err
		}
	default:
		return nil, fmt.Errorf("unknown change base %q", b)
	}
	return normalize(existing(root, all)), nil
}

// BranchBase is the commit a branch gate compares with: BMAX_GUARD_BASE, else
// the merge-base of HEAD and origin/HEAD, else HEAD. An unborn HEAD returns ""
// and no error.
func BranchBase(root string) (string, error) {
	if v := os.Getenv("BMAX_GUARD_BASE"); v != "" {
		return v, nil
	}
	if !hasHead(root) {
		return "", nil
	}
	if out, err := git(root, "merge-base", "HEAD", "refs/remotes/origin/HEAD"); err == nil {
		if s := strings.TrimSpace(string(out)); s != "" {
			return s, nil
		}
	}
	out, err := git(root, "rev-parse", "HEAD")
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

// Tracked lists every tracked file (git ls-files).
func Tracked(root string) ([]string, error) {
	out, err := git(root, "ls-files", "-z")
	if err != nil {
		return nil, err
	}
	return normalize(existing(root, split(out))), nil
}

// Candidates lists every file a rule may look at: tracked plus untracked
// not-ignored files (git ls-files --cached --others --exclude-standard).
func Candidates(root string) ([]string, error) {
	out, err := git(root, "ls-files", "-z", "--cached", "--others", "--exclude-standard")
	if err != nil {
		return nil, err
	}
	return normalize(existing(root, split(out))), nil
}

// Git runs git in root and returns its stdout; for packages that need history.
func Git(root string, args ...string) ([]byte, error) { return git(root, args...) }

// GitAllowFail runs git and returns its stdout even when it exits non-zero
// (git merge-tree exits 1 on conflicts and still prints them).
func GitAllowFail(root string, args ...string) []byte {
	cmd := exec.Command("git", args...)
	cmd.Dir = root
	var out bytes.Buffer
	cmd.Stdout = &out
	_ = cmd.Run()
	return out.Bytes()
}
