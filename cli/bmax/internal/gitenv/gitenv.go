// Package gitenv knows which environment variables tie a git command to one repository.
//
// A git hook runs with GIT_DIR, GIT_INDEX_FILE, GIT_WORK_TREE and friends exported, and every git command started
// below it, in whatever directory, then acts on THAT repository: a script that runs `git init`, `git config` or
// `git commit` in a temporary directory rewrites the repository being committed or pushed. bmax therefore removes
// these variables from the environment of the scripts it runs. Its own git calls keep the inherited environment
// (the commit gate must see the index of `git commit -a`).
package gitenv

import (
	"os"
	"os/exec"
	"strings"
	"sync"
)

// fallback is the output of `git rev-parse --local-env-vars` of git 2.53, used when git cannot be run and to
// cover names an older git does not list. Names the installed git prints are added to it.
var fallback = []string{
	"GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_CONFIG", "GIT_CONFIG_PARAMETERS", "GIT_CONFIG_COUNT", "GIT_OBJECT_DIRECTORY",
	"GIT_DIR", "GIT_WORK_TREE", "GIT_IMPLICIT_WORK_TREE", "GIT_GRAFT_FILE", "GIT_INDEX_FILE", "GIT_NO_REPLACE_OBJECTS",
	"GIT_REPLACE_REF_BASE", "GIT_PREFIX", "GIT_SHALLOW_FILE", "GIT_COMMON_DIR", "GIT_NAMESPACE",
}

var (
	once  sync.Once
	names []string
)

// Names returns the repository-local variables, computed once per process.
func Names() []string {
	once.Do(func() {
		seen := map[string]bool{}
		add := func(n string) {
			if n != "" && !seen[n] {
				seen[n] = true
				names = append(names, n)
			}
		}
		if out, err := exec.Command("git", "rev-parse", "--local-env-vars").Output(); err == nil {
			for _, n := range strings.Fields(string(out)) {
				add(n)
			}
		}
		for _, n := range fallback {
			add(n)
		}
	})
	return names
}

// Strip returns env (KEY=value entries) without the repository-local git variables.
func Strip(env []string) []string {
	drop := map[string]bool{}
	for _, n := range Names() {
		drop[n] = true
	}
	out := make([]string, 0, len(env))
	for _, e := range env {
		k, _, _ := strings.Cut(e, "=")
		if !drop[k] {
			out = append(out, e)
		}
	}
	return out
}

// Unset removes the repository-local variables from the environment of this process (the tests use it so
// that a `go test` started from a hook cannot act on the repository of the hook).
func Unset() {
	for _, n := range Names() {
		os.Unsetenv(n)
	}
}
