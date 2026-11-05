//go:build unix

package run

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"path/filepath"
	"syscall"
	"testing"
	"time"
)

func sh(script string) []string { return []string{"sh", "-c", script} }

func goneGroup(t *testing.T, pgid int) {
	t.Helper()
	if pgid <= 0 {
		t.Fatalf("pgid not recorded: %d", pgid)
	}
	deadline := time.Now().Add(2 * time.Second)
	for {
		err := syscall.Kill(-pgid, 0)
		if err == syscall.ESRCH {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("process group %d still alive: kill(-pgid,0) = %v", pgid, err)
		}
		time.Sleep(20 * time.Millisecond)
	}
}

func TestRunExitCodes(t *testing.T) {
	for _, n := range []int{0, 1, 2, 137} {
		var out bytes.Buffer
		o := Run(context.Background(), Spec{Argv: sh(fmt.Sprintf("exit %d", n))}, &out)
		if o.ExitCode != n || o.TimedOut || o.Interrupted || o.NotFound || o.StartErr != nil {
			t.Errorf("exit %d: %+v", n, o)
		}
	}
}

func TestRunSignalExit(t *testing.T) {
	var out bytes.Buffer
	o := Run(context.Background(), Spec{Argv: sh("kill -9 $$")}, &out)
	if o.ExitCode != 137 {
		t.Fatalf("ExitCode = %d, want 137", o.ExitCode)
	}
}

func TestRunOrderedCapture(t *testing.T) {
	var out bytes.Buffer
	Run(context.Background(), Spec{Argv: sh("echo a; echo b >&2; echo c")}, &out)
	if out.String() != "a\nb\nc\n" {
		t.Fatalf("out = %q", out.String())
	}
}

func TestRunNotFound(t *testing.T) {
	var out bytes.Buffer
	o := Run(context.Background(), Spec{Argv: []string{"bmax-no-such-cmd-xyz"}}, &out)
	if !o.NotFound || o.ExitCode != -1 || o.StartErr != nil {
		t.Fatalf("%+v", o)
	}
}

