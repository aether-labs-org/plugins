package builtin

import (
	"encoding/json"
	"reflect"
	"sort"
	"strings"
)

// Doc describes the with: block of a builtin. Keys, types and defaults come from
// the Go struct that Decode fills (so they cannot drift); only the sentences and
// the example are written here, and a test checks that every key has a sentence
// and that the example passes Decode.
type Doc struct {
	Summary  string
	Keys     map[string]string // key path -> description; nested keys are "layers.name"
	Required []string
	Example  map[string]any
}

// Documented is implemented by every builtin.
type Documented interface{ Doc() Doc }

// keyPaths lists the json key paths of a params struct, nested ones as "layers.name".
func keyPaths(t reflect.Type, prefix string) []string {
	for t.Kind() == reflect.Ptr || t.Kind() == reflect.Slice {
		t = t.Elem()
	}
	if t.Kind() != reflect.Struct {
		return nil
	}
	var out []string
	for i := 0; i < t.NumField(); i++ {
		tag := strings.Split(t.Field(i).Tag.Get("json"), ",")[0]
		if tag == "" || tag == "-" {
			continue
		}
		out = append(out, prefix+tag)
		out = append(out, keyPaths(t.Field(i).Type, prefix+tag+".")...)
	}
	sort.Strings(out)
	return out
}

func jsonType(t reflect.Type, docs map[string]string, path string, defaults reflect.Value) map[string]any {
	switch t.Kind() {
	case reflect.String:
		return map[string]any{"type": "string"}
	case reflect.Int, reflect.Int64:
		return map[string]any{"type": "integer"}
	case reflect.Bool:
		return map[string]any{"type": "boolean"}
	case reflect.Slice:
		return map[string]any{"type": "array", "items": jsonType(t.Elem(), docs, path, reflect.Value{})}
	case reflect.Struct:
		return structSchema(t, docs, path, defaults, nil)
	}
	return map[string]any{}
}

func structSchema(t reflect.Type, docs map[string]string, prefix string, defaults reflect.Value, required []string) map[string]any {
	props := map[string]any{}
	for i := 0; i < t.NumField(); i++ {
		tag := strings.Split(t.Field(i).Tag.Get("json"), ",")[0]
		if tag == "" || tag == "-" {
			continue
		}
		var def reflect.Value
		if defaults.IsValid() {
			def = defaults.Field(i)
		}
		p := jsonType(t.Field(i).Type, docs, prefix+tag+".", def)
		if d := docs[prefix+tag]; d != "" {
			p["description"] = d
		}
		if def.IsValid() && !def.IsZero() && def.Kind() != reflect.Slice && def.Kind() != reflect.Struct {
			p["default"] = def.Interface()
		}
		props[tag] = p
	}
	out := map[string]any{"type": "object", "additionalProperties": false, "properties": props}
	if len(required) > 0 {
		out["required"] = required
	}
	return out
}

// WithSchema is the JSON Schema of the with: block of one builtin.
func WithSchema(b Builtin) map[string]any {
	d, _ := b.(Documented)
	doc := Doc{}
	if d != nil {
		doc = d.Doc()
	}
	p, _ := b.Decode(nil)
	v := reflect.ValueOf(p)
	t := v.Type()
	var s map[string]any
	if t.Kind() == reflect.Struct {
		s = structSchema(t, doc.Keys, "", v, doc.Required)
	} else {
		s = map[string]any{"type": "object", "additionalProperties": false, "properties": map[string]any{}}
	}
	s["description"] = doc.Summary
	if doc.Example != nil {
		s["examples"] = []any{doc.Example}
	} else {
		s["examples"] = []any{map[string]any{}}
	}
	return s
}

