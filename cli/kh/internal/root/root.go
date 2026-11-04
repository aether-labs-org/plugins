// Package root locates the repository root: the git top-level, which must
// contain .agents/keel.yml. One harness per git repository.
package root

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

var (
	// ErrNotFound: the git top-level has no .agents/keel.yml.
	ErrNotFound = errors.New("no .agents/keel.yml at the repository root")
	// ErrNotGit: start is not inside a git work tree.
	ErrNotGit = errors.New("not a git repository")
	// ErrNested: a .agents/keel.yml exists below the top-level.
	ErrNested = errors.New("nested .agents/keel.yml - one harness per git repository")
)

type nestedError struct{ rel string }

func (e *nestedError) Error() string {
	return fmt.Sprintf("nested .agents/keel.yml at %s - one harness per git repository", e.rel)
}
func (e *nestedError) Is(target error) bool { return target == ErrNested }

// Toplevel returns the git top-level of start (a worktree's own top-level when
// .git is a file), or ErrNotGit.
func Toplevel(start string) (string, error) {
	abs, err := filepath.Abs(start)
	if err != nil {
		return "", err
	}
	cmd := exec.Command("git", "rev-parse", "--show-toplevel")
	cmd.Dir = abs
	var out bytes.Buffer
	cmd.Stdout = &out
	if err := cmd.Run(); err != nil {
		if _, lookErr := exec.LookPath("git"); lookErr != nil {
			return "", errors.New("git not found")
		}
		return "", ErrNotGit
	}
	top := strings.TrimRight(out.String(), "\r\n")
	if top == "" {
		return "", ErrNotGit
	}
	if r, err := filepath.EvalSymlinks(top); err == nil {
		top = r
	}
	return filepath.Clean(top), nil
}

func hasKeel(dir string) bool {
	st, err := os.Stat(filepath.Join(dir, ".agents", "keel.yml"))
	return err == nil && st.Mode().IsRegular()
}

// Find returns the git top-level containing .agents/keel.yml. A keel.yml in any
// directory between start and the top-level (exclusive) is ErrNested.
func Find(start string) (string, error) {
	top, err := Toplevel(start)
	if err != nil {
		return "", err
	}
	abs, err := filepath.Abs(start)
	if err != nil {
		return "", err
	}
	if r, err := filepath.EvalSymlinks(abs); err == nil {
		abs = r
	}
	for dir := abs; dir != top; dir = filepath.Dir(dir) {
		if rel, err := filepath.Rel(top, dir); err != nil || strings.HasPrefix(rel, "..") {
			break
		}
		if hasKeel(dir) {
			rel, _ := filepath.Rel(top, dir)
			return "", &nestedError{filepath.ToSlash(rel)}
		}
		if filepath.Dir(dir) == dir {
			break
		}
	}
	if !hasKeel(top) {
		return "", ErrNotFound
	}
	return top, nil
}
