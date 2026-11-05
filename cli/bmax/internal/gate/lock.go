package gate

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// staleAfter: a lock older than this is taken over even if its pid is alive
// (the pid may have been reused).
const staleAfter = 24 * time.Hour

func pidAlive(pid int) bool {
	if pid <= 0 {
		return false
	}
	err := syscall.Kill(pid, 0)
	return err == nil || errors.Is(err, syscall.EPERM)
}

// Acquire takes .agents/run/gate.lock, waiting up to wait for a live holder.
// A lock whose pid is dead (a killed bmax) is taken over at once.
func Acquire(root string, wait time.Duration) (release func(), err error) {
	dir := filepath.Join(root, ".agents", "run")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return nil, err
	}
	path := filepath.Join(dir, "gate.lock")
	me := os.Getpid()
	deadline := time.Now().Add(wait)
	for {
		f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
		if err == nil {
			fmt.Fprintf(f, "%d\n", me)
			f.Close()
			return func() {
				if b, err := os.ReadFile(path); err == nil && strings.TrimSpace(string(b)) == strconv.Itoa(me) {
					os.Remove(path)
				}
			}, nil
		}
		if !errors.Is(err, fs.ErrExist) {
			return nil, err
		}
		holder := 0
		stale := false
		if b, rerr := os.ReadFile(path); rerr == nil {
			holder, _ = strconv.Atoi(strings.TrimSpace(string(b)))
			if st, serr := os.Stat(path); serr == nil && time.Since(st.ModTime()) > staleAfter {
				stale = true
			}
		} else if errors.Is(rerr, fs.ErrNotExist) {
			continue // released between the two calls
		}
		if stale || !pidAlive(holder) {
			os.Remove(path)
			continue
		}
		if time.Now().After(deadline) {
			return nil, fmt.Errorf("another gate is running (pid %d)", holder)
		}
		time.Sleep(50 * time.Millisecond)
	}
}
