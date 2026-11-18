//go:build windows

package gate

import "syscall"

const processQueryLimitedInformation = 0x1000

// pidAlive opens the process with the least access; a pid that cannot be opened is treated as gone
// (an access-denied pid is still alive, which errors other than ERROR_INVALID_PARAMETER say).
func pidAlive(pid int) bool {
	if pid <= 0 {
		return false
	}
	h, err := syscall.OpenProcess(processQueryLimitedInformation, false, uint32(pid))
	if err != nil {
		return err == syscall.ERROR_ACCESS_DENIED
	}
	defer syscall.CloseHandle(h)
	var code uint32
	if err := syscall.GetExitCodeProcess(h, &code); err != nil {
		return false
	}
	return code == 259 // STILL_ACTIVE
}
