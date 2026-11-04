// Package tree fingerprints the git work tree so that a stored result can be
// compared with the current state without re-running anything.
package tree

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"os/exec"
	"sort"
	"strings"

	"github.com/aether-labs-org/plugins/cli/kh/internal/result"
)

const runPrefix = ".agents/run/"

func git(root string, args ...string) ([]byte, error) {
	cmd := exec.Command("git", append([]string{"-c", "core.quotepath=off"}, args...)...)
	cmd.Dir = root
	var out bytes.Buffer
	cmd.Stdout = &out
	err := cmd.Run()
	return out.Bytes(), err
}

// Fingerprint returns HEAD and a hash of the uncommitted state: the diff
// against HEAD (or the index before the first commit) plus the content hash of
// every untracked file. Paths under .agents/run/ (the evidence) are excluded.
// Outside a git work tree both fields are empty.
func Fingerprint(root string) result.Tree {
	var t result.Tree
	if out, err := git(root, "rev-parse", "--is-inside-work-tree"); err != nil || strings.TrimSpace(string(out)) != "true" {
		return t
	}
	exclude := []string{"--", ".", ":(exclude).agents/run"}
	var diff []byte
	if out, err := git(root, "rev-parse", "-q", "--verify", "HEAD"); err == nil {
		t.Head = strings.TrimSpace(string(out))
		diff, _ = git(root, append([]string{"diff", "HEAD", "--binary"}, exclude...)...)
	} else {
		diff, _ = git(root, append([]string{"diff", "--cached", "--binary"}, exclude...)...)
	}
	h := sha256.New()
	h.Write(diff)

	if out, err := git(root, "ls-files", "--others", "--exclude-standard", "-z"); err == nil {
		var paths []string
		for _, p := range strings.Split(string(out), "\x00") {
			if p != "" && !strings.HasPrefix(p, runPrefix) {
				paths = append(paths, p)
			}
		}
		sort.Strings(paths)
		for _, p := range paths {
			sum, _ := git(root, "hash-object", "--", p) // unreadable file: empty hash
			h.Write([]byte(p))
			h.Write([]byte{0})
			h.Write([]byte(strings.TrimSpace(string(sum))))
			h.Write([]byte{'\n'})
		}
	}
	t.DiffHash = hex.EncodeToString(h.Sum(nil))
	return t
}
