// Package envfile reads KEY=value files without executing anything, with the semantics of
// scripts/lib/envparse.sh (keel_env_load): comments, unquoted values with a trailing ` # comment`,
// single- or double-quoted values that may span lines, CRLF tolerated, nothing expanded, and a
// value containing `$(` or a backtick rejected.
package envfile

import (
	"fmt"
	"strings"
)

const space = " \t\n\v\f\r"

// Parse returns every KEY=value of data. name is used in error messages only.
func Parse(name, data string) (map[string]string, error) {
	vals := map[string]string{}
	lines := strings.Split(data, "\n")
	if strings.HasSuffix(data, "\n") {
		lines = lines[:len(lines)-1]
	}
	var key, q, buf string
	open, start := false, 0
	set := func(n int, k, v string) error {
		if strings.Contains(v, "$(") || strings.Contains(v, "`") {
			return fmt.Errorf("%s:%d: %s contains $( or a backtick, which keel never executes", name, n, k)
		}
		vals[k] = v
		return nil
	}
	tail := func(n int, rest string) error {
		t := strings.TrimLeft(rest, space)
		if t == "" || strings.HasPrefix(t, "#") {
			return nil
		}
		return fmt.Errorf("%s:%d: unexpected text after the closing quote", name, n)
	}
	for i, line := range lines {
		n := i + 1
		line = strings.TrimSuffix(line, "\r")
		if open {
			if j := strings.Index(line, q); j >= 0 {
				buf += "\n" + line[:j]
				if err := tail(n, line[j+1:]); err != nil {
					return nil, err
				}
				if err := set(start, key, buf); err != nil {
					return nil, err
				}
				open = false
			} else {
				buf += "\n" + line
			}
			continue
		}
		t := strings.TrimLeft(line, space)
		if t == "" || strings.HasPrefix(t, "#") {
			continue
		}
		eq := strings.Index(t, "=")
		key = ""
		if eq > 0 {
			key = t[:eq]
		}
		if !validKey(key) {
			return nil, fmt.Errorf("%s:%d: not a KEY=value line (keys are UPPER_CASE)", name, n)
		}
		rest := t[eq+1:]
		if strings.HasPrefix(rest, "'") || strings.HasPrefix(rest, `"`) {
			q, rest = rest[:1], rest[1:]
			if j := strings.Index(rest, q); j >= 0 {
				if err := tail(n, rest[j+1:]); err != nil {
					return nil, err
				}
				if err := set(n, key, rest[:j]); err != nil {
					return nil, err
				}
			} else {
				open, start, buf = true, n, rest
			}
			continue
		}
		// ${rest%%[[:space:]]#*}: cut at the first blank that is followed by '#', then trim the right.
		for j := 0; j+1 < len(rest); j++ {
			if strings.IndexByte(space, rest[j]) >= 0 && rest[j+1] == '#' {
				rest = rest[:j]
				break
			}
		}
		if err := set(n, key, strings.TrimRight(rest, space)); err != nil {
			return nil, err
		}
	}
	if open {
		return nil, fmt.Errorf("%s:%d: %s has an unterminated quote", name, start, key)
	}
	return vals, nil
}

func validKey(k string) bool {
	if k == "" || (k[0] >= '0' && k[0] <= '9') {
		return false
	}
	for i := 0; i < len(k); i++ {
		c := k[i]
		if !(c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '_') {
			return false
		}
	}
	return true
}
