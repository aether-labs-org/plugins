package config

import (
	"encoding/json"
	"os"
	"reflect"
	"sort"
	"strings"
	"testing"
)

func TestParseRejectsUnknownKeysAndWrongTypes(t *testing.T) {
	for _, bad := range []string{
		"version: 1\nrequires: 0.1.0\nbogus: 1\n",
		"version: 1\nrequires: 0.1.0\ngate: { fast: { ceiling_seconds: thirty } }\n",
		"version: 1\nrequires: 0.1.0\nsensors: [ { id: a, gate: fast, exec: a.sh, class: security } ]\n",
	} {
		if _, err := Parse([]byte(bad)); err == nil {
			t.Errorf("Parse(%q) = nil error, want one", bad)
		}
	}
}

func TestRequiresMustBeExact(t *testing.T) {
	for v, ok := range map[string]bool{"0.1.0": true, "1.2.3": true, ">=1.2,<2": false, "1.2": false, "v1.2.3": false} {
		c := &Config{Version: 1, Requires: v}
		if got := len(c.Validate(t.TempDir())) == 0; got != ok {
			t.Errorf("requires %q valid = %v, want %v", v, got, ok)
		}
	}
}

func TestSensorsForUsesGateShOrder(t *testing.T) {
	c := &Config{Sensors: []Sensor{{ID: "architecture", Gate: "fast"}, {ID: "architecture-grep", Gate: "fast"}, {ID: "s", Gate: "slow"}}}
	var ids []string
	for _, s := range c.SensorsFor("fast") {
		ids = append(ids, s.ID)
	}
	// gate.sh globbed scripts/sensors/*.sh: "architecture-grep.sh" < "architecture.sh" bytewise.
	if want := []string{"architecture-grep", "architecture"}; !reflect.DeepEqual(ids, want) {
		t.Errorf("SensorsFor(fast) = %v, want %v", ids, want)
	}
}

func TestCeilingDefaults(t *testing.T) {
	c := &Config{}
	if c.Ceiling("fast") != 30 || c.Ceiling("slow") != 600 {
		t.Errorf("defaults = %d/%d, want 30/600", c.Ceiling("fast"), c.Ceiling("slow"))
	}
}

func yamlKeys(v any) []string {
	var keys []string
	rt := reflect.TypeOf(v)
	for i := 0; i < rt.NumField(); i++ {
		keys = append(keys, strings.Split(rt.Field(i).Tag.Get("yaml"), ",")[0])
	}
	sort.Strings(keys)
	return keys
}

func TestSchemaMatchesStructs(t *testing.T) {
	data, err := os.ReadFile("../../schema/keel.schema.json")
	if err != nil {
		t.Fatal(err)
	}
	var s struct {
		Properties map[string]any `json:"properties"`
		Defs       map[string]struct {
			Properties map[string]any `json:"properties"`
		} `json:"$defs"`
	}
	if err := json.Unmarshal(data, &s); err != nil {
		t.Fatal(err)
	}
	keys := func(m map[string]any) []string {
		var k []string
		for x := range m {
			k = append(k, x)
		}
		sort.Strings(k)
		return k
	}
	for name, pair := range map[string][2][]string{
		"Config": {yamlKeys(Config{}), keys(s.Properties)},
		"Sensor": {yamlKeys(Sensor{}), keys(s.Defs["sensor"].Properties)},
		"Budget": {yamlKeys(Budget{}), keys(s.Defs["budget"].Properties)},
	} {
		if !reflect.DeepEqual(pair[0], pair[1]) {
			t.Errorf("%s fields %v != schema properties %v", name, pair[0], pair[1])
		}
	}
}
