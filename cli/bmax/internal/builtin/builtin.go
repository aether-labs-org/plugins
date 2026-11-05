// Package builtin holds the checks bmax runs itself (no external tool): the rule
// builtins ported from the v0.3 bash sensors (file-size, code-language,
// folder-layout, pattern, architecture-grep, test-presence, dependencies), guard,
// and the memory and git-cycle builtins.
//
// Parameter names are the v0.3 env keys in snake_case, under `with:`:
//
//	file-size         LIMIT -> limit, INCLUDE -> include, EXCLUDE -> exclude
//	code-language     INCLUDE, EXCLUDE -> include, exclude; STOPLIST -> stoplist ("pt" or a repository path)
//	folder-layout     INCLUDE, EXCLUDE, ALLOWED -> include, exclude, allowed
//	pattern           PATTERN -> pattern, INCLUDE, EXCLUDE, MESSAGE -> message, FIX -> fix
//	                  (the ast-grep and semgrep engines are gone: run them with `run:` and `format: sarif`)
//	architecture-grep LANG -> lang, LAYERS -> layers (name, path, import, allowed), FORBIDDEN -> forbidden (layer, prefix)
//	test-presence     INCLUDE, EXCLUDE, MAPPINGS -> include, exclude, mappings ("from|to", RE2 and $1)
//	dependencies      INCLUDE, EXCLUDE -> include, exclude
package builtin

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"time"

	"github.com/aether-labs-org/plugins/cli/bmax/internal/config"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/result"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/scope"
)

// Context is what a builtin may look at.
type Context struct {
	Root   string
	Files  []string // in scope (or every candidate file with --all)
	All    bool     // Files is every candidate, not just the changed ones
	Base   string   // branch base for builtins that need history ("" when unborn)
	Cfg    *config.Config
	Script config.Script
	Gate   string // the gate being run, "" for a lone bmax run
	Now    time.Time

	// CommitMsgFile is set by the commit-msg hook for the commit-message builtin.
	CommitMsgFile string
	// Measure: report per-file counts for bmax measure, whatever the verdict.
	Measure bool
}

// Outcome is what a builtin reports.
type Outcome struct {
	Status   result.Status
	Summary  string
	Findings []result.Finding
	Counts   map[string]int // per file, for baselines; nil when the builtin has none
	Guidance string         // default guidance, used when the script declares none
}

// Builtin is one check.
type Builtin interface {
	Name() string
	// Decode strictly decodes the with: block: unknown keys are problems.
	Decode(with map[string]any) (params any, problems []string)
	Run(ctx Context, params any) Outcome
}

// ClassDefault is implemented by builtins whose default class is not correctness.
type ClassDefault interface{ DefaultClass() string }

// Registry maps builtin names to builtins.
type Registry map[string]Builtin

// Default returns every builtin.
func Default() Registry {
	r := Registry{}
	for _, b := range []Builtin{
		fileSize{}, codeLanguage{}, folderLayout{}, pattern{}, architectureGrep{}, testPresence{}, dependencies{},
	} {
		r[b.Name()] = b
	}
	for _, b := range extra {
		r[b.Name()] = b
	}
	return r
}

// extra lets other files of the package register their builtins.
var extra []Builtin

func register(b Builtin) { extra = append(extra, b) }

// Validator adapts the registry to config.WithValidator.
func (r Registry) Validator() config.WithValidator {
	return func(name string, with map[string]any) (bool, []string) {
		b, ok := r[name]
		if !ok {
			return false, nil
		}
		_, problems := b.Decode(with)
		return true, problems
	}
}

// ClassOf returns the default class of a builtin.
func ClassOf(b Builtin) string {
	if c, ok := b.(ClassDefault); ok {
		return c.DefaultClass()
	}
	return "correctness"
}

// decodeWith strictly decodes a with: block into T (json tags are the keys).
func decodeWith[T any](with map[string]any) (T, []string) {
	var out T
	allowed := map[string]bool{}
	t := reflect.TypeOf(out)
	for i := 0; i < t.NumField(); i++ {
		if tag := strings.Split(t.Field(i).Tag.Get("json"), ",")[0]; tag != "" && tag != "-" {
			allowed[tag] = true
		}
	}
	var problems []string
	keys := make([]string, 0, len(with))
	for k := range with {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		if !allowed[k] {
			problems = append(problems, fmt.Sprintf("unknown key %q", k))
		}
	}
	if len(problems) > 0 {
		return out, problems
	}
	if len(with) == 0 {
		return out, nil
	}
	b, err := json.Marshal(with)
	if err == nil {
		dec := json.NewDecoder(bytes.NewReader(b))
		dec.DisallowUnknownFields()
		err = dec.Decode(&out)
	}
	if err != nil {
		problems = append(problems, "invalid value: "+strings.TrimPrefix(err.Error(), "json: "))
	}
	return out, problems
}

func hasMeta(s string) bool { return strings.ContainsAny(s, "*?[{") }

// specMatch reports whether a file matches an include/exclude spec: a plain
// path matches itself and everything below it; a glob without "/" matches the
// base name at any depth; a glob with "/" matches the whole path.
func specMatch(spec, file string) bool {
	spec = strings.TrimSuffix(spec, "/")
	if spec == "" || spec == "." || spec == "/" {
		return true
	}
	if !hasMeta(spec) {
		return file == spec || strings.HasPrefix(file, spec+"/")
	}
	if scope.MatchOne(spec, file) {
		return true
	}
	// "src/**" also names the directory itself
	if strings.HasSuffix(spec, "/**") {
		return specMatch(strings.TrimSuffix(spec, "/**"), file)
	}
	return false
}

// selectFiles keeps the files matching include (empty = all) and not matching exclude.
func selectFiles(files, include, exclude []string) []string {
	var out []string
	for _, f := range files {
		if len(include) > 0 {
			ok := false
			for _, s := range include {
				if specMatch(s, f) {
					ok = true
					break
				}
			}
			if !ok {
				continue
			}
		}
		skip := false
		for _, s := range exclude {
			if specMatch(s, f) {
				skip = true
				break
			}
		}
		if !skip {
			out = append(out, f)
		}
	}
	return out
}

// readText returns the content of a file unless it is empty or binary (a NUL in
// the first 8 KiB), like `grep -I .`.
func readText(root, rel string) ([]byte, bool) {
	b, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(rel)))
	if err != nil || len(b) == 0 {
		return nil, false
	}
	head := b
	if len(head) > 8192 {
		head = head[:8192]
	}
	if bytes.IndexByte(head, 0) >= 0 {
		return nil, false
	}
	return b, true
}

func exists(root, rel string) bool {
	st, err := os.Stat(filepath.Join(root, filepath.FromSlash(rel)))
	return err == nil && st.Mode().IsRegular()
}

// noScope is the outcome when nothing is in scope.
func noScope() Outcome {
	return Outcome{Status: result.Skip, Summary: "no changed files in scope"}
}

// pass and fail build common outcomes.
func pass(summary string, counts map[string]int) Outcome {
	return Outcome{Status: result.Pass, Summary: summary, Counts: counts}
}

func sortFindings(fs []result.Finding) {
	sort.SliceStable(fs, func(i, j int) bool {
		if fs[i].File != fs[j].File {
			return fs[i].File < fs[j].File
		}
		return fs[i].Line < fs[j].Line
	})
}
