package format

import (
	"encoding/json"
	"github.com/aether-labs-org/plugins/cli/kh/internal/config"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"testing"

	"github.com/aether-labs-org/plugins/cli/kh/internal/result"
)

const fixtureRoot = "../../testdata/formats"

// fixtures lists the .cmd files of one format directory.
func fixtures(t *testing.T, formatName string) []string {
	t.Helper()
	m, _ := filepath.Glob(filepath.Join(fixtureRoot, formatName, "*.cmd"))
	sort.Strings(m)
	return m
}

// reportFor finds the recorded output next to a .cmd file (any extension but
// .cmd and .want.json).
func reportFor(t *testing.T, cmd string) string {
	t.Helper()
	base := strings.TrimSuffix(cmd, ".cmd")
	all, _ := filepath.Glob(base + ".*")
	for _, f := range all {
		if !strings.HasSuffix(f, ".cmd") && !strings.HasSuffix(f, ".want.json") {
			return f
		}
	}
	t.Fatalf("no recorded output for %s", cmd)
	return ""
}

func cmdLines(t *testing.T, cmd string) []string {
	b, err := os.ReadFile(cmd)
	if err != nil {
		t.Fatal(err)
	}
	return strings.Split(strings.TrimRight(string(b), "\n"), "\n")
}

// TestFixtures parses every recorded output and compares it with .want.json.
// KH_UPDATE_FIXTURES=1 rewrites the .want.json files (review them by hand).
func TestFixtures(t *testing.T) {
	total := 0
	for _, name := range []string{"junit", "checkstyle", "sarif", "eslint-json", "errorformat"} {
		for _, cmd := range fixtures(t, name) {
			total++
			t.Run(name+"/"+strings.TrimSuffix(filepath.Base(cmd), ".cmd"), func(t *testing.T) {
				lines := cmdLines(t, cmd)
				if len(lines) < 3 || !strings.HasPrefix(lines[1], "tool version: ") {
					t.Fatalf("%s: line 1 is the command, line 2 'tool version: ...', line 3 the date", cmd)
				}
				rep, err := os.ReadFile(reportFor(t, cmd))
				if err != nil {
					t.Fatal(err)
				}
				p, ok := Get(name)
				if !ok {
					t.Fatalf("no parser for %s", name)
				}
				in := Input{Reports: [][]byte{rep}}
				if name == "errorformat" {
					if len(lines) < 4 {
						t.Fatalf("%s: line 4 must hold the pattern", cmd)
					}
					in = Input{Output: rep, Pattern: lines[3]}
				}
				got, ok, err := p(in)
				if err != nil || !ok {
					t.Fatalf("parse: ok=%v err=%v", ok, err)
				}
				if got == nil {
					got = []result.Finding{}
				}
				wantPath := strings.TrimSuffix(cmd, ".cmd") + ".want.json"
				if os.Getenv("KH_UPDATE_FIXTURES") == "1" {
					b, _ := json.MarshalIndent(got, "", "  ")
					os.WriteFile(wantPath, append(b, '\n'), 0o644)
				}
				wb, err := os.ReadFile(wantPath)
				if err != nil {
					t.Fatalf("missing %s", wantPath)
				}
				var want []result.Finding
				if err := json.Unmarshal(wb, &want); err != nil {
					t.Fatal(err)
				}
				if want == nil {
					want = []result.Finding{}
				}
				if !reflect.DeepEqual(got, want) {
					gb, _ := json.MarshalIndent(got, "", "  ")
					t.Errorf("findings differ from %s:\n%s", wantPath, gb)
				}
			})
		}
	}
	if total == 0 {
		t.Fatal("no fixtures found")
	}
}

func TestJUnitSkippedNotFailure(t *testing.T) {
	xml := `<testsuites><testsuite name="s" tests="2"><testcase classname="a.B" name="ok"/><testcase classname="a.B" name="sk"><skipped/></testcase></testsuite></testsuites>`
	got, ok, err := junit(Input{Reports: [][]byte{[]byte(xml)}})
	if err != nil || !ok || len(got) != 0 {
		t.Fatalf("got %v ok=%v err=%v", got, ok, err)
	}
	tot, ok := TotalsJUnit([][]byte{[]byte(xml)})
	if !ok || tot.Tests != 2 || tot.Skipped != 1 || tot.Failed != 0 {
		t.Errorf("totals = %+v", tot)
	}
}

func TestJUnitErrorIsFailure(t *testing.T) {
	xml := `<testsuite name="s"><testcase classname="a.B" name="boom"><error message="NPE" type="java.lang.NullPointerException">trace</error></testcase></testsuite>`
	got, ok, _ := junit(Input{Reports: [][]byte{[]byte(xml)}})
	if !ok || len(got) != 1 || got[0].Severity != "error" || got[0].Message != "NPE" || got[0].Rule != "boom" || got[0].File != "a.B" {
		t.Fatalf("got %+v", got)
	}
}

func TestJUnitMessageFromBody(t *testing.T) {
	xml := `<testsuite><testcase classname="x.y" name="n" file="src/a.py" line="7"><failure>

  first real line
second</failure></testcase></testsuite>`
	got, _, _ := junit(Input{Reports: [][]byte{[]byte(xml)}})
	if len(got) != 1 || got[0].Message != "first real line" || got[0].File != "src/a.py" || got[0].Line != 7 {
		t.Fatalf("got %+v", got)
	}
}

