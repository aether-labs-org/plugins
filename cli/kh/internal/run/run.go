//go:build unix

// Package run executes a command in its own process group with a timeout,
// capturing stdout and stderr into one ordered stream.
package run

import (
	"context"
	"errors"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"syscall"
	"time"
)

const (
	// DefaultTimeout is used when Spec.Timeout is zero.
	DefaultTimeout = 10 * time.Minute
	// DefaultKillGrace is used when Spec.KillGrace is zero.
	DefaultKillGrace = 5 * time.Second
)

// drainWait bounds how long Run waits for the output pipe to close after the
// process group is gone (a process that escaped the group can hold it open).
const drainWait = 2 * time.Second

// Spec describes one command execution.
type Spec struct {
	Argv      []string // executed directly, no shell
	Dir       string
	Env       []string // nil inherits the environment of kh
	Timeout   time.Duration
	KillGrace time.Duration
}

// Outcome is what happened to the command.
type Outcome struct {
	ExitCode    int // 128+signal for a signal-terminated process; -1 if it never ran
	TimedOut    bool
	Interrupted bool // ctx was cancelled
	NotFound    bool // Argv[0] could not be found or executed
	StartErr    error
	Started     time.Time
	Finished    time.Time

	pgid int // for tests
}

// Run executes s, copying the combined stdout and stderr to out. On timeout or
// ctx cancellation the process group gets SIGTERM, then SIGKILL after the
// grace period. After the main process exits, the group is killed so that no
// background child outlives the run or holds the output open.
func Run(ctx context.Context, s Spec, out io.Writer) (o Outcome) {
	o = Outcome{ExitCode: -1, Started: time.Now()}
	defer func() { o.Finished = time.Now() }()

	if len(s.Argv) == 0 {
		o.StartErr = errors.New("empty command")
		return o
	}
	timeout, grace := s.Timeout, s.KillGrace
	if timeout == 0 {
		timeout = DefaultTimeout
	}
	if grace == 0 {
		grace = DefaultKillGrace
	}
	if s.Dir != "" {
		if st, err := os.Stat(s.Dir); err != nil || !st.IsDir() {
			if err == nil {
				err = errors.New("not a directory")
			}
			o.StartErr = errors.New("working directory " + s.Dir + ": " + err.Error())
			return o
		}
	}

	pr, pw, err := os.Pipe()
	if err != nil {
		o.StartErr = err
		return o
	}
	cmd := exec.Command(s.Argv[0], s.Argv[1:]...)
	cmd.Dir = s.Dir
	cmd.Env = s.Env
	cmd.Stdout = pw
	cmd.Stderr = pw
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := cmd.Start(); err != nil {
		pw.Close()
		pr.Close()
		if errors.Is(err, exec.ErrNotFound) || errors.Is(err, fs.ErrNotExist) || errors.Is(err, fs.ErrPermission) {
			o.NotFound = true
		} else {
			o.StartErr = err
		}
		return o
	}
	pw.Close()
	o.pgid = cmd.Process.Pid

	copyDone := make(chan struct{})
	go func() {
		_, _ = io.Copy(out, pr)
		close(copyDone)
	}()
	waitCh := make(chan error, 1)
	go func() { waitCh <- cmd.Wait() }()

	timer := time.NewTimer(timeout)
	defer timer.Stop()
	select {
	case <-waitCh:
	case <-timer.C:
		o.TimedOut = true
		terminate(o.pgid, waitCh, grace)
	case <-ctx.Done():
		o.Interrupted = true
		terminate(o.pgid, waitCh, grace)
	}

	// The main process is gone: nothing else of the group may keep running.
	_ = syscall.Kill(-o.pgid, syscall.SIGKILL)

	select {
	case <-copyDone:
	case <-time.After(drainWait):
		pr.Close()
		<-copyDone
	}
	pr.Close()

	o.ExitCode = exitCode(cmd.ProcessState)
	return o
}

// terminate sends SIGTERM to the group, waits up to grace for the main process,
// then sends SIGKILL.
func terminate(pgid int, waitCh <-chan error, grace time.Duration) {
	_ = syscall.Kill(-pgid, syscall.SIGTERM)
	select {
	case <-waitCh:
		return
	case <-time.After(grace):
	}
	_ = syscall.Kill(-pgid, syscall.SIGKILL)
	<-waitCh
}

func exitCode(ps *os.ProcessState) int {
	if ps == nil {
		return -1
	}
	if ws, ok := ps.Sys().(syscall.WaitStatus); ok && ws.Signaled() {
		return 128 + int(ws.Signal())
	}
	return ps.ExitCode()
}
