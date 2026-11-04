package setup

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/aether-labs-org/plugins/cli/kh/internal/config"
)

func repo(t *testing.T) string {
	t.Helper()
	d, _ := filepath.EvalSymlinks(t.TempDir())
	if out, err := exec.Command("git", "-C", d, "init", "-q", ".").CombinedOutput(); err != nil {
		t.Fatalf("%v %s", err, out)
	}
	return d
}

func parse(t *testing.T, y string) *config.Config {
	t.Helper()
	c, err := config.Parse([]byte(y))
	if err != nil {
		t.Fatal(err)
	}
	return c
}

func hooksPath(t *testing.T, d string) string {
	out, _ := exec.Command("git", "-C", d, "config", "--get", "core.hooksPath").Output()
	return strings.TrimSpace(string(out))
}

func TestSetupNativeMode(t *testing.T) {
	d := repo(t)
	os.MkdirAll(filepath.Join(d, ".agents/githooks"), 0o755)
	for _, h := range []string{"pre-commit", "commit-msg", "pre-push"} {
		os.WriteFile(filepath.Join(d, ".agents/githooks", h), []byte("#!/bin/sh\n"), 0o644)
	}
	var out bytes.Buffer
	if err := Run(d, parse(t, "version: 1\ngithooks: { mode: native, pre-commit: commit }\n"), &out); err != nil {
		t.Fatal(err)
	}
	if hooksPath(t, d) != ".agents/githooks" || !strings.Contains(out.String(), "core.hooksPath = .agents/githooks (3 hook files executable)") {
		t.Errorf("hooksPath=%q out=%q", hooksPath(t, d), out.String())
	}
	for _, h := range []string{"pre-commit", "commit-msg", "pre-push"} {
		if st, _ := os.Stat(filepath.Join(d, ".agents/githooks", h)); st.Mode()&0o111 == 0 {
			t.Errorf("%s is not executable", h)
		}
	}
	// idempotent
	if err := Run(d, parse(t, "version: 1\ngithooks: { pre-commit: commit }\n"), &out); err != nil {
		t.Fatal(err)
	}
}

func TestSetupNativeModeMissingDir(t *testing.T) {
	d := repo(t)
	if err := Run(d, parse(t, "version: 1\ngithooks: { mode: native }\n"), &bytes.Buffer{}); err == nil || !strings.Contains(err.Error(), ".agents/githooks is missing") {
		t.Fatalf("%v", err)
	}
	if hooksPath(t, d) != "" {
		t.Error("core.hooksPath set without hooks")
	}
}

func TestSetupExternalMode(t *testing.T) {
	d := repo(t)
	var out bytes.Buffer
	y := "version: 1\ngithooks: { mode: external, pre-commit: commit, commit-msg: cm, pre-push: slow }\n"
	if err := Run(d, parse(t, y), &out); err != nil {
		t.Fatal(err)
	}
	s := out.String()
	for _, want := range []string{"external mode", "pre-commit:  sh .agents/bin/kh gate commit", `commit-msg:  sh .agents/bin/kh hook commit-msg "$1"`, "pre-push:    sh .agents/bin/kh gate slow"} {
		if !strings.Contains(s, want) {
			t.Errorf("missing %q in:\n%s", want, s)
		}
	}
	if hooksPath(t, d) != "" {
		t.Error("external mode must not touch core.hooksPath")
	}
}

func TestSetupNotAdopted(t *testing.T) {
	d := repo(t)
	var out bytes.Buffer
	if err := Run(d, parse(t, "version: 1\n"), &out); err != nil || !strings.Contains(out.String(), "not adopted") {
		t.Fatalf("%v %q", err, out.String())
	}
}
