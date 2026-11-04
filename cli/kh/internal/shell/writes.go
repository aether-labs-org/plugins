package shell

import (
	"path"
	"regexp"
	"strings"
)

// nonFlags returns the arguments that do not start with "-".
func nonFlags(args []string) []string {
	var out []string
	positional := false
	for _, a := range args {
		switch {
		case positional && a != "":
			out = append(out, a)
		case a == "--":
			positional = true
		case a != "" && !strings.HasPrefix(a, "-"):
			out = append(out, a)
		}
	}
	return out
}

var interpreterRE = regexp.MustCompile(`^(python[0-9.]*|node|nodejs|perl|ruby|php|deno|bun)$`)

var codeFlag = map[string]bool{"-c": true, "-e": true, "-p": true, "-r": true, "--eval": true, "--print": true}

var stringLit = regexp.MustCompile(`'([^'\n]*)'|"([^"\n]*)"|\x60([^\x60\n]*)\x60`)

// literalsIn returns the contents of the quoted string literals of code.
func literalsIn(code string) []string {
	var out []string
	for _, m := range stringLit.FindAllStringSubmatch(code, -1) {
		for _, g := range m[1:] {
			if g != "" {
				out = append(out, g)
			}
		}
	}
	return out
}

// GitSub returns the subcommand of a git invocation and the words after it,
// skipping git's global options.
func GitSub(words []string) (sub string, rest []string, ok bool) {
	if len(words) == 0 || baseName(words[0]) != "git" {
		return "", nil, false
	}
	i := 1
	for i < len(words) {
		w := words[i]
		switch {
		case w == "-C" || w == "-c" || w == "--git-dir" || w == "--work-tree" || w == "--namespace" || w == "--exec-path" || w == "--config-env" || w == "--super-prefix" || w == "--attr-source":
			i += 2
		case strings.HasPrefix(w, "-"):
			i++
		default:
			return w, words[i+1:], true
		}
	}
	return "", nil, true
}

// WriteTargets lists the paths a segment writes, creates, deletes or truncates
// (spec section 8.2): output redirections, tee, sed -i, perl -i, cp, mv, rm, ln,
// install, truncate, touch, chmod, dd of=, git checkout/restore/reset/apply/rm/mv
// on a path, and the string literals of interpreter code (python -c, node -e,
// perl -e, ruby -e, here-documents fed to an interpreter). A target is a path as
// written in the command: the caller resolves it against the working directory.
func WriteTargets(seg Segment) []string {
	out := append([]string(nil), seg.Redirects...)
	if len(seg.Words) == 0 {
		return out
	}
	head := baseName(seg.Words[0])
	args := seg.Words[1:]
	switch {
	case head == "tee":
		out = append(out, nonFlags(args)...)
	case head == "sed":
		for _, a := range args {
			if a == "--in-place" || strings.HasPrefix(a, "--in-place=") || (strings.HasPrefix(a, "-i")) || (strings.HasPrefix(a, "-") && !strings.HasPrefix(a, "--") && strings.Contains(a, "i")) {
				out = append(out, nonFlags(args)...)
				break
			}
		}
	case head == "perl" || head == "ruby":
		for _, a := range args {
			if strings.HasPrefix(a, "-") && !strings.HasPrefix(a, "--") && strings.Contains(a, "i") && !strings.Contains(a, "e") || strings.HasPrefix(a, "-i") {
				out = append(out, nonFlags(args)...)
				break
			}
		}
		out = append(out, interpreterLiterals(args, seg.Heredoc)...)
	case head == "cp" || head == "install" || head == "rsync":
		out = append(out, copyTargets(args)...)
	case head == "mv":
		out = append(out, nonFlags(args)...)
		out = append(out, copyTargets(args)...)
	case head == "ln":
		out = append(out, copyTargets(args)...)
	case head == "rm", head == "rmdir", head == "unlink", head == "truncate", head == "touch", head == "chmod", head == "chown", head == "chgrp", head == "shred", head == "sponge":
		out = append(out, nonFlags(args)...)
	case head == "dd":
		for _, a := range args {
			if strings.HasPrefix(a, "of=") {
				out = append(out, strings.TrimPrefix(a, "of="))
			}
		}
	case head == "curl":
		for i, a := range args {
			if (a == "-o" || a == "--output") && i+1 < len(args) {
				out = append(out, args[i+1])
			}
		}
	case head == "wget":
		for i, a := range args {
			if (a == "-O" || a == "--output-document") && i+1 < len(args) {
				out = append(out, args[i+1])
			}
		}
	case head == "git":
		sub, rest, _ := GitSub(seg.Words)
		switch sub {
		case "checkout", "restore", "reset", "rm", "mv", "clean":
			out = append(out, nonFlags(rest)...)
		case "apply", "am":
			out = append(out, nonFlags(rest)...)
		}
	case interpreterRE.MatchString(head):
		out = append(out, interpreterLiterals(args, seg.Heredoc)...)
	}
	return dedupe(out)
}

