// Package gate runs the fast or the slow gate and renders gate.sh's report byte for byte.
package gate

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/aether-labs-org/plugins/cli/keel/internal/config"
)

// Adapter runs a built-in sensor in-process and returns its contract output and exit code.
type Adapter func(root string) (out string, rc int)

// Adapters maps adapter names to implementations; main wires "guard".
var Adapters = map[string]Adapter{}

var runState = regexp.MustCompile(`^\.agents/(last-[^/]*|\.gate-lock/.*)$`)

func git(root string, args ...string) (string, error) {
	cmd := exec.Command("git", args...)
	cmd.Dir = root
	out, err := cmd.Output()
	return string(out), err
}

// Scope returns gate.sh's SCOPE (changed files since HEAD, untracked included, deleted and keel's run
// state excluded, sorted bytewise and unique) and the note used when it is empty.
func Scope(root string) (scope, emptyNote string) {
	if _, err := git(root, "rev-parse", "--verify", "-q", "HEAD"); err != nil {
		return "", "no commits yet"
	}
	diff, _ := git(root, "-c", "core.quotepath=off", "diff", "--name-only", "--diff-filter=d", "HEAD")
	others, _ := git(root, "-c", "core.quotepath=off", "ls-files", "--others", "--exclude-standard")
	set := map[string]bool{}
	for _, l := range strings.Split(diff+"\n"+others, "\n") {
		if l != "" && !runState.MatchString(l) {
			set[l] = true
		}
	}
	files := make([]string, 0, len(set))
	for f := range set {
		files = append(files, f)
	}
	sort.Strings(files)
	return strings.Join(files, "\n"), "no uncommitted changes"
}

// RunSensor runs one sensor from root with SCOPE (and the rest of env) as given, the way gate.sh
// did: `bash <file>` with stderr merged into stdout. It returns the raw output and the exit code.
func RunSensor(root string, s config.Sensor, env []string) (string, int) {
	if s.Adapter != "" {
		a, ok := Adapters[s.Adapter]
		if !ok {
			return "", 127
		}
		return a(root)
	}
	cmd := exec.Command("bash", s.Exec)
	cmd.Dir = root
	cmd.Env = env
	var buf bytes.Buffer
	cmd.Stdout = &buf
	cmd.Stderr = &buf
	err := cmd.Run()
	rc := 0
	if err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			rc = ee.ExitCode()
		} else {
			rc = 127
		}
	}
	return buf.String(), rc
}

// WithScope returns env with SCOPE replaced.
func WithScope(env []string, scope string) []string {
	out := make([]string, 0, len(env)+1)
	for _, kv := range env {
		if !strings.HasPrefix(kv, "SCOPE=") {
			out = append(out, kv)
		}
	}
	return append(out, "SCOPE="+scope)
}

// cutField mimics `cut -f n` on one line: a line without a TAB is printed whole.
func cutField(line string, n int) string {
	if !strings.Contains(line, "\t") {
		return line
	}
	f := strings.Split(line, "\t")
	if n-1 < len(f) {
		return f[n-1]
	}
	return ""
}

// padRight and padLeft pad by bytes, as bash's printf %-Ns and %Ns do in every locale.
func padRight(s string, w int) string {
	if len(s) >= w {
		return s
	}
	return s + strings.Repeat(" ", w-len(s))
}

func padLeft(s string, w int) string {
	if len(s) >= w {
		return s
	}
	return strings.Repeat(" ", w-len(s)) + s
}

func duration(ms int64) string {
	if ms >= 1000 {
		return fmt.Sprintf("%d.%ds", ms/1000, (ms%1000)/100)
	}
	return fmt.Sprintf("%dms", ms)
}

// Marks returns pass/fail/skip marks: Unicode only on a UTF-8 terminal, like gate.sh.
func Marks(tty bool) (string, string, string) {
	if tty && utf8Locale() {
		return "✓", "✗", "○"
	}
	return "v", "x", "-"
}

