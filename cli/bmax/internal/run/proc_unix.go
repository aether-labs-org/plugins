//go:build unix

package run

import (
	"os"
	"os/exec"
	"syscall"
)

// setGroup puts the command in its own process group.
func setGroup(cmd *exec.Cmd) { cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true} }

// termGroup asks every process of the group to stop.
func termGroup(pgid int) { _ = syscall.Kill(-pgid, syscall.SIGTERM) }

// killGroup kills every process of the group.
func killGroup(pgid int) { _ = syscall.Kill(-pgid, syscall.SIGKILL) }

func exitCode(ps *os.ProcessState) int {
	if ps == nil {
		return -1
	}
	if ws, ok := ps.Sys().(syscall.WaitStatus); ok && ws.Signaled() {
		return 128 + int(ws.Signal())
	}
	return ps.ExitCode()
}
