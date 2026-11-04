package redact_test

import (
	"bytes"
	"strings"
	"testing"

	"github.com/aether-labs-org/plugins/cli/kh/internal/redact"
)

const ph = "‹redacted›"

func ghToken() string { return "ghp_" + strings.Repeat("a1B2", 9) } // 36 alnum after the prefix

func write(t *testing.T, r *redact.Redactor, chunks ...string) string {
	t.Helper()
	var buf bytes.Buffer
	w := r.Writer(&buf)
	for _, c := range chunks {
		if _, err := w.Write([]byte(c)); err != nil {
			t.Fatal(err)
		}
	}
	if err := w.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.String()
}

func TestRedactPlaceholder(t *testing.T) {
	if redact.Placeholder != "‹redacted›" {
		t.Fatalf("Placeholder = %q", redact.Placeholder)
	}
}

func TestRedactEnvValue(t *testing.T) {
	r := redact.New([]string{"AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG"})
	got := r.String("key wJalrXUtnFEMI/K7MDENG end")
	if got != "key "+ph+" end" {
		t.Fatalf("got %q", got)
	}
}

func TestRedactShortValueKept(t *testing.T) {
	r := redact.New([]string{"API_TOKEN=abc"})
	if got := r.String("abc"); got != "abc" {
		t.Fatalf("got %q", got)
	}
}

func TestRedactNonSecretName(t *testing.T) {
	r := redact.New([]string{"HOME=/home/someone"})
	if got := r.String("at /home/someone"); got != "at /home/someone" {
		t.Fatalf("got %q", got)
	}
}

func TestRedactNameRules(t *testing.T) {
	cases := []struct {
		env    string
		secret bool
	}{
		{"my_token=value123", true},
		{"DB_PASSWORD=value123", true},
		{"AWS_CREDENTIALS_FILE=value123", true},
		{"SOME_SECRET_THING=value123", true},
		{"STRIPE_KEY=value123", true},
		{"KEYBOARD=value123", false},
		{"KEY_ID=value123", false},
	}
	for _, c := range cases {
		got := redact.New([]string{c.env}).String("x value123 y")
		want := "x value123 y"
		if c.secret {
			want = "x " + ph + " y"
		}
		if got != want {
			t.Errorf("%s: got %q want %q", c.env, got, want)
		}
	}
}

func TestRedactLongestFirst(t *testing.T) {
	r := redact.New([]string{"DB_PASSWORD=secret12", "DB_PASSWORD_OLD=secret12345"})
	got := r.String("pw=secret12345!")
	if got != "pw="+ph+"!" {
		t.Fatalf("got %q", got)
	}
}

func TestRedactPatterns(t *testing.T) {
	r := redact.New(nil)
	jwt := "eyJhbGciOiJI.eyJzdWIiOiIx.SflKxwRJSMeKKF2QT4fw"
	table := []struct{ in, want string }{
		{"id AKIAIOSFODNN7EXAMPLE x", "id " + ph + " x"},
		{"id ASIAIOSFODNN7EXAMPLE x", "id " + ph + " x"},
		{"t " + ghToken() + " x", "t " + ph + " x"},
		{"t gho_" + strings.Repeat("Z", 40) + " x", "t " + ph + " x"},
		{"t github_pat_" + strings.Repeat("A_1", 8) + " x", "t " + ph + " x"},
		{"jwt " + jwt + " x", "jwt " + ph + " x"},
		{"AKIA123 stays", "AKIA123 stays"},
		{"ghp_short stays", "ghp_short stays"},
	}
	for _, c := range table {
		if got := r.String(c.in); got != c.want {
			t.Errorf("%q: got %q want %q", c.in, got, c.want)
		}
	}
}

func TestRedactPrivateKeyBlock(t *testing.T) {
	r := redact.New(nil)
	in := "a\n-----BEGIN RSA PRIVATE KEY-----\nMIIE\n-----END RSA PRIVATE KEY-----\nb\n"
	if got := write(t, r, in); got != "a\n"+ph+"\nb\n" {
		t.Fatalf("got %q", got)
	}
}

func TestRedactPrivateKeyUnterminated(t *testing.T) {
	r := redact.New(nil)
	in := "a\n-----BEGIN PRIVATE KEY-----\nMIIE\nmore\n"
	if got := write(t, r, in); got != "a\n"+ph+"\n" {
		t.Fatalf("got %q", got)
	}
}

func TestRedactNoTrailingNewline(t *testing.T) {
	r := redact.New(nil)
	if got := write(t, r, "x "+ghToken()); got != "x "+ph {
		t.Fatalf("got %q", got)
	}
}

func TestRedactSplitWrites(t *testing.T) {
	r := redact.New(nil)
	tok := ghToken()
	got := write(t, r, "v="+tok[:10], tok[10:]+"\n")
	if got != "v="+ph+"\n" {
		t.Fatalf("got %q", got)
	}
}

func TestRedactHugeLine(t *testing.T) {
	r := redact.New(nil)
	half := strings.Repeat("x", 1<<20)
	got := write(t, r, half+" "+ghToken()+" "+half+"\n")
	want := half + " " + ph + " " + half + "\n"
	if got != want {
		t.Fatalf("len(got)=%d len(want)=%d", len(got), len(want))
	}
}

func TestRedactCloseKeepsDst(t *testing.T) {
	r := redact.New(nil)
	cw := &closeWatcher{}
	w := r.Writer(cw)
	_, _ = w.Write([]byte("hi"))
	_ = w.Close()
	if cw.closed {
		t.Fatal("Close closed dst")
	}
	if cw.buf.String() != "hi" {
		t.Fatalf("got %q", cw.buf.String())
	}
}

type closeWatcher struct {
	buf    bytes.Buffer
	closed bool
}

func (c *closeWatcher) Write(p []byte) (int, error) { return c.buf.Write(p) }
func (c *closeWatcher) Close() error                { c.closed = true; return nil }