// ConfigSchema returns the bmax.yml JSON Schema (base) with the with: block of
// every builtin described under $defs.with, and the script definition
// constrained by it: builtin: <name> requires with: to match that block.
func (r Registry) ConfigSchema(base []byte) ([]byte, error) {
	var doc map[string]any
	if err := json.Unmarshal(base, &doc); err != nil {
		return nil, err
	}
	defs, _ := doc["$defs"].(map[string]any)
	if defs == nil {
		defs = map[string]any{}
		doc["$defs"] = defs
	}
	names := make([]string, 0, len(r))
	for n := range r {
		names = append(names, n)
	}
	sort.Strings(names)
	with := map[string]any{}
	var allOf []any
	for _, n := range names {
		with[n] = WithSchema(r[n])
		allOf = append(allOf, map[string]any{
			"if":   map[string]any{"properties": map[string]any{"builtin": map[string]any{"const": n}}, "required": []string{"builtin"}},
			"then": map[string]any{"properties": map[string]any{"with": map[string]any{"$ref": "#/$defs/with/" + n}}},
		})
	}
	defs["with"] = with
	if script, ok := defs["script"].(map[string]any); ok {
		script["allOf"] = allOf
		if props, ok := script["properties"].(map[string]any); ok {
			if w, ok := props["builtin"].(map[string]any); ok {
				w["enum"] = names
			}
		}
	}
	return json.MarshalIndent(doc, "", "  ")
}

// ------------------------------------------------------------------ the descriptions

var filterKeys = map[string]string{
	"include": "Paths the builtin looks at: a directory (src), a file, or a glob (*.ts matches the base name at any depth; src/**/*.py matches the whole path). Empty means every file in scope.",
	"exclude": "Paths to skip, in the same notation as include.",
}

func merge(a, b map[string]string) map[string]string {
	out := map[string]string{}
	for k, v := range a {
		out[k] = v
	}
	for k, v := range b {
		out[k] = v
	}
	return out
}

func (fileSize) Doc() Doc {
	return Doc{Summary: "Fails files with more lines than a limit. Per-file counts feed a TSV baseline (class heuristic).",
		Keys:    merge(filterKeys, map[string]string{"limit": "Largest allowed number of lines (default 300)."}),
		Example: map[string]any{"limit": 300, "include": []any{"src"}, "exclude": []any{"*.generated.*"}}}
}

func (codeLanguage) Doc() Doc {
	return Doc{Summary: "Counts identifier and comment words that are not in the project's code language (non-ASCII letters, or words in a stop-list). String literals are ignored. Per-file counts feed a TSV baseline.",
		Keys:    merge(filterKeys, map[string]string{"stoplist": "The stop-list: 'pt' (Portuguese, embedded; the default) or a repository path to a file with one lowercase word per line."}),
		Example: map[string]any{"include": []any{"src"}, "stoplist": "pt"}}
}

func (folderLayout) Doc() Doc {
	return Doc{Summary: "Every file under include must match one allowed pattern; a file elsewhere counts 1.",
		Keys:     merge(filterKeys, map[string]string{"allowed": "Shell case patterns for the allowed paths: * matches anything including /, ? one character, [abc] a class. A file must match at least one."}),
		Required: []string{"allowed"},
		Example:  map[string]any{"include": []any{"src"}, "allowed": []any{"src/app/*", "src/domain/*"}}}
}

func (pattern) Doc() Doc {
	return Doc{Summary: "Counts the lines matching a regular expression, per file (RE2 syntax; text files only). Per-file counts feed a TSV baseline.",
		Keys: merge(filterKeys, map[string]string{
			"pattern": "The regular expression (RE2). Required.",
			"message": "What is wrong, used in the guidance.",
			"fix":     "The right fix, appended to the guidance."}),
		Required: []string{"pattern"},
		Example:  map[string]any{"pattern": `console\.(log|debug)\(`, "include": []any{"src"}, "message": "Direct console output was found.", "fix": "Use the logger in src/log.ts."}}
}

