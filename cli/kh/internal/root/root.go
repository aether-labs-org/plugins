// Package root locates the repository root: the nearest directory, walking
// upward, that contains .agents/keel.yml.
package root

import (
	"errors"
	"os"
	"path/filepath"
)

// ErrNotFound is returned when no .agents/keel.yml exists in start or above.
var ErrNotFound = errors.New("no .agents/keel.yml here or in any parent directory")

// Find returns the absolute directory that contains .agents/keel.yml, walking
// up from start.
func Find(start string) (string, error) {
	dir, err := filepath.Abs(start)
	if err != nil {
		return "", err
	}
	for {
		st, err := os.Stat(filepath.Join(dir, ".agents", "keel.yml"))
		if err == nil && st.Mode().IsRegular() {
			return dir, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", ErrNotFound
		}
		dir = parent
	}
}
