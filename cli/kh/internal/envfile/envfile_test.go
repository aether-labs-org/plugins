package envfile

import (
	"strings"
	"testing"
)

// The fixture of tests/keel_envparse_test.sh: the Go reader must agree with scripts/lib/envparse.sh.
const ok = "# Managed by keel-harness - see .agents/README.md\nRULE_ID=file-size\nKIND=metric                       # metric | structure\n  LIMIT=300\nINCLUDE='src/'\nLAYERS='domain|src/d|com.d||domainModels\nweb|src/w|com.w|domain|adapter'\nNOTE=\"it's fine\"   # trailing comment\nLITERAL=$HOME\nEMPTY=\nCRLF=yes\r\nLAST=noeol"

func TestParseMatchesEnvparse(t *testing.T) {
	got, err := Parse("ok.env", ok)
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]string{
		"RULE_ID": "file-size", "KIND": "metric", "LIMIT": "300", "INCLUDE": "src/",
		"LAYERS": "domain|src/d|com.d||domainModels\nweb|src/w|com.w|domain|adapter",
		"NOTE": "it's fine", "LITERAL": "$HOME", "EMPTY": "", "CRLF": "yes", "LAST": "noeol",
	}
	for k, v := range want {
		if got[k] != v {
			t.Errorf("%s = %q, want %q", k, got[k], v)
		}
	}
}

func TestParseRejectsLikeEnvparse(t *testing.T) {
	for line, reason := range map[string]string{
		"X=$(touch PWNED)": "contains $( or a backtick", "X=`id`": "contains $( or a backtick",
		"X='open": "unterminated quote", "not a line": "not a KEY=value line", "lower=1": "not a KEY=value line",
		"X='a' junk": "unexpected text after the closing quote",
	} {
		_, err := Parse("bad.env", line+"\n")
		if err == nil || !strings.Contains(err.Error(), reason) || !strings.Contains(err.Error(), "bad.env:1:") {
			t.Errorf("Parse(%q) error = %v, want bad.env:1: ... %s", line, err, reason)
		}
	}
}
