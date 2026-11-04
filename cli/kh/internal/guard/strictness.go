package guard

import (
	"regexp"
	"strings"
)

// Type-strictness checks ported from the v0.3 guard sensor (D44): tsconfig
// strict and the flags it implies, mypy strict and disallow_untyped_defs, and
// pyright typeCheckingMode.

var tsFlags = []string{"strict", "noImplicitAny", "strictNullChecks", "strictFunctionTypes", "strictBindCallApply",
	"strictPropertyInitialization", "noImplicitThis", "useUnknownInCatchVariables", "alwaysStrict",
	"noUncheckedIndexedAccess", "exactOptionalPropertyTypes", "noImplicitOverride", "noImplicitReturns"}

var impliedByStrict = map[string]bool{"noImplicitAny": true, "strictNullChecks": true, "strictFunctionTypes": true,
	"strictBindCallApply": true, "strictPropertyInitialization": true, "noImplicitThis": true,
	"useUnknownInCatchVariables": true, "alwaysStrict": true}

func dropJSONComments(s string) string {
	var keep []string
	for _, l := range strings.Split(s, "\n") {
		if !strings.HasPrefix(strings.TrimSpace(l), "//") {
			keep = append(keep, l)
		}
	}
	return strings.Join(keep, "\n")
}

func tsVal(text, key string) string {
	re := regexp.MustCompile(`"` + regexp.QuoteMeta(key) + `"\s*:\s*([a-zA-Z]*)`)
	if m := re.FindStringSubmatch(dropJSONComments(text)); m != nil {
		return m[1]
	}
	return ""
}

func jsonStr(text, key string) string {
	re := regexp.MustCompile(`"` + regexp.QuoteMeta(key) + `"\s*:\s*"([^"]*)"`)
	if m := re.FindStringSubmatch(dropJSONComments(text)); m != nil {
		return m[1]
	}
	return ""
}

// tsEff is the effective value of a flag: unset flags that strict switches on
// take the value of strict.
func tsEff(text, flag string) string {
	v := tsVal(text, flag)
	if v == "" && impliedByStrict[flag] {
		v = tsVal(text, "strict")
	}
	return v
}

// iniVal reads key in [section] of an ini/toml file: lower-cased, without
// quotes and a trailing comment.
func iniVal(text, section, key string) string {
	in := false
	for _, line := range strings.Split(strings.ReplaceAll(text, "\r", ""), "\n") {
		t := strings.TrimSpace(line)
		if strings.HasPrefix(t, "[") {
			s := strings.TrimLeft(t, "[")
			if i := strings.Index(s, "]"); i >= 0 {
				s = s[:i]
			}
			in = strings.TrimSpace(s) == section
			continue
		}
		if !in || t == "" || strings.HasPrefix(t, "#") || strings.HasPrefix(t, ";") {
			continue
		}
		i := strings.IndexByte(line, '=')
		if i < 0 {
			continue
		}
		if strings.ReplaceAll(strings.ReplaceAll(line[:i], " ", ""), "\t", "") != key {
			continue
		}
		v := line[i+1:]
		if j := strings.IndexAny(v, "#;"); j >= 0 {
			v = v[:j]
		}
		return strings.ToLower(strings.Trim(strings.TrimSpace(v), `"'`))
	}
	return ""
}

func mypyEff(text, section, flag string) string {
	v := iniVal(text, section, flag)
	if v == "" && flag == "disallow_untyped_defs" {
		v = iniVal(text, section, "strict")
	}
	switch v {
	case "true", "1", "yes", "on":
		return "true"
	case "":
		return ""
	}
	return "false"
}

var pyrightLevels = map[string]int{"off": 0, "basic": 1, "standard": 2, "strict": 3}
var pyrightNames = []string{"off", "basic", "standard", "strict"}

func isStrictnessFile(path string) bool {
	if strings.Contains(path, "node_modules/") {
		return false
	}
	base := path[strings.LastIndexByte(path, '/')+1:]
	if strings.HasPrefix(base, "tsconfig") && strings.HasSuffix(base, ".json") {
		return true
	}
	switch base {
	case "pyrightconfig.json", "mypy.ini", ".mypy.ini", "setup.cfg", "pyproject.toml":
		return true
	}
	return false
}

// strictnessLoosenings compares one file at the base with the work tree.
// curExists is false when the file was deleted.
func strictnessLoosenings(path, old, cur string, curExists bool) []string {
	base := path[strings.LastIndexByte(path, '/')+1:]
	var out []string
	if strings.HasPrefix(base, "tsconfig") && strings.HasSuffix(base, ".json") {
		if !curExists {
			for _, f := range tsFlags {
				if tsEff(old, f) == "true" {
					return []string{"type-strictness: file removed"}
				}
			}
			return nil
		}
		strictLoosened := false
		for _, f := range tsFlags {
			o, n := tsEff(old, f), tsEff(cur, f)
			if o != "true" || n == "true" {
				continue
			}
			if f == "strict" {
				strictLoosened = true
			} else if impliedByStrict[f] && strictLoosened {
				continue
			}
			if n == "" {
				n = "(unset)"
			}
			out = append(out, "type-strictness: "+f+" true -> "+n)
		}
	}
	switch base {
	case "mypy.ini", ".mypy.ini", "setup.cfg", "pyproject.toml":
		sec := "mypy"
		if base == "pyproject.toml" {
			sec = "tool.mypy"
		}
		strictOff := false
		for _, f := range []string{"strict", "disallow_untyped_defs"} {
			o, n := mypyEff(old, sec, f), mypyEff(cur, sec, f)
			if o != "true" || n == "true" {
				continue
			}
			if f == "disallow_untyped_defs" && strictOff {
				continue
			}
			if f == "strict" {
				strictOff = true
			}
			if n == "" {
				n = "(unset)"
			}
			out = append(out, "type-strictness: mypy "+f+" true -> "+n)
		}
	}
	if base == "pyrightconfig.json" || base == "pyproject.toml" {
		var o, n string
		if base == "pyproject.toml" {
			o, n = iniVal(old, "tool.pyright", "typeCheckingMode"), iniVal(cur, "tool.pyright", "typeCheckingMode")
		} else {
			o, n = jsonStr(old, "typeCheckingMode"), jsonStr(cur, "typeCheckingMode")
		}
		if lo, ok := pyrightLevels[o]; ok {
			ln, ok := pyrightLevels[n]
			if !ok {
				ln = 2 // pyright's default mode is standard
			}
			if ln < lo {
				out = append(out, "type-strictness: pyright typeCheckingMode "+o+" -> "+pyrightNames[ln])
			}
		}
	}
	return out
}