func dedupe(l []string) []string {
	seen := map[string]bool{}
	var out []string
	for _, x := range l {
		if !seen[x] {
			seen[x] = true
			out = append(out, x)
		}
	}
	return out
}

func interpreterLiterals(args []string, heredoc string) []string {
	var out []string
	for i, a := range args {
		if codeFlag[a] && i+1 < len(args) {
			out = append(out, literalsIn(args[i+1])...)
		}
		// -c"code" / -e'code' glued forms and combined flags like -pie
		if len(a) > 2 && a[0] == '-' && a[1] != '-' && (a[1] == 'e' || a[1] == 'c') {
			out = append(out, literalsIn(a[2:])...)
		}
	}
	if heredoc != "" {
		out = append(out, literalsIn(heredoc)...)
	}
	return out
}

// valueFlags are cp/mv/install/ln options that take the next word as a value.
var valueFlags = map[string]bool{"-m": true, "-o": true, "-g": true, "-S": true, "--mode": true, "--owner": true, "--group": true, "--suffix": true,
	// rsync options that take a separate argument
	"-e": true, "--rsh": true, "--exclude": true, "--include": true, "--exclude-from": true, "--include-from": true, "--filter": true, "-f": true,
	"--backup-dir": true, "--temp-dir": true, "-T": true, "--partial-dir": true, "--log-file": true, "--port": true, "--chmod": true, "--chown": true, "--files-from": true}

// copyTargets: the destination of cp/install/ln (the last argument), the file
// that lands in it when it is a directory, and -t DIR.
func copyTargets(args []string) []string {
	var plain []string
	dir := ""
	positional := false
	for i := 0; i < len(args); i++ {
		a := args[i]
		switch {
		case positional:
			plain = append(plain, a)
		case a == "--":
			positional = true
		case a == "-t" || a == "--target-directory":
			if i+1 < len(args) {
				dir = args[i+1]
				i++
			}
		case strings.HasPrefix(a, "--target-directory="):
			dir = strings.TrimPrefix(a, "--target-directory=")
		case valueFlags[a]:
			i++
		case strings.HasPrefix(a, "-"):
		default:
			plain = append(plain, a)
		}
	}
	var out []string
	if dir != "" {
		out = append(out, dir)
		for _, s := range plain {
			out = append(out, path.Join(dir, path.Base(s)))
		}
		return out
	}
	if len(plain) >= 2 {
		dest := plain[len(plain)-1]
		out = append(out, dest)
		for _, s := range plain[:len(plain)-1] {
			out = append(out, path.Join(dest, path.Base(s)))
		}
	}
	return out
}

var patchPathRE = regexp.MustCompile(`(?m)^(?:\+\+\+|---) (?:[ab]/)?([^\t\n]+)`)

// PatchTargets lists the paths named by a unified diff (git apply, patch).
func PatchTargets(patch string) []string {
	var out []string
	for _, m := range patchPathRE.FindAllStringSubmatch(patch, -1) {
		if m[1] != "/dev/null" {
			out = append(out, m[1])
		}
	}
	return out
}

var cluster = regexp.MustCompile(`^-[a-zA-Z]*n[a-zA-Z]*$`)

var gitConfigKeyRE = regexp.MustCompile(`^GIT_CONFIG_KEY_[0-9]+=(.*)$`)

func isHooksPathKey(v string) bool {
	return strings.EqualFold(strings.Trim(strings.TrimSpace(v), `"'`), "core.hookspath")
}

