package shell

import "strings"

// launcherOpts lists, per launcher, the options that take the next word as
// their argument.
var launcherOpts = map[string]map[string]bool{
	"sudo":    {"-u": true, "-g": true, "-h": true, "-p": true, "-C": true, "-D": true, "-r": true, "-t": true, "-T": true, "-U": true, "-R": true, "--user": true, "--group": true},
	"doas":    {"-u": true, "-C": true},
	"nice":    {"-n": true, "--adjustment": true},
	"timeout": {"-s": true, "--signal": true, "-k": true, "--kill-after": true},
	"exec":    {"-a": true},
	"stdbuf":  {"-i": true, "-o": true, "-e": true},
	"ionice":  {"-c": true, "-n": true, "-p": true, "-P": true, "-u": true},
	"time":    {"-f": true, "-o": true, "--format": true, "--output": true},
	"env":     {"-u": true, "-C": true, "-S": true, "--unset": true, "--chdir": true},
}

// isLauncher: a command that only starts another command.
func isLauncher(name string) bool {
	switch name {
	case "sudo", "doas", "nohup", "nice", "timeout", "command", "exec", "stdbuf", "ionice", "time", "env":
		return true
	}
	return false
}

// Unwrap strips the launcher prefixes of a segment (sudo, nohup, nice, timeout,
// command, exec, stdbuf, ionice, time, env) with their own options, so that
// what runs is what gets analysed. Assignments given to env or sudo are kept as
// assignments. `command -v x` and `command -V x` only query and run nothing: the
// segment is returned without words.
func Unwrap(seg Segment) Segment {
	for depth := 0; depth < 8 && len(seg.Words) > 0; depth++ {
		name := baseName(seg.Words[0])
		if !isLauncher(name) {
			break
		}
		rest := seg.Words[1:]
		vals := launcherOpts[name]
		i := 0
		query := false
		for i < len(rest) {
			w := rest[i]
			if w == "--" {
				i++
				break
			}
			if assignRE.MatchString(w) && (name == "env" || name == "sudo" || name == "doas") {
				seg.Assign = append(seg.Assign, w)
				i++
				continue
			}
			if !strings.HasPrefix(w, "-") || w == "-" {
				break
			}
			if name == "command" && (w == "-v" || w == "-V") {
				query = true
			}
			if vals[w] {
				i += 2
				continue
			}
			i++
		}
		if i > len(rest) {
			i = len(rest)
		}
		rest = rest[i:]
		if name == "timeout" && len(rest) > 0 { // the duration
			rest = rest[1:]
		}
		if query {
			rest = nil
		}
		seg.Words = rest
	}
	return seg
}
