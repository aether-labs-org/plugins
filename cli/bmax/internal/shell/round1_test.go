package shell

import (
	"reflect"
	"sort"
	"testing"
)

func TestHomeExpansion(t *testing.T) {
	t.Setenv("HOME", "/home/u")
	cases := []struct {
		cmd  string
		want []string
	}{
		{"echo x > ~/.claude/settings.json", []string{"/home/u/.claude/settings.json"}},
		{"echo x > $HOME/.claude/settings.json", []string{"/home/u/.claude/settings.json"}},
		{`echo x > "${HOME}/.claude/settings.json"`, []string{"/home/u/.claude/settings.json"}},
		{`echo x > "$HOME/.claude/settings.json"`, []string{"/home/u/.claude/settings.json"}},
		{"echo x > ${HOME}/.claude/settings.json", []string{"/home/u/.claude/settings.json"}},
		{"tee ~/.copilot/settings.json", []string{"/home/u/.copilot/settings.json"}},
		{"cp /tmp/x ~", []string{"/home/u", "/home/u/x"}},
		// not expanded: single quotes, a quoted tilde, another user, not leading, a longer variable name
		{"echo x > '$HOME/.claude/settings.json'", []string{"$HOME/.claude/settings.json"}},
		{`echo x > '~/.claude/settings.json'`, []string{"~/.claude/settings.json"}},
		{`echo x > "~/.claude/settings.json"`, []string{"~/.claude/settings.json"}},
		{"echo x > ~root/.bashrc", []string{"~root/.bashrc"}},
		{"echo x > a~/b", []string{"a~/b"}},
		{"echo x > /tmp/$HOME/y", []string{"/tmp/$HOME/y"}},
		{"echo x > $HOMEWARD/y", []string{"$HOMEWARD/y"}},
	}
	for _, c := range cases {
		segs, _ := Split(c.cmd)
		var got []string
		for _, s := range segs {
			got = append(got, WriteTargets(s)...)
		}
		sort.Strings(got)
		want := append([]string(nil), c.want...)
		sort.Strings(want)
		if !reflect.DeepEqual(got, want) {
			t.Errorf("%q\n  got  %q\n  want %q", c.cmd, got, want)
		}
	}
}

func TestForbiddenGitAbbreviationsAndEnv(t *testing.T) {
	deny := []string{
		"git commit --no-verif -m x",
		"git push --no-veri",
		"git commit --no-ver -m x",
		"git commit --no-v -m x",
		"git --config-env=core.hooksPath=MYVAR commit -m x",
		"git --config-env=CORE.HOOKSPATH=MYVAR commit -m x",
		"git --config-env core.hooksPath=MYVAR commit -m x",
		"GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null git commit -m x",
		"GIT_CONFIG_KEY_3=Core.HooksPath git commit -m x",
		"env GIT_CONFIG_KEY_0=core.hooksPath git commit -m x",
		"export GIT_CONFIG_KEY_0=core.hooksPath",
		"GIT_CONFIG_PARAMETERS=\"'core.hookspath=/dev/null'\" git commit -m x",
		"export GIT_CONFIG_PARAMETERS=\"'core.hooksPath=/dev/null'\"",
		"git config core.hooksPath /dev/null",
		"git config --unset core.hooksPath",
		"git config --replace-all core.hooksPath /dev/null",
		"git config --add core.hooksPath /dev/null",
		"git config --global core.hooksPath /dev/null",
		"git config set core.hooksPath /dev/null",
	}
	for _, c := range deny {
		if r, ok := forbidden(c); !ok || r == "" {
			t.Errorf("%q should be forbidden", c)
		}
	}
	allow := []string{
		"git config core.hooksPath",
		"git config --get core.hooksPath",
		"git config --get-all core.hooksPath",
		"git config --global --get core.hooksPath",
		"git commit --no-edit -m x",
		"git commit --no -m x",
		"git commit --no-verbose",
		"GIT_CONFIG_KEY_0=user.name git commit -m x",
		"GIT_CONFIG_PARAMETERS=\"'user.name=x'\" git commit -m x",
		"git --config-env=user.name=NAME commit -m x",
	}
	for _, c := range allow {
		if r, ok := forbidden(c); ok {
			t.Errorf("%q should be allowed, got %q", c, r)
		}
	}
}