func (testPresence) Doc() Doc {
	return Doc{Summary: "Every changed main file matching include must have a test at a path produced by one of the mappings; a file no mapping applies to is not covered. Counts 1 per file without a test (TSV baseline).",
		Keys:     merge(filterKeys, map[string]string{"mappings": "Lines 'regex|replacement': an RE2 regular expression matched against the main file's path, a pipe, and the test path to produce, with $1, $2... (or \\1) for the groups. Example: '^src/(.*)\\.ts$|test/$1.test.ts' maps src/a/b.ts to test/a/b.test.ts."}),
		Required: []string{"mappings"},
		Example:  map[string]any{"include": []any{"src"}, "mappings": []any{`^src/(.*)\.ts$|test/$1.test.ts`}}}
}

func (architectureGrep) Doc() Doc {
	return Doc{Summary: "Counts, per file, the imports that cross a layer boundary not allowed, plus the imports of forbidden prefixes. Java, Kotlin and Python only (use a native tool for the rest).",
		Keys: map[string]string{
			"lang":             "java, kotlin or python.",
			"layers":           "The layers, with the path they live in and the package they import as.",
			"layers.name":      "The layer's name.",
			"layers.path":      "Repository path of the layer's sources (the longest matching path decides a file's layer).",
			"layers.import":    "The package prefix others use to import the layer (com.acme.domain, acme.domain).",
			"layers.allowed":   "Names of the layers this layer may import (itself is always allowed).",
			"forbidden":        "Imports a layer must never contain.",
			"forbidden.layer":  "The layer the rule applies to.",
			"forbidden.prefix": "The forbidden import prefix (org.springframework).",
		},
		Required: []string{"lang", "layers"},
		Example: map[string]any{"lang": "java",
			"layers": []any{
				map[string]any{"name": "domain", "path": "src/main/java/com/acme/domain", "import": "com.acme.domain"},
				map[string]any{"name": "adapter", "path": "src/main/java/com/acme/adapter", "import": "com.acme.adapter", "allowed": []any{"domain"}}},
			"forbidden": []any{map[string]any{"layer": "domain", "prefix": "org.springframework"}}}}
}

func (dependencies) Doc() Doc {
	return Doc{Summary: "Fails when a manifest gained a direct dependency since the base and no ADR added in the same change names that manifest by path (class security, no baseline). Reads package.json, pyproject.toml, pom.xml and build.gradle(.kts).",
		Keys:    filterKeys,
		Example: map[string]any{"include": []any{"."}, "exclude": []any{"examples"}}}
}

func (guardBuiltin) Doc() Doc {
	return Doc{Summary: "Fails when the harness itself was loosened since the base (class security, in every required gate; reserved id guard). Takes no parameters.", Example: map[string]any{}}
}

func (memoryBuiltin) Doc() Doc {
	return Doc{Summary: "Checks the format of plans, progress and lessons, and that versioned memory holds no absolute user path, local evidence reference or secret. Takes no parameters.", Example: map[string]any{}}
}

func (scopeBuiltin) Doc() Doc {
	return Doc{Summary: "Reports changed files outside the Scope of every active plan; skips with no active plan. Takes no parameters.", Example: map[string]any{}}
}

func (mergeCheck) Doc() Doc {
	return Doc{Summary: "Reports conflicts with the upstream branch (git merge-tree, git 2.38 or newer) and how many commits behind. Takes no parameters.", Example: map[string]any{}}
}

var patternKey = map[string]string{"pattern": "A Go (RE2) regular expression. Required."}

func (commitMessage) Doc() Doc {
	return Doc{Summary: "The first non-comment line of the commit message must match the pattern; runs from the commit-msg hook (githooks.commit-msg), skips elsewhere.",
		Keys: patternKey, Required: []string{"pattern"},
		Example: map[string]any{"pattern": `^(feat|fix|docs|refactor|test|chore)(\(.+\))?!?: .+`}}
}

func (branchName) Doc() Doc {
	return Doc{Summary: "The current branch name must match the pattern; skips on a detached HEAD.",
		Keys: patternKey, Required: []string{"pattern"},
		Example: map[string]any{"pattern": `^(feat|fix|chore)/[a-z0-9-]+$`}}
}
