package shell

import "strings"

// launchers extend the signature through the tool they start: the word after
// them (skipping options) names what runs.
var launchers = map[string]int{
	"make": 1, "bash": 1, "sh": 1, "zsh": 1, "dash": 1,
	"python": 0, "python3": 0, "node": 1, "ruby": 1, "perl": 1,
}

var skipSegments = map[string]bool{"cd": true, "export": true, "echo": true}

func firstNonOption(words []string) (string, int) {
	for i, w := range words {
		if !strings.HasPrefix(w, "-") {
			return w, i
		}
	}
	return "", -1
}

func normArg(w string) string { return strings.TrimPrefix(w, "./") }

// jsValueOpts are options of the JavaScript package managers that take the
// next word as their value (so that it is not mistaken for the binary).
var jsValueOpts = map[string]bool{"--filter": true, "-F": true, "-C": true, "--dir": true, "--cwd": true, "-p": true, "--package": true, "--workspace": true, "-w": false}

// firstBin returns the first word that is not an option or "--", skipping the
// values of the options that take one.
func firstBin(words []string) string {
	for i := 0; i < len(words); i++ {
		w := words[i]
		switch {
		case w == "--":
			continue
		case strings.HasPrefix(w, "-"):
			if jsValueOpts[w] {
				i++
			}
		default:
			return normArg(baseName(w))
		}
	}
	return ""
}

// pnpmYarnBuiltin: sub-commands of pnpm and yarn that are not binaries; a bare
// word outside this set is a binary (`pnpm vitest`, `yarn vitest`).
var pnpmYarnBuiltin = map[string]bool{}

func init() {
	for _, w := range strings.Fields(`run exec dlx x install i add remove rm uninstall update up upgrade upgrade-interactive test t start stop restart
		publish pack link ln unlink list ls ll outdated audit why init create store config c cache env prune rebuild rb dedupe patch patch-commit
		fetch import deploy setup root bin licenses recursive multi server doctor help version self-update approve-builds ignored-builds sbom
		info versions workspace workspaces plugin policies set node constraints npm autoclean check generate-lock-entry login logout owner tag team unplug global`) {
		pnpmYarnBuiltin[w] = true
	}
}

// jsSignature normalises the JavaScript launchers to the binary they run, so a
// script declared as `npx vitest run` is matched by `pnpm vitest run`,
// `pnpm exec vitest`, `yarn vitest`, `bunx vitest`... Commands that run package
// scripts (npm run, npm test, pnpm run, yarn run, bun run) keep their own signature.
func jsSignature(head string, rest []string) (string, bool) {
	switch head {
	case "npx", "bunx", "pnpx":
		return firstBin(rest), true
	case "npm":
		sub, i := firstNonOption(rest)
		switch sub {
		case "exec", "x":
			return firstBin(rest[i+1:]), true
		case "run", "run-script":
			if n, _ := firstNonOption(rest[i+1:]); n != "" {
				return "npm run " + n, true
			}
			return "npm run", true
		case "":
			return "npm", true
		}
		return "npm " + sub, true
	case "bun":
		sub, i := firstNonOption(rest)
		switch sub {
		case "x":
			return firstBin(rest[i+1:]), true
		case "run":
			if n, _ := firstNonOption(rest[i+1:]); n != "" {
				return "bun run " + n, true
			}
			return "bun run", true
		case "":
			return "bun", true
		}
		return "bun " + sub, true
	case "pnpm", "yarn":
		// options before the sub-command (pnpm --filter web vitest)
		var sub string
		idx := -1
		for i := 0; i < len(rest); i++ {
			w := rest[i]
			if strings.HasPrefix(w, "-") {
				if jsValueOpts[w] {
					i++
				}
				continue
			}
			sub, idx = w, i
			break
		}
		switch {
		case sub == "":
			return head, true
		case sub == "exec" || sub == "dlx" || (head == "pnpm" && sub == "x"):
			return firstBin(rest[idx+1:]), true
		case sub == "run":
			if n, _ := firstNonOption(rest[idx+1:]); n != "" {
				return head + " run " + n, true
			}
			return head + " run", true
		case pnpmYarnBuiltin[sub]:
			return head + " " + sub, true
		}
		return normArg(baseName(sub)), true // a bare binary
	}
	return "", false
}

// Signature is the command signature of a segment (v0.4 D62): the first token's
// base name, extended through known launchers to the next non-option token. The
// JavaScript launchers are normalised to the binary they run. Segments that are
// cd, export or echo have an empty signature.
//
//	./gradlew test        -> gradlew
//	npx eslint src        -> eslint
//	pnpm vitest run       -> vitest
//	python -m pytest      -> python -m pytest
//	make lint             -> make lint
//	uv run pytest -k x    -> uv run pytest
//	npm run lint          -> npm run lint
func Signature(seg Segment) string {
	if len(seg.Words) == 0 {
		return ""
	}
	head := baseName(seg.Words[0])
	if skipSegments[head] {
		return ""
	}
	rest := seg.Words[1:]
	if sig, ok := jsSignature(head, rest); ok {
		return sig
	}
	sig := []string{head}
	switch head {
	case "uv", "poetry", "pipenv", "bundle", "go":
		if len(rest) > 0 {
			verb := map[string]string{"uv": "run", "poetry": "run", "pipenv": "run", "bundle": "exec", "go": "run"}[head]
			if rest[0] == verb {
				sig = append(sig, verb)
				if next, _ := firstNonOption(rest[1:]); next != "" {
					sig = append(sig, normArg(next))
				}
			}
		}
	case "python", "python3":
		if len(rest) > 1 && rest[0] == "-m" {
			sig = append(sig, "-m", rest[1])
		} else if next, _ := firstNonOption(rest); next != "" {
			sig = append(sig, normArg(next))
		}
	default:
		if n, ok := launchers[head]; ok && n == 1 {
			if next, _ := firstNonOption(rest); next != "" {
				sig = append(sig, normArg(next))
			}
		}
	}
	return strings.Join(sig, " ")
}

// RunSignature is the signature of a declared run: command: the signature of
// its first segment that is not cd, export or echo.
func RunSignature(run string) string {
	segs, _ := Split(run)
	for _, s := range segs {
		if sig := Signature(s); sig != "" {
			return sig
		}
	}
	return ""
}
