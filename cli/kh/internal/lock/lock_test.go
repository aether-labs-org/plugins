package lock_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/aether-labs-org/plugins/cli/kh/internal/lock"
)

func hex64(c string) string { return strings.Repeat(c, 64) }

func sample() lock.Lock {
	return lock.Lock{Version: "0.5.0", SHA256: map[string]string{
		"linux-amd64": hex64("a"), "linux-arm64": hex64("b"),
		"darwin-amd64": hex64("c"), "darwin-arm64": hex64("d"),
	}}
}

func TestLockRoundTrip(t *testing.T) {
	text := lock.Format(sample())
	if !strings.HasPrefix(text, "# keel.lock - kh pin; written by keel, do not edit by hand\nversion=0.5.0\nlinux-amd64=") {
		t.Fatalf("format:\n%s", text)
	}
	p := filepath.Join(t.TempDir(), "keel.lock")
	os.WriteFile(p, []byte(text), 0o644)
	got, err := lock.Read(p)
	if err != nil {
		t.Fatal(err)
	}
	if got.Version != "0.5.0" || got.SHA256["darwin-arm64"] != hex64("d") || len(got.SHA256) != 4 {
		t.Fatalf("got %+v", got)
	}
}

func TestLockCRLF(t *testing.T) {
	text := strings.ReplaceAll(lock.Format(sample()), "\n", "\r\n")
	p := filepath.Join(t.TempDir(), "keel.lock")
	os.WriteFile(p, []byte(text), 0o644)
	if _, err := lock.Read(p); err != nil {
		t.Fatal(err)
	}
}

func TestLockRejectsBadHex(t *testing.T) {
	l := sample()
	l.SHA256["linux-amd64"] = strings.Repeat("a", 63)
	p := filepath.Join(t.TempDir(), "keel.lock")
	os.WriteFile(p, []byte(lock.Format(l)), 0o644)
	if _, err := lock.Read(p); err == nil || !strings.Contains(err.Error(), "linux-amd64") {
		t.Fatalf("err = %v", err)
	}
}

func TestLockRejectsMissingVersionAndUnknownKey(t *testing.T) {
	p := filepath.Join(t.TempDir(), "keel.lock")
	os.WriteFile(p, []byte("linux-amd64="+hex64("a")+"\n"), 0o644)
	if _, err := lock.Read(p); err == nil {
		t.Fatal("missing version accepted")
	}
	os.WriteFile(p, []byte("version=1\nplan9-mips="+hex64("a")+"\n"), 0o644)
	if _, err := lock.Read(p); err == nil {
		t.Fatal("unknown platform accepted")
	}
}

func TestCheckMismatch(t *testing.T) {
	l := lock.Lock{Version: "0.5.0"}
	if err := lock.Check(l, "0.5.0"); err != nil {
		t.Fatal(err)
	}
	err := lock.Check(l, "0.5.1")
	if err == nil || !strings.Contains(err.Error(), "pin mismatch: keel.lock pins 0.5.0, this kh is 0.5.1") {
		t.Fatalf("err = %v", err)
	}
}