func TestUnrecognisedIsNotOK(t *testing.T) {
	for name, in := range map[string]Input{
		"junit/none":       {},
		"junit/html":       {Reports: [][]byte{[]byte("<html><body>nope</body></html>")}},
		"junit/garbage":    {Reports: [][]byte{[]byte("this is not xml <<<")}},
		"checkstyle/none":  {},
		"checkstyle/other": {Reports: [][]byte{[]byte("<testsuite/>")}},
	} {
		p, _ := Get(strings.Split(name, "/")[0])
		got, ok, _ := p(in)
		if ok || len(got) != 0 {
			t.Errorf("%s: ok=%v findings=%v", name, ok, got)
		}
	}
}

func TestEmptyReportIsRecognised(t *testing.T) {
	got, ok, _ := junit(Input{Reports: [][]byte{[]byte(`<testsuites tests="0"/>`)}})
	if !ok || len(got) != 0 {
		t.Errorf("ok=%v got=%v", ok, got)
	}
	got, ok, _ = checkstyle(Input{Reports: [][]byte{[]byte(`<checkstyle version="1"></checkstyle>`)}})
	if !ok || len(got) != 0 {
		t.Errorf("checkstyle ok=%v got=%v", ok, got)
	}
}

func TestFormatsMatchConfig(t *testing.T) {
	got := Names()
	sort.Strings(got)
	want := append([]string(nil), config.Formats...)
	sort.Strings(want)
	if !reflect.DeepEqual(got, want) {
		t.Errorf("registered %v, config.Formats %v", got, want)
	}
}

func TestSarifLevels(t *testing.T) {
	doc := `{"version":"2.1.0","runs":[{"tool":{"driver":{"rules":[{"id":"r3","defaultConfiguration":{"level":"error"}}]}},"results":[
	 {"ruleId":"r1","level":"error","message":{"text":"e"},"locations":[{"physicalLocation":{"artifactLocation":{"uri":"file:///a%20b/x.go"},"region":{"startLine":3,"startColumn":4}}}]},
	 {"ruleId":"r2","level":"warning","message":{"text":"w"}},
	 {"ruleId":"r4","level":"note","message":{"text":"n"}},
	 {"ruleId":"r3","message":{"text":"from the rule default"}},
	 {"ruleId":"r5","message":{"text":"no level anywhere"}}]}]}`
	got, ok, err := sarif(Input{Reports: [][]byte{[]byte(doc)}})
	if err != nil || !ok || len(got) != 5 {
		t.Fatalf("ok=%v err=%v got=%v", ok, err, got)
	}
	var sev []string
	for _, f := range got {
		sev = append(sev, f.Severity)
	}
	if !reflect.DeepEqual(sev, []string{"error", "warning", "note", "error", "warning"}) {
		t.Errorf("severities = %v", sev)
	}
	if got[0].File != "/a b/x.go" || got[0].Line != 3 || got[0].Col != 4 {
		t.Errorf("location = %+v", got[0])
	}
}

func TestSarifAndJSONUnrecognised(t *testing.T) {
	for _, name := range []string{"sarif", "eslint-json"} {
		p, _ := Get(name)
		for _, in := range []Input{{}, {Output: []byte("plain text")}, {Reports: [][]byte{[]byte(`{"nope":1}`)}}} {
			if got, ok, _ := p(in); ok {
				t.Errorf("%s accepted %q: %v", name, in.Output, got)
			}
		}
	}
}

func TestJSONFromOutputWithNoise(t *testing.T) {
	out := "npm warn something\n[{\"filePath\":\"/r/a.js\",\"messages\":[{\"ruleId\":\"eqeqeq\",\"severity\":2,\"message\":\"m\",\"line\":1,\"column\":2}]}]\ntrailing noise\n"
	got, ok, err := eslintJSON(Input{Output: []byte(out)})
	if err != nil || !ok || len(got) != 1 || got[0].Rule != "eqeqeq" || got[0].Severity != "error" {
		t.Fatalf("ok=%v err=%v got=%v", ok, err, got)
	}
}

func TestErrorformatMultiline(t *testing.T) {
	out := "a.py:3:1 - error: first\n    continued here\n    ^\n    and here\nnot indented\n    stray indented\na.py:9:1 - error: second\n"
	got, ok, err := errorformat(Input{Output: []byte(out), Pattern: `^(?P<file>\S+):(?P<line>\d+):(?P<col>\d+) - (?P<severity>\w+): (?P<message>.*)$`})
	if err != nil || !ok || len(got) != 2 {
		t.Fatalf("ok=%v err=%v got=%v", ok, err, got)
	}
	if got[0].Message != "first continued here and here" || got[1].Message != "second" {
		t.Errorf("messages = %q / %q", got[0].Message, got[1].Message)
	}
}

func TestErrorformatBadPattern(t *testing.T) {
	if _, ok, err := errorformat(Input{Output: []byte("x"), Pattern: "("}); ok || err == nil {
		t.Errorf("ok=%v err=%v", ok, err)
	}
}