func utf8Locale() bool {
	for _, k := range []string{"LC_ALL", "LC_CTYPE", "LANG"} {
		if v := os.Getenv(k); v != "" {
			v = strings.ToLower(v)
			return strings.Contains(v, "utf-8") || strings.Contains(v, "utf8")
		}
	}
	return false
}

// IsTTY reports whether f is a terminal.
func IsTTY(f *os.File) bool {
	st, err := f.Stat()
	return err == nil && st.Mode()&os.ModeCharDevice != 0
}

// LogPath is where the full report of a gate run is kept.
func LogPath(mode string) string {
	if mode == "slow" {
		return ".agents/last-run-slow.log"
	}
	return ".agents/last-run.log"
}

// Run runs every sensor of the gate, writes the full report to LogPath(mode), prints at most 40
// lines of it to w plus where the full log is, and returns 1 when any sensor failed, else 0.
func Run(root, mode string, c *config.Config, w io.Writer, tty bool) int {
	_ = os.MkdirAll(filepath.Join(root, ".agents"), 0o755)
	mPass, mFail, mSkip := Marks(tty)
	scope, emptyNote := Scope(root)
	env := WithScope(os.Environ(), scope)
	nScope := 0
	for _, l := range strings.Split(scope, "\n") {
		if l != "" {
			nScope++
		}
	}

	var report strings.Builder
	var totalMS int64
	n, failed, skipped := 0, 0, 0
	for _, s := range c.SensorsFor(mode) {
		n++
		start := time.Now()
		raw, rc := RunSensor(root, s, env)
		ms := time.Since(start).Milliseconds()
		totalMS += ms

		out := strings.TrimRight(raw, "\n") // $(...) strips trailing newlines
		head1, rest, _ := strings.Cut(out, "\n")
		body := strings.TrimRight(rest, "\n")
		cls, sum := cutField(head1, 2), cutField(head1, 4)

		mark := mPass
		switch rc {
		case 0:
		case 2:
			mark = mSkip
			skipped++
		default:
			mark = mFail
			failed++
		}
		fmt.Fprintf(&report, "%s %s [%s] %s %s\n", mark, padRight(s.ID, 12), padRight(cls, 11), padRight(sum, 44), padLeft(duration(ms), 8))
		if body != "" {
			report.WriteString(body + "\n")
		}
	}

	scopeLine := "scope: whole repository (" + emptyNote + ")"
	if nScope > 0 {
		scopeLine = fmt.Sprintf("scope: %d files changed since last commit", nScope)
	}
	ceiling := c.Ceiling(mode)
	over := ""
	if totalMS > int64(ceiling)*1000 {
		over = " (over ceiling)"
	}
	ran := n - skipped
	var verdict string
	switch {
	case skipped == 0 && failed > 0:
		verdict = fmt.Sprintf("FAILED (%d of %d)", failed, n)
	case skipped == 0:
		verdict = fmt.Sprintf("PASSED (%d of %d)", n, n)
	case failed > 0:
		verdict = fmt.Sprintf("FAILED (%d of %d, %d skipped)", failed, ran, skipped)
	default:
		verdict = fmt.Sprintf("PASSED (%d of %d, %d skipped)", ran-failed, ran, skipped)
	}
	full := report.String() + "\n" + scopeLine + "\n" +
		fmt.Sprintf("gate: %s - %s | ceiling %ds, spent %s%s | model cost: US$0.00\n", mode, verdict, ceiling, duration(totalMS), over)

	log := LogPath(mode)
	_ = os.WriteFile(filepath.Join(root, log), []byte(full), 0o644)
	lines := strings.SplitAfter(full, "\n")
	if lines[len(lines)-1] == "" {
		lines = lines[:len(lines)-1]
	}
	if len(lines) > 40 {
		io.WriteString(w, strings.Join(lines[:40], ""))
		fmt.Fprintf(w, "output truncated at 40 lines - full log in %s\n", log)
	} else {
		io.WriteString(w, full)
		fmt.Fprintf(w, "full log in %s\n", log)
	}
	if failed > 0 {
		return 1
	}
	return 0
}
