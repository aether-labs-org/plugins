package script

import (
	"os"
	"os/exec"
	"strconv"
	"strings"

	"github.com/aether-labs-org/plugins/cli/bmax/internal/config"
)

// maxCommandArg bounds the single "-c" argument: Linux refuses an argument
// longer than 128 KiB (MAX_ARG_STRLEN) however large ARG_MAX is.
const maxCommandArg = 100_000

// shQuote quotes one word for a POSIX shell.
func shQuote(s string) string {
	if s != "" && strings.IndexFunc(s, func(r rune) bool {
		return !(r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || strings.ContainsRune("_-./=:@%+,", r))
	}) < 0 {
		return s
	}
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

// Command builds the argv that runs a script: bash -o pipefail -c with the
// script's command, then each file and each extra argument quoted as one word.
// {report} in the command expands to the quoted report path.
func Command(s config.Script, files, extra []string, report string) []string {
	cmd := s.Run
	if report != "" {
		cmd = strings.ReplaceAll(cmd, "{report}", shQuote(report))
	}
	var b strings.Builder
	b.WriteString(cmd)
	if s.PassesFiles() {
		for _, f := range files {
			b.WriteByte(' ')
			b.WriteString(shQuote(f))
		}
	}
	for _, x := range extra {
		b.WriteByte(' ')
		b.WriteString(shQuote(x))
	}
	return []string{"bash", "-o", "pipefail", "-c", b.String()}
}

// DefaultMaxArg is ARG_MAX minus a safety margin and the environment, capped at
// maxCommandArg.
func DefaultMaxArg() int {
	n := 131072
	if out, err := exec.Command("getconf", "ARG_MAX").Output(); err == nil {
		if v, err := strconv.Atoi(strings.TrimSpace(string(out))); err == nil && v > 0 {
			n = v
		}
	}
	env := 0
	for _, e := range os.Environ() {
		env += len(e) + 9
	}
	n -= 4096 + env
	if n > maxCommandArg {
		n = maxCommandArg
	}
	if n < 8192 {
		n = 8192
	}
	return n
}
