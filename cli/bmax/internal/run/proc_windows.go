//go:build windows

package run

import (
	"os"
	"os/exec"
	"strconv"
	"syscall"
)

// setGroup starts the command in a new process group (no console signal reaches it from bmax's console).
func setGroup(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{CreationFlags: syscall.CREATE_NEW_PROCESS_GROUP}
}

// termGroup: Windows has no SIGTERM for a process tree, so the grace period is not honoured; the tree is killed.
func termGroup(pid int) { killGroup(pid) }

// killGroup kills the process and its children (taskkill walks the tree; Windows has no negative-pid kill).
func killGroup(pid int) {
	if pid <= 0 {
		return
	}
	_ = exec.Command("taskkill", "/T", "/F", "/PID", strconv.Itoa(pid)).Run()
}

func exitCode(ps *os.ProcessState) int {
	if ps == nil {
		return -1
	}
	return ps.ExitCode()
}