func TestLauncherPrefixes(t *testing.T) {
	cases := []struct {
		cmd  string
		want []string
	}{
		{"sudo tee AGENTS.md", []string{"AGENTS.md"}},
		{"sudo -u root -E tee AGENTS.md", []string{"AGENTS.md"}},
		{"sudo -g wheel cp /tmp/x .agents/bmax.yml", []string{".agents/bmax.yml", ".agents/bmax.yml/x"}},
		{`nohup sh -c "echo > AGENTS.md"`, []string{"AGENTS.md"}},
		{`timeout 5 sh -c 'echo > AGENTS.md'`, []string{"AGENTS.md"}},
		{`timeout -s KILL 10s tee AGENTS.md`, []string{"AGENTS.md"}},
		{"nice -n 5 cp /tmp/x .agents/bmax.yml", []string{".agents/bmax.yml", ".agents/bmax.yml/x"}},
		{"nice -5 touch AGENTS.md", []string{"AGENTS.md"}},
		{"command cp /tmp/x .agents/bmax.yml", []string{".agents/bmax.yml", ".agents/bmax.yml/x"}},
		{"exec tee AGENTS.md", []string{"AGENTS.md"}},
		{"stdbuf -oL tee AGENTS.md", []string{"AGENTS.md"}},
		{"ionice -c 3 tee AGENTS.md", []string{"AGENTS.md"}},
		{"time tee AGENTS.md", []string{"AGENTS.md"}},
		{"env -i FOO=1 tee AGENTS.md", []string{"AGENTS.md"}},
		{"sudo nice -n 1 nohup tee AGENTS.md", []string{"AGENTS.md"}},
		{"command -v cp", nil},
		{"sudo ls -la", nil},
		{"timeout 5 ls", nil},
	}
	for _, c := range cases {
		segs, _ := Split(c.cmd)
		var got []string
		for _, s := range segs {
			got = append(got, WriteTargets(s)...)
		}
		sort.Strings(got)
		want := append([]string(nil), c.want...)
		sort.Strings(want)
		if len(got) == 0 && len(want) == 0 {
			continue
		}
		if !reflect.DeepEqual(got, want) {
			t.Errorf("%q\n  got  %q\n  want %q", c.cmd, got, want)
		}
	}
	for _, c := range []string{"sudo git commit --no-verify -m x", "nice -n 3 git push --no-veri", "timeout 5 env BMAX_BINARY=/tmp/x sh .agents/bin/bmax gate fast"} {
		if _, ok := forbidden(c); !ok {
			t.Errorf("%q should be forbidden through its launcher", c)
		}
	}
	segs, _ := Split("sudo -u root ./gradlew test")
	if got := Signature(segs[0]); got != "gradlew" {
		t.Errorf("signature through sudo = %q", got)
	}
}

func TestRsyncAndRecursiveCopies(t *testing.T) {
	cases := []struct {
		cmd  string
		want []string
	}{
		{"rsync /tmp/x AGENTS.md", []string{"AGENTS.md", "AGENTS.md/x"}},
		{"rsync -av --exclude '*.o' /tmp/x/ .agents/", []string{".agents/", ".agents/x"}},
		{"rsync -e ssh host:/a b", []string{"b", "b/a"}},
		{"cp -r /tmp/x/. .agents/", []string{".agents", ".agents/"}},
		{"cp /tmp/x .agents", []string{".agents", ".agents/x"}},
	}
	for _, c := range cases {
		got := targets(c.cmd)
		want := append([]string(nil), c.want...)
		sort.Strings(want)
		if !reflect.DeepEqual(got, want) {
			t.Errorf("%q\n  got  %q\n  want %q", c.cmd, got, want)
		}
	}
	for cmd, want := range map[string]bool{
		"cp -r /tmp/x .agents": true, "cp -R a b": true, "cp -a a b": true, "cp --recursive a b": true, "cp -rv a b": true,
		"rsync -r a b": true, "rsync -a a b": true, "rsync -avz a b": true, "rsync a b": false, "cp a b": false, "cp -p a b": false,
		"rm -rf x": true, "mv a b": true,
	} {
		segs, _ := Split(cmd)
		if got := Destructive(segs[0]); got != want {
			t.Errorf("Destructive(%q) = %v, want %v", cmd, got, want)
		}
	}
}

func TestJSLauncherSignatures(t *testing.T) {
	cases := map[string]string{
		"npx vitest run":             "vitest",
		"npx --yes vitest run":       "vitest",
		"npm exec vitest":            "vitest",
		"npm exec -- vitest run":     "vitest",
		"pnpm exec vitest":           "vitest",
		"pnpm dlx vitest":            "vitest",
		"pnpm vitest run":            "vitest",
		"pnpm --filter web vitest":   "vitest",
		"yarn vitest":                "vitest",
		"yarn exec vitest":           "vitest",
		"yarn dlx vitest":            "vitest",
		"bunx vitest":                "vitest",
		"bun x vitest":               "vitest",
		"./node_modules/.bin/vitest": "vitest",
		"vitest run":                 "vitest",
		"npm run lint":               "npm run lint",
		"npm test":                   "npm test",
		"pnpm run lint":              "pnpm run lint",
		"pnpm test":                  "pnpm test",
		"pnpm install":               "pnpm install",
		"yarn run lint":              "yarn run lint",
		"yarn install":               "yarn install",
		"bun run lint":               "bun run lint",
	}
	for cmd, want := range cases {
		segs, _ := Split(cmd)
		if got := Signature(segs[0]); got != want {
			t.Errorf("Signature(%q) = %q, want %q", cmd, got, want)
		}
	}
	if got := RunSignature("npx vitest run --reporter=junit"); got != "vitest" {
		t.Errorf("RunSignature = %q", got)
	}
}