// Forbidden reports a command kh never lets an agent run: skipping the git
// hooks, redirecting the hooks path (by option, configuration or environment),
// hiding a file from git, or overriding the pinned kh binary or its download URL.
func Forbidden(seg Segment) (reason string, ok bool) {
	for _, w := range append(append([]string{}, seg.Assign...), seg.Words...) {
		switch {
		case strings.HasPrefix(w, "KH_BINARY=") || strings.HasPrefix(w, "KH_RELEASE_URL="):
			return "an inline " + w[:strings.IndexByte(w, '=')] + "= replaces the pinned kh; ask the human to set it outside the agent session", true
		case gitConfigKeyRE.MatchString(w) && isHooksPathKey(gitConfigKeyRE.FindStringSubmatch(w)[1]):
			return "GIT_CONFIG_KEY_<n>=core.hooksPath redirects the git hooks through the environment", true
		case strings.HasPrefix(w, "GIT_CONFIG_PARAMETERS=") && strings.Contains(strings.ToLower(w), "hookspath"):
			return "GIT_CONFIG_PARAMETERS with core.hooksPath redirects the git hooks through the environment", true
		}
	}
	if len(seg.Words) == 0 || baseName(seg.Words[0]) != "git" {
		return "", false
	}
	// git -c core.hooksPath=... and --config-env core.hooksPath=VAR, before the subcommand
	for i := 1; i < len(seg.Words); i++ {
		w := seg.Words[i]
		switch {
		case w == "-c" && i+1 < len(seg.Words) && strings.HasPrefix(strings.ToLower(seg.Words[i+1]), "core.hookspath"):
			return "git -c core.hooksPath redirects the git hooks", true
		case w == "--config-env" && i+1 < len(seg.Words) && strings.HasPrefix(strings.ToLower(seg.Words[i+1]), "core.hookspath"):
			return "git --config-env core.hooksPath redirects the git hooks", true
		case strings.HasPrefix(w, "--config-env=") && strings.HasPrefix(strings.ToLower(strings.TrimPrefix(w, "--config-env=")), "core.hookspath"):
			return "git --config-env core.hooksPath redirects the git hooks", true
		}
	}
	sub, rest, _ := GitSub(seg.Words)
	for _, a := range rest {
		// git accepts any unambiguous prefix of a long option
		if len(a) >= len("--no-v") && strings.HasPrefix("--no-verify", a) {
			return "git " + sub + " " + a + " skips the git hooks", true
		}
	}
	switch sub {
	case "commit":
		for _, a := range rest {
			if a == "--" {
				break
			}
			if a == "-n" || cluster.MatchString(a) {
				return "git commit -n skips the git hooks", true
			}
		}
	case "config":
		if configSetsHooksPath(rest) {
			return "git config core.hooksPath redirects the git hooks", true
		}
	case "update-index":
		for _, a := range rest {
			if a == "--assume-unchanged" || a == "--skip-worktree" {
				return "git update-index " + a + " hides changes from git", true
			}
		}
	}
	return "", false
}

// configSetsHooksPath: a git config call that names core.hooksPath and writes
// it (a value, --unset, --replace-all, --add, set/unset). Reading it is fine.
func configSetsHooksPath(args []string) bool {
	named := false
	for _, a := range args {
		if strings.HasPrefix(strings.ToLower(a), "core.hookspath") {
			named = true
		}
	}
	if !named {
		return false
	}
	get := false
	for _, a := range args {
		switch a {
		case "--unset", "--unset-all", "--replace-all", "--add", "--edit", "-e":
			return true
		case "--get", "--get-all", "--get-regexp", "--get-urlmatch", "--list", "-l":
			get = true
		}
	}
	pos := nonFlags(args)
	if len(pos) > 0 && (pos[0] == "set" || pos[0] == "unset") {
		return true
	}
	if get {
		return false
	}
	return len(pos) >= 2 // name and value
}

// Destructive reports whether naming a directory makes the command write
// below it: removing or moving, and recursive copies (cp -r/-R/-a, rsync -r/-a)
// into a directory, which write whatever the source tree holds.
func Destructive(seg Segment) bool {
	if len(seg.Words) == 0 {
		return false
	}
	head := baseName(seg.Words[0])
	switch head {
	case "rm", "rmdir", "unlink", "mv", "shred":
		return true
	case "cp", "rsync", "install":
		for _, a := range seg.Words[1:] {
			if a == "--" {
				break
			}
			if a == "--recursive" || a == "--archive" {
				return true
			}
			if strings.HasPrefix(a, "-") && !strings.HasPrefix(a, "--") && strings.ContainsAny(a[1:], "rRa") {
				return true
			}
		}
	case "git":
		sub, _, _ := GitSub(seg.Words)
		return sub == "rm" || sub == "clean" || sub == "checkout" || sub == "restore" || sub == "reset" || sub == "mv"
	}
	return false
}
