package config

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"testing"
)

// fakeValidator knows the builtins used by the fixtures.
func fakeValidator(builtin string, with map[string]any) (bool, []string) {
	allowed := map[string][]string{
		"file-size":      {"limit", "include", "exclude"},
		"memory":         {},
		"merge-check":    {},
		"commit-message": {"pattern"},
		"guard":          {},
	}
	keys, ok := allowed[builtin]
	if !ok {
		return false, nil
	}
	var problems []string
	var names []string
	for k := range with {
		names = append(names, k)
	}
	sort.Strings(names)
	for _, k := range names {
		found := false
		for _, a := range keys {
			if a == k {
				found = true
			}
		}
		if !found {
			problems = append(problems, `unknown key "`+k+`"`)
		}
	}
	return true, problems
}

func readFixture(t *testing.T, rel string) []byte {
	t.Helper()
	b, err := os.ReadFile(filepath.Join("testdata", rel))
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func mustParse(t *testing.T, b []byte) *Config {
	t.Helper()
	c, err := Parse(b)
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	return c
}

func TestLoadValidFull(t *testing.T) {
	c := mustParse(t, readFixture(t, "valid/full.yml"))
	if issues := Validate(c, fakeValidator); len(issues) != 0 {
		t.Fatalf("issues: %v", issues)
	}
	if got := c.Scripts["lint"].Baseline; got != ".agents/baselines/lint.tsv" {
		t.Errorf("lint baseline = %q", got)
	}
	if got := c.Scripts["test"].Retries; got != 1 {
		t.Errorf("test retries = %d", got)
	}
	if got := c.Gates["slow"].Changes; got != "branch" {
		t.Errorf("slow changes = %q", got)
	}
	if c.ADRDir != "docs/adr" {
		t.Errorf("ADRDir = %q", c.ADRDir)
	}
	if c.Order[0] != "test" || c.Order[1] != "lint" {
		t.Errorf("order = %v", c.Order)
	}
	if c.Scripts["typecheck"].PassFiles == nil || *c.Scripts["typecheck"].PassFiles {
		t.Error("pass_files false lost")
	}
	if !c.Scripts["lint"].PassesFiles() {
		t.Error("pass_files defaults to true")
	}
	if c.Scripts["test"].Timeout.String() != "10m0s" || c.Gates["fast"].Ceiling.String() != "30s" {
		t.Errorf("durations: %v %v", c.Scripts["test"].Timeout, c.Gates["fast"].Ceiling)
	}
	if c.Scripts["file-size"].With["limit"] != 300 {
		t.Errorf("with = %v", c.Scripts["file-size"].With)
	}
	if _, ok := c.Scripts["guard"]; !ok {
		t.Error("implicit guard script missing")
	}
	if c.Githooks.Mode != "native" || c.Githooks.CommitMsg != "commit-message" {
		t.Errorf("githooks = %+v", c.Githooks)
	}
}

func TestShortForm(t *testing.T) {
	c := mustParse(t, []byte("version: 1\nscripts: {build: ./gradlew assemble}\n"))
	s := c.Scripts["build"]
	if s.Run != "./gradlew assemble" || s.Format != "" {
		t.Errorf("script = %+v", s)
	}
}

func TestCRLF(t *testing.T) {
	lf := readFixture(t, "valid/full.yml")
	crlf := []byte(strings.ReplaceAll(string(lf), "\n", "\r\n"))
	a, b := mustParse(t, lf), mustParse(t, crlf)
	if !reflect.DeepEqual(a, b) {
		t.Errorf("CRLF config differs from LF:\n%+v\n%+v", a, b)
	}
}

func TestEmptyFile(t *testing.T) {
	c := mustParse(t, nil)
	if c.ADRDir != "docs/adr" || len(c.Scripts) != 0 {
		t.Errorf("empty = %+v", c)
	}
}

func TestInvalid(t *testing.T) {
	want := map[string]string{
		"unknown-key":               `unknown key "colour"`,
		"unknown-builtin":           `unknown builtin "file-sizes"`,
		"errorformat-no-pattern":    `format errorformat needs pattern`,
		"gate-unknown-script":       `unknown script "lnt"`,
		"missing-commit-gate":       `required gate "commit" is missing`,
		"gate-without-guard":        `gate "fast" must list guard`,
		"baseline-on-security":      `security scripts never take a baseline`,
		"baseline-on-correctness":   `only heuristic scripts take a TSV baseline`,
		"baseline-without-findings": `baseline needs a format or builtin that reports files`,
		"retries-4":                 `retries must be 0-3`,
		"run-and-builtin":           `exactly one of run, builtin, exec`,
		"bad-changes":               `changes must be worktree, staged or branch`,
		"githooks-unknown-gate":     `githooks.pre-push names unknown gate`,
		"githooks-bad-mode":         `githooks.mode must be native or external`,
		"version-2":                 `unsupported version 2`,
		"unknown-with-key":          `scripts.file-size.with: unknown key "limt"`,
		"guard-replaced":            `guard is reserved for the guard builtin`,
	}
	files, _ := filepath.Glob("testdata/invalid/*.yml")
	if len(files) != len(want) {
		t.Fatalf("%d fixtures, %d expectations", len(files), len(want))
	}
	for name, sub := range want {
		t.Run(name, func(t *testing.T) {
			b := readFixture(t, "invalid/"+name+".yml")
			var all []Issue
			c, err := Parse(b)
			if err != nil {
				all = err.(*ValidationError).Issues
			} else {
				all = Validate(c, fakeValidator)
			}
			var lines []string
			for _, i := range all {
				lines = append(lines, i.String())
			}
			joined := strings.Join(lines, "\n")
			if !strings.Contains(joined, sub) {
				t.Errorf("want %q in:\n%s", sub, joined)
			}
		})
	}
}

func TestLoadValidFromRoot(t *testing.T) {
	root := t.TempDir()
	os.MkdirAll(filepath.Join(root, ".agents"), 0o755)
	os.WriteFile(filepath.Join(root, ".agents", "bmax.yml"), readFixture(t, "invalid/version-2.yml"), 0o644)
	_, err := LoadValid(root, fakeValidator)
	ve, ok := err.(*ValidationError)
	if !ok || !strings.Contains(ve.Error(), "unsupported version 2") {
		t.Fatalf("err = %v", err)
	}
	os.WriteFile(filepath.Join(root, ".agents", "bmax.yml"), readFixture(t, "valid/full.yml"), 0o644)
	if _, err := LoadValid(root, fakeValidator); err != nil {
		t.Fatal(err)
	}
}

// schemaProps reads properties keys at a JSON pointer-ish path.
func schemaProps(t *testing.T, path ...string) map[string]bool {
	t.Helper()
	b, ok := Schema("config")
	if !ok {
		t.Fatal("no config schema")
	}
	var v any
	if err := json.Unmarshal(b, &v); err != nil {
		t.Fatal(err)
	}
	for _, p := range path {
		v = v.(map[string]any)[p]
	}
	out := map[string]bool{}
	for k := range v.(map[string]any) {
		out[k] = true
	}
	return out
}

func TestSchemaMatchesStruct(t *testing.T) {
	cases := []struct {
		name string
		typ  reflect.Type
		path []string
	}{
		{"top level", reflect.TypeOf(rawConfig{}), []string{"properties"}},
		{"script", reflect.TypeOf(rawScript{}), []string{"$defs", "script", "properties"}},
		{"gate", reflect.TypeOf(rawGate{}), []string{"$defs", "gate", "properties"}},
		{"githooks", reflect.TypeOf(rawGithooks{}), []string{"properties", "githooks", "properties"}},
	}
	for _, c := range cases {
		got := schemaProps(t, c.path...)
		want := yamlKeys(c.typ)
		if !reflect.DeepEqual(got, want) {
			t.Errorf("%s: schema keys %v, struct keys %v", c.name, got, want)
		}
	}
}

func TestSchemaNames(t *testing.T) {
	if _, ok := Schema("config"); !ok {
		t.Error("config schema missing")
	}
	if _, ok := Schema("nope"); ok {
		t.Error("unknown schema name accepted")
	}
}
