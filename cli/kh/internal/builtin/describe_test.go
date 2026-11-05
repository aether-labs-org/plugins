package builtin

import (
	"encoding/json"
	"os"
	"reflect"
	"sort"
	"strings"
	"testing"
)

func names(r Registry) []string {
	var out []string
	for n := range r {
		out = append(out, n)
	}
	sort.Strings(out)
	return out
}

func TestEveryBuiltinIsDocumented(t *testing.T) {
	r := Default()
	if len(r) < 13 {
		t.Fatalf("only %d builtins registered: %v", len(r), names(r))
	}
	for _, n := range names(r) {
		d, ok := r[n].(Documented)
		if !ok {
			t.Errorf("%s has no Doc()", n)
			continue
		}
		doc := d.Doc()
		if doc.Summary == "" {
			t.Errorf("%s: empty summary", n)
		}
		p, _ := r[n].Decode(nil)
		paths := keyPaths(reflect.TypeOf(p), "")
		for _, k := range paths {
			if doc.Keys[k] == "" {
				t.Errorf("%s: with key %q has no description", n, k)
			}
		}
		for k := range doc.Keys {
			found := false
			for _, p := range paths {
				found = found || p == k
			}
			if !found {
				t.Errorf("%s: description for %q, which is not a with key (the struct and the docs drifted)", n, k)
			}
		}
		for _, k := range doc.Required {
			if doc.Keys[k] == "" {
				t.Errorf("%s: required key %q is not a documented key", n, k)
			}
		}
		// the example decodes cleanly with the real validator
		if _, problems := r[n].Decode(doc.Example); len(problems) > 0 {
			t.Errorf("%s: the example does not validate: %v", n, problems)
		}
		if len(paths) > 0 && len(doc.Example) == 0 {
			t.Errorf("%s: a builtin with keys needs an example", n)
		}
		// without its required keys Decode complains, so "required" is true
		if len(doc.Required) > 0 {
			if _, problems := r[n].Decode(nil); len(problems) == 0 {
				t.Errorf("%s: Required says %v but Decode(nil) has no problem", n, doc.Required)
			}
		}
	}
}

func TestKeelSchemaDescribesEveryBuiltinWith(t *testing.T) {
	base := []byte(`{"$defs":{"script":{"type":"object","properties":{"builtin":{"type":"string"},"with":{"type":"object"}}}}}`)
	b, err := Default().KeelSchema(base)
	if err != nil {
		t.Fatal(err)
	}
	var doc map[string]any
	if err := json.Unmarshal(b, &doc); err != nil {
		t.Fatal(err)
	}
	defs := doc["$defs"].(map[string]any)
	with := defs["with"].(map[string]any)
	for _, n := range names(Default()) {
		w, ok := with[n].(map[string]any)
		if !ok {
			t.Errorf("no $defs.with.%s", n)
			continue
		}
		if w["description"] == "" || w["additionalProperties"] != false {
			t.Errorf("%s: %v", n, w)
		}
	}
	fs := with["file-size"].(map[string]any)
	limit := fs["properties"].(map[string]any)["limit"].(map[string]any)
	if limit["type"] != "integer" || limit["default"] != float64(300) || limit["description"] == "" {
		t.Errorf("file-size limit: %v", limit)
	}
	tp := with["test-presence"].(map[string]any)
	if tp["required"].([]any)[0] != "mappings" || len(tp["examples"].([]any)) != 1 {
		t.Errorf("test-presence: %v", tp)
	}
	layers := with["architecture-grep"].(map[string]any)["properties"].(map[string]any)["layers"].(map[string]any)
	if layers["type"] != "array" || layers["items"].(map[string]any)["properties"].(map[string]any)["import"] == nil {
		t.Errorf("architecture-grep layers: %v", layers)
	}
	script := defs["script"].(map[string]any)
	if len(script["allOf"].([]any)) != len(Default()) {
		t.Errorf("script.allOf has %d conditions", len(script["allOf"].([]any)))
	}
}

// gates.md carries the table of every builtin with its with: keys and an example.
func TestGatesMdDocumentsEveryBuiltin(t *testing.T) {
	b, err := os.ReadFile("../../../../plugins/keel-harness/skills/harness/references/gates.md")
	if err != nil {
		t.Fatal(err)
	}
	text := string(b)
	rows := map[string]string{}
	for _, l := range strings.Split(text, "\n") {
		if strings.HasPrefix(l, "| `") {
			cells := strings.SplitN(l, "|", 3)
			rows[strings.Trim(strings.TrimSpace(cells[1]), "`")] = l
		}
	}
	for _, n := range names(Default()) {
		row, ok := rows[n]
		if !ok {
			t.Errorf("gates.md has no table row for builtin %s", n)
			continue
		}
		p, _ := Default()[n].Decode(nil)
		for _, k := range keyPaths(reflect.TypeOf(p), "") {
			if !strings.Contains(row, k[strings.LastIndex(k, ".")+1:]) {
				t.Errorf("gates.md row of %s does not mention the key %q", n, k)
			}
		}
		if !strings.Contains(row, "builtin: "+n) {
			t.Errorf("gates.md row of %s has no example (builtin: %s)", n, n)
		}
	}
	if !strings.Contains(text, `'^src/(.*)\.ts$|test/$1.test.ts'`) {
		t.Error("gates.md lacks the test-presence mapping example '^src/(.*)\\.ts$|test/$1.test.ts'")
	}
}
