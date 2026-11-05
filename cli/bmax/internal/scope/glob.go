package scope

import (
	"strings"

	"github.com/bmatcuk/doublestar/v4"
)

// Match returns the files matching glob, in order. A glob without "/" matches
// the base name at any depth; a glob with "/" matches the whole slash-separated
// path. Braces {a,b} and ** are supported; file names are matched verbatim
// (spaces, unicode and a leading dash are ordinary characters).
func Match(glob string, files []string) []string {
	var out []string
	for _, f := range files {
		if MatchOne(glob, f) {
			out = append(out, f)
		}
	}
	return out
}

// MatchOne reports whether one file matches glob (see Match).
func MatchOne(glob, file string) bool {
	if glob == "" {
		return false
	}
	target := file
	if !strings.Contains(glob, "/") {
		if i := strings.LastIndexByte(file, '/'); i >= 0 {
			target = file[i+1:]
		}
	}
	ok, err := doublestar.Match(glob, target)
	return err == nil && ok
}
