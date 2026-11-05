// Package root locates the repository root: the git top-level, which must
// contain .agents/bmax.yml. One harness per git repository.
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
	// ErrNotFound: the git top-level has no .agents/bmax.yml.
	ErrNotFound = errors.New("no .agents/bmax.yml at the repository root")
	// ErrNotGit: start is not inside a git work tree.
	ErrNotGit = errors.New("not a git repository")
	// ErrNested: a .agents/bmax.yml exists below the top-level.
	ErrNested = errors.New("nested .agents/bmax.yml - one harness per git repository")
)

type nestedError struct{ rel string }

func (e *nestedError) Error() string {
	return fmt.Sprintf("nested .agents/bmax.yml at %s - one harness per git repository", e.rel)
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

func hasBmax(dir string) bool {
	st, err := os.Stat(filepath.Join(dir, ".agents", "bmax.yml"))
	return err == nil && st.Mode().IsRegular()
}

// Find returns the git top-level containing .agents/bmax.yml. A bmax.yml in any
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
		if hasBmax(dir) {
			rel, _ := filepath.Rel(top, dir)
			return "", &nestedError{filepath.ToSlash(rel)}
		}
		if filepath.Dir(dir) == dir {
			break
		}
	}
	if !hasBmax(top) {
		return "", ErrNotFound
	}
	return top, nil
}

// EnvVar names the variable that pins the root of a command: the wrapper of a
// repository exports it, so a command resolves the project from where the wrapper
// lives and not from the working directory (which an agent session can move into
// another repository).
const EnvVar = "BMAX_ROOT"

// FromEnv resolves the value of BMAX_ROOT: it must be the top-level of a git work
// tree (a worktree's own top-level when .git is a file) and must contain
// .agents/bmax.yml.
func FromEnv(value string) (string, error) {
	top, err := Pinned(value)
	if err != nil {
		return "", err
	}
	if !hasBmax(top) {
		return "", ErrNotFound
	}
	return top, nil
}

// Pinned is FromEnv without the bmax.yml requirement.
func Pinned(value string) (string, error) {
	abs, err := filepath.Abs(value)
	if err != nil {
		return "", err
	}
	top, err := Toplevel(abs)
	if err != nil {
		return "", fmt.Errorf("%s=%s is not inside a git repository", EnvVar, value)
	}
	want := abs
	if r, err := filepath.EvalSymlinks(abs); err == nil {
		want = r
	}
	if filepath.Clean(want) != top {
		return "", fmt.Errorf("%s=%s is not a git top-level (the top-level is %s)", EnvVar, value, top)
	}
	return top, nil
}

// Containing returns the top-level of the git repository that contains path: the
// nearest ancestor (the path itself included) holding a .git entry, found from the
// nearest existing directory with symlinks resolved. It does not need git to run
// and works inside a .git directory. "" means path is outside any repository.
func Containing(path string) string {
	abs, err := filepath.Abs(path)
	if err != nil {
		return ""
	}
	cur := abs
	for {
		if r, err := filepath.EvalSymlinks(cur); err == nil {
			cur = r
			break
		}
		dir := filepath.Dir(cur)
		if dir == cur {
			return ""
		}
		cur = dir
	}
	if st, err := os.Stat(cur); err == nil && !st.IsDir() {
		cur = filepath.Dir(cur)
	}
	return nearestGit(cur)
}

// Enclosing returns every repository top-level that contains path, nearest first.
func Enclosing(path string) []string {
	var out []string
	cur := Containing(path)
	for cur != "" {
		out = append(out, cur)
		parent := filepath.Dir(cur)
		if parent == cur {
			break
		}
		cur = nearestGit(parent)
	}
	return out
}

func nearestGit(dir string) string {
	for {
		if _, err := os.Lstat(filepath.Join(dir, ".git")); err == nil {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return ""
		}
		dir = parent
	}
}