func TestRunNotExecutable(t *testing.T) {
	p := filepath.Join(t.TempDir(), "x")
	if err := os.WriteFile(p, []byte("#!/bin/sh\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	var out bytes.Buffer
	o := Run(context.Background(), Spec{Argv: []string{p}}, &out)
	if !o.NotFound || o.ExitCode != -1 {
		t.Fatalf("%+v", o)
	}
}

func TestRunBadDir(t *testing.T) {
	var out bytes.Buffer
	o := Run(context.Background(), Spec{Argv: []string{"true"}, Dir: "/no/such/dir/xyz"}, &out)
	if o.NotFound || o.StartErr == nil || o.ExitCode != -1 {
		t.Fatalf("%+v", o)
	}
}

func TestRunTimeoutKillsGroup(t *testing.T) {
	var out bytes.Buffer
	start := time.Now()
	o := Run(context.Background(), Spec{Argv: sh("sleep 30 & sleep 30"), Timeout: 200 * time.Millisecond}, &out)
	if !o.TimedOut || o.Interrupted {
		t.Fatalf("%+v", o)
	}
	if el := time.Since(start); el > 2*time.Second {
		t.Fatalf("elapsed %v", el)
	}
	goneGroup(t, o.pgid)
}

func TestRunTermIgnored(t *testing.T) {
	var out bytes.Buffer
	start := time.Now()
	o := Run(context.Background(), Spec{
		Argv:      sh(`trap "" TERM; sleep 30`),
		Timeout:   100 * time.Millisecond,
		KillGrace: 100 * time.Millisecond,
	}, &out)
	if !o.TimedOut {
		t.Fatalf("%+v", o)
	}
	if el := time.Since(start); el > 2*time.Second {
		t.Fatalf("elapsed %v", el)
	}
	goneGroup(t, o.pgid)
}

func TestRunCancelKillsGroup(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	go func() {
		time.Sleep(100 * time.Millisecond)
		cancel()
	}()
	var out bytes.Buffer
	start := time.Now()
	o := Run(ctx, Spec{Argv: sh("sleep 30 & sleep 30")}, &out)
	if !o.Interrupted || o.TimedOut {
		t.Fatalf("%+v", o)
	}
	if el := time.Since(start); el > 2*time.Second {
		t.Fatalf("elapsed %v", el)
	}
	goneGroup(t, o.pgid)
}

func TestRunBackgroundChildReleased(t *testing.T) {
	var out bytes.Buffer
	start := time.Now()
	o := Run(context.Background(), Spec{Argv: sh("sleep 30 & echo started")}, &out)
	if el := time.Since(start); el > 2*time.Second {
		t.Fatalf("elapsed %v", el)
	}
	if o.ExitCode != 0 || out.String() != "started\n" {
		t.Fatalf("%+v out=%q", o, out.String())
	}
	goneGroup(t, o.pgid)
}

func TestRunDir(t *testing.T) {
	d, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	var out bytes.Buffer
	Run(context.Background(), Spec{Argv: []string{"pwd"}, Dir: d}, &out)
	if out.String() != d+"\n" {
		t.Fatalf("out = %q, want %q", out.String(), d+"\n")
	}
}

func TestRunTimestamps(t *testing.T) {
	var out bytes.Buffer
	o := Run(context.Background(), Spec{Argv: []string{"true"}}, &out)
	if o.Started.IsZero() || o.Finished.Before(o.Started) {
		t.Fatalf("%+v", o)
	}
}

// BMAX_ROOT is the wrapper's hand-off to the bmax process it execs: a bmax started by a script must not inherit it.
func TestRunDoesNotPassBmaxRoot(t *testing.T) {
	t.Setenv("BMAX_ROOT", "/outer/repository")
	t.Setenv("BMAX_KEEP", "yes")
	var out bytes.Buffer
	Run(context.Background(), Spec{Argv: sh(`printf '%s|%s' "${BMAX_ROOT-unset}" "${BMAX_KEEP-unset}"`)}, &out)
	if out.String() != "unset|yes" {
		t.Fatalf("inherited env: %q", out.String())
	}
	out.Reset()
	Run(context.Background(), Spec{Argv: sh(`printf '%s|%s' "${BMAX_ROOT-unset}" "${BMAX_KEEP-unset}"`), Env: []string{"PATH=" + os.Getenv("PATH"), "BMAX_ROOT=/explicit", "BMAX_KEEP=no"}}, &out)
	if out.String() != "unset|no" {
		t.Fatalf("explicit env: %q", out.String())
	}
}

// A script runs with the git variables that a hook inherits (GIT_DIR, GIT_INDEX_FILE, ...) removed: a git command it
// runs in another directory would otherwise act on the repository that is being committed or pushed.
func TestChildEnvDropsRepositoryLocalGitVariables(t *testing.T) {
	in := []string{"PATH=/bin", "HOME=/h", "GIT_DIR=/r/.git/worktrees/w", "GIT_WORK_TREE=/r", "GIT_INDEX_FILE=/r/.git/worktrees/w/index",
		"GIT_COMMON_DIR=/r/.git", "GIT_PREFIX=sub/", "GIT_OBJECT_DIRECTORY=/o", "BMAX_ROOT=/r", "GIT_SSH_COMMAND=ssh -i k", "GIT_EDITOR=true"}
	got := childEnv(in)
	want := []string{"PATH=/bin", "HOME=/h", "GIT_SSH_COMMAND=ssh -i k", "GIT_EDITOR=true"}
	if fmt.Sprint(got) != fmt.Sprint(want) {
		t.Fatalf("childEnv = %v, want %v", got, want)
	}
}

func TestRunDoesNotPassGitVariables(t *testing.T) {
	t.Setenv("GIT_DIR", "/nonexistent/.git")
	t.Setenv("GIT_INDEX_FILE", "/nonexistent/index")
	t.Setenv("GIT_EDITOR", "true")
	var out bytes.Buffer
	Run(context.Background(), Spec{Argv: sh(`printf '%s|%s|%s' "${GIT_DIR-unset}" "${GIT_INDEX_FILE-unset}" "${GIT_EDITOR-unset}"`)}, &out)
	if out.String() != "unset|unset|true" {
		t.Fatalf("%q", out.String())
	}
}
