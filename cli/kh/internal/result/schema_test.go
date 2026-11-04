package result_test

import (
	"encoding/json"
	"reflect"
	"sort"
	"testing"

	"github.com/aether-labs-org/plugins/cli/kh/internal/config"
	"github.com/aether-labs-org/plugins/cli/kh/internal/result"
)

func keysOf(m map[string]any) []string {
	var k []string
	for x := range m {
		k = append(k, x)
	}
	sort.Strings(k)
	return k
}

func TestJSONSchemaMatchesResult(t *testing.T) {
	b, ok := config.Schema("result")
	if !ok {
		t.Fatal("no result schema")
	}
	var schema map[string]any
	if err := json.Unmarshal(b, &schema); err != nil {
		t.Fatal(err)
	}
	enc, err := json.Marshal(result.Result{Baseline: &result.Baseline{}})
	if err != nil {
		t.Fatal(err)
	}
	var got map[string]any
	json.Unmarshal(enc, &got)

	props := schema["properties"].(map[string]any)
	if !reflect.DeepEqual(keysOf(got), keysOf(props)) {
		t.Errorf("Result keys %v\nschema keys %v", keysOf(got), keysOf(props))
	}
	for name, sub := range map[string]map[string]any{
		"counts":   got["counts"].(map[string]any),
		"baseline": got["baseline"].(map[string]any),
		"evidence": got["evidence"].(map[string]any),
		"tree":     got["tree"].(map[string]any),
	} {
		sp := props[name].(map[string]any)["properties"].(map[string]any)
		if !reflect.DeepEqual(keysOf(sub), keysOf(sp)) {
			t.Errorf("%s: Result keys %v, schema keys %v", name, keysOf(sub), keysOf(sp))
		}
	}
	finding, _ := json.Marshal(result.Finding{})
	var fm map[string]any
	json.Unmarshal(finding, &fm)
	fp := schema["$defs"].(map[string]any)["finding"].(map[string]any)["properties"].(map[string]any)
	if !reflect.DeepEqual(keysOf(fm), keysOf(fp)) {
		t.Errorf("Finding keys %v, schema keys %v", keysOf(fm), keysOf(fp))
	}
}
