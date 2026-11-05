// Package lock reads .agents/bmax.lock, the pin of the bmax version of a
// repository. The format is line-based so the sh wrapper can read it too.
package lock

import (
	"fmt"
	"os"
	"regexp"
	"strings"
)

// Platforms are the keys of the lock, in file order.
var Platforms = []string{"linux-amd64", "linux-arm64", "darwin-amd64", "darwin-arm64"}

var hexRE = regexp.MustCompile(`^[0-9a-f]{64}$`)

// Lock is the parsed pin.
type Lock struct {
	Version string
	SHA256  map[string]string // keys: Platforms
}

// Read parses a lock file; CRLF is tolerated.
func Read(path string) (Lock, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return Lock{}, err
	}
	l := Lock{SHA256: map[string]string{}}
	for i, line := range strings.Split(string(b), "\n") {
		line = strings.TrimRight(line, "\r")
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			return Lock{}, fmt.Errorf("%s:%d: expected key=value", path, i+1)
		}
		if k == "version" {
			l.Version = v
			continue
		}
		known := false
		for _, p := range Platforms {
			if p == k {
				known = true
			}
		}
		if !known {
			return Lock{}, fmt.Errorf("%s:%d: unknown key %q", path, i+1, k)
		}
		if !hexRE.MatchString(v) {
			return Lock{}, fmt.Errorf("%s:%d: %s must be 64 lowercase hex characters", path, i+1, k)
		}
		l.SHA256[k] = v
	}
	if l.Version == "" {
		return Lock{}, fmt.Errorf("%s: missing version=", path)
	}
	return l, nil
}

// Format renders the lock file.
func Format(l Lock) string {
	var b strings.Builder
	b.WriteString("# bmax.lock - bmax pin; written by Baymax, do not edit by hand\n")
	fmt.Fprintf(&b, "version=%s\n", l.Version)
	for _, p := range Platforms {
		if h, ok := l.SHA256[p]; ok {
			fmt.Fprintf(&b, "%s=%s\n", p, h)
		}
	}
	return b.String()
}

// Check returns nil when the binary is the pinned version.
func Check(l Lock, binaryVersion string) error {
	if l.Version == binaryVersion {
		return nil
	}
	return fmt.Errorf("pin mismatch: bmax.lock pins %s, this bmax is %s", l.Version, binaryVersion)
}
