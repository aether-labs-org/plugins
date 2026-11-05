package gitenv_test

import (
	"os"
	"os/exec"
	"strings"
	"testing"

	"github.com/aether-labs-org/plugins/cli/kh/internal/gitenv"
)

func TestNamesIncludeTheRepositoryLocalVariables(t *testing.T) {
	have := map[string]bool{}
	for _, n := range gitenv.Names() {
		have[n] = true
	}
	for _, want := range []string{"GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY",
		"GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_PREFIX", "GIT_CONFIG_PARAMETERS", "GIT_CONFIG_COUNT", "GIT_NAMESPACE"} {
		if !have[want] {
			t.Errorf("%s missing from %v", want, gitenv.Names())
		}
	}
	// what git itself says is covered
	if out, err := exec.Command("git", "rev-parse", "--local-env-vars").Output(); err == nil {
		for _, n := range strings.Fields(string(out)) {
			if !have[n] {
				t.Errorf("git lists %s, gitenv does not", n)
			}
		}
	}
	// the variables that are about the user, not the repository, are never listed
	for _, keep := range []string{"GIT_SSH_COMMAND", "GIT_EDITOR", "GIT_ASKPASS", "GIT_AUTHOR_NAME", "GIT_TERMINAL_PROMPT"} {
		if have[keep] {
			t.Errorf("%s must not be stripped", keep)
		}
	}
}

func TestStrip(t *testing.T) {
	in := []string{"PATH=/bin", "GIT_DIR=/r/.git", "GIT_WORK_TREE=/r", "GIT_INDEX_FILE=/r/.git/index", "GIT_COMMON_DIR=/r/.git",
		"HOME=/h", "GIT_SSH_COMMAND=ssh -i k", "GIT_EDITOR=true", "GIT_CONFIG_PARAMETERS='a.b=c'"}
	got := strings.Join(gitenv.Strip(in), "|")
	if got != "PATH=/bin|HOME=/h|GIT_SSH_COMMAND=ssh -i k|GIT_EDITOR=true" {
		t.Fatalf("%s", got)
	}
}

func TestUnset(t *testing.T) {
	t.Setenv("GIT_DIR", "/x")
	t.Setenv("GIT_INDEX_FILE", "/y")
	t.Setenv("GIT_EDITOR", "true")
	gitenv.Unset()
	if os.Getenv("GIT_DIR") != "" || os.Getenv("GIT_INDEX_FILE") != "" || os.Getenv("GIT_EDITOR") != "true" {
		t.Fatal("Unset must clear the repository-local variables and nothing else")
	}
}
