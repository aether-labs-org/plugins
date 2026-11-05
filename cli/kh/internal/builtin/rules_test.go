package builtin

import (
	"strings"
	"testing"

	"github.com/aether-labs-org/plugins/cli/kh/internal/result"
)

func TestFileSize(t *testing.T) {
	d := newRepo(t)
	write(t, d, "src/a.ts", lines(7))
	write(t, d, "src/small.ts", lines(3))
	write(t, d, "src/my file ação.ts", lines(9))
	write(t, d, "src/big.test.ts", lines(12))
	write(t, d, "src/blob.bin", "x\x00\n"+lines(20))
	commit(t, d)
	ctx := ctxAll(t, d)
	out := run(t, "file-size", ctx, map[string]any{"limit": 5, "include": []any{"src/"}, "exclude": []any{"*.test.*"}})
	if out.Status != result.Fail || out.Summary != "2 of 3 files over 5 lines" {
		t.Fatalf("status=%s summary=%q", out.Status, out.Summary)
	}
	if out.Counts["src/a.ts"] != 7 || out.Counts["src/my file ação.ts"] != 9 || len(out.Counts) != 2 {
		t.Errorf("counts = %v", out.Counts)
	}
	if len(out.Findings) != 2 || out.Findings[0].Message != "7 lines (limit 5)" {
		t.Errorf("findings = %v", out.Findings)
	}
	if !strings.Contains(out.Guidance, "within 5 lines") {
		t.Errorf("guidance = %q", out.Guidance)
	}
	// scope restricts the check
	ctx.Files = []string{"src/small.ts"}
	if out := run(t, "file-size", ctx, map[string]any{"limit": 5}); out.Status != result.Pass {
		t.Errorf("scoped: %s", out.Status)
	}
	// nothing in scope is a skip, never a silent pass
	ctx.Files = nil
	if out := run(t, "file-size", ctx, nil); out.Status != result.Skip || out.Summary != "no changed files in scope" {
		t.Errorf("empty scope: %s %q", out.Status, out.Summary)
	}
	// the default limit is 300
	ctx = ctxAll(t, d)
	if out := run(t, "file-size", ctx, nil); out.Status != result.Pass {
		t.Errorf("default limit: %s", out.Status)
	}
}

func TestFileSizeIncludeNoMatchSkips(t *testing.T) {
	d := newRepo(t)
	write(t, d, "src/a.ts", lines(7))
	commit(t, d)
	out := run(t, "file-size", ctxAll(t, d), map[string]any{"limit": 5, "include": []any{"lib"}})
	if out.Status != result.Skip {
		t.Errorf("status = %s", out.Status)
	}
}

func TestFolderLayout(t *testing.T) {
	d := newRepo(t)
	write(t, d, "src/app/x.ts", "1\n")
	write(t, d, "src/domain/d.ts", "1\n")
	write(t, d, "src/misc/y.ts", "1\n")
	write(t, d, "src/other/z.ts", "1\n")
	commit(t, d)
	with := map[string]any{"include": []any{"src"}, "allowed": []any{"src/app/*", "src/domain/*"}}
	out := run(t, "folder-layout", ctxAll(t, d), with)
	if out.Status != result.Fail || len(out.Findings) != 2 || out.Findings[0].File != "src/misc/y.ts" || out.Counts["src/other/z.ts"] != 1 {
		t.Fatalf("status=%s findings=%v counts=%v", out.Status, out.Findings, out.Counts)
	}
	ctx := ctxAll(t, d)
	ctx.Files = []string{"src/app/x.ts"}
	if out := run(t, "folder-layout", ctx, with); out.Status != result.Pass {
		t.Errorf("scoped: %s", out.Status)
	}
	if _, problems := Default()["folder-layout"].Decode(map[string]any{"include": []any{"src"}}); len(problems) == 0 {
		t.Error("allowed is required")
	}
}

func TestShellPattern(t *testing.T) {
	cases := []struct {
		pat, path string
		want      bool
	}{
		{"src/app/*", "src/app/x.ts", true},
		{"src/app/*", "src/app/deep/x.ts", true}, // * crosses /
		{"src/app/*", "src/apple/x.ts", false},
		{"*.ts", "a/b.ts", true},
		{"src/?.ts", "src/a.ts", true},
		{"src/[ab].ts", "src/c.ts", false},
		{"src/[!ab].ts", "src/c.ts", true},
		{"a.b", "axb", false},
	}
	for _, c := range cases {
		if got := shellPattern(c.pat).MatchString(c.path); got != c.want {
			t.Errorf("%q vs %q = %v", c.pat, c.path, got)
		}
	}
}

func TestCodeLanguage(t *testing.T) {
	d := newRepo(t)
	write(t, d, "src/a.ts", "const nomeUsuario = 1; // calcula o valor\nconst name = \"Usuário inválido\";\n")
	write(t, d, "src/b.ts", "function açãoX() {}\n")
	write(t, d, "src/c.ts", "plain English only\n")
	commit(t, d)
	out := run(t, "code-language", ctxAll(t, d), map[string]any{"include": []any{"src"}})
	if out.Status != result.Fail || out.Counts["src/a.ts"] != 4 {
		t.Fatalf("status=%s counts=%v", out.Status, out.Counts)
	}
	if out.Counts["src/b.ts"] < 1 {
		t.Errorf("non-ASCII identifier not flagged: %v", out.Counts)
	}
	if _, ok := out.Counts["src/c.ts"]; ok {
		t.Errorf("English file flagged: %v", out.Counts)
	}
	if out.Summary != "2 of 3 files with non-English words" {
		t.Errorf("summary = %q", out.Summary)
	}
}

func TestCodeLanguageStoplistFromRepo(t *testing.T) {
	d := newRepo(t)
	write(t, d, "words.txt", "# custom\nfoo\n")
	write(t, d, "src/a.ts", "const foo = 1\n")
	commit(t, d)
	out := run(t, "code-language", ctxAll(t, d), map[string]any{"include": []any{"src"}, "stoplist": "words.txt"})
	if out.Counts["src/a.ts"] != 1 {
		t.Errorf("counts = %v", out.Counts)
	}
	out = run(t, "code-language", ctxAll(t, d), map[string]any{"stoplist": "missing.txt"})
	if out.Status != result.Skip || !strings.Contains(out.Summary, "not found") {
		t.Errorf("%s %q", out.Status, out.Summary)
	}
}

func TestStoplistShape(t *testing.T) {
	b, _ := stoplists.ReadFile("stoplists/pt.txt")
	n := 0
	for _, l := range strings.Split(string(b), "\n") {
		if l == "" || strings.HasPrefix(l, "#") {
			continue
		}
		n++
		if strings.ToLower(l) != l {
			t.Errorf("%q is not lowercase", l)
		}
		switch l {
		case "data", "total", "item", "status", "local", "real", "final", "base":
			t.Errorf("%q is also English", l)
		}
	}
	if n < 100 {
		t.Errorf("only %d words", n)
	}
}

func TestPattern(t *testing.T) {
	d := newRepo(t)
	write(t, d, "src/a.ts", "console.log(1);\nok();\nconsole.debug(2);\n")
	write(t, d, "src/clean.ts", "ok();\n")
	write(t, d, "src/my file: ação.ts", "console.log(a)\nconsole.log(b)\n")
	write(t, d, "src/blob.bin", "console.log(1)\x00\x01\n")
	commit(t, d)
	with := map[string]any{"pattern": `console\.(log|debug)\(`, "include": []any{"src"}, "message": "Direct console output.", "fix": "Use the logger."}
	out := run(t, "pattern", ctxAll(t, d), with)
	if out.Status != result.Fail || out.Counts["src/a.ts"] != 2 || out.Counts["src/my file: ação.ts"] != 2 || len(out.Counts) != 2 {
		t.Fatalf("status=%s counts=%v", out.Status, out.Counts)
	}
	if out.Summary != "2 of 3 files with matches" || !strings.HasPrefix(out.Guidance, "Direct console output. Use the logger. Never add a suppression") {
		t.Errorf("summary=%q guidance=%q", out.Summary, out.Guidance)
	}
	if out.Findings[0].Line != 1 {
		t.Errorf("first match line = %d", out.Findings[0].Line)
	}
	ctx := ctxAll(t, d)
	ctx.Files = []string{"src/clean.ts"}
	if out := run(t, "pattern", ctx, with); out.Status != result.Pass {
		t.Errorf("scoped: %s", out.Status)
	}
}

func TestPatternDecode(t *testing.T) {
	b := Default()["pattern"]
	if _, p := b.Decode(nil); len(p) == 0 {
		t.Error("an empty pattern must be a problem, never a silent pass")
	}
	if _, p := b.Decode(map[string]any{"pattern": "foo("}); len(p) == 0 || !strings.Contains(p[0], "not a valid regular expression") {
		t.Errorf("invalid regexp: %v", p)
	}
	if _, p := b.Decode(map[string]any{"pattern": "x", "engine": "perl"}); len(p) != 1 || p[0] != `unknown key "engine"` {
		t.Errorf("engine is gone: %v", p)
	}
}

func TestTestPresence(t *testing.T) {
	d := newRepo(t)
	write(t, d, "src/main/java/a/Foo.java", "c\n")
	write(t, d, "src/test/java/a/FooTest.java", "c\n")
	write(t, d, "src/main/java/a/Bar.java", "c\n")
	commit(t, d)
	with := map[string]any{"include": []any{"src/main"}, "mappings": []any{`^src/main/java/(.*)\.java$|src/test/java/\1Test.java`}}
	ctx := ctxAll(t, d)
	ctx.Files = []string{"src/main/java/a/Foo.java"}
	if out := run(t, "test-presence", ctx, with); out.Status != result.Pass {
		t.Errorf("Foo: %s", out.Status)
	}
	ctx.Files = []string{"src/main/java/a/Bar.java"}
	out := run(t, "test-presence", ctx, with)
	if out.Status != result.Fail || out.Findings[0].File != "src/main/java/a/Bar.java" || !strings.Contains(out.Findings[0].Message, "src/test/java/a/BarTest.java") {
		t.Fatalf("%s %v", out.Status, out.Findings)
	}
	out = run(t, "test-presence", ctxAll(t, d), with)
	if out.Counts["src/main/java/a/Bar.java"] != 1 || len(out.Counts) != 1 {
		t.Errorf("counts = %v", out.Counts)
	}
	// a file no mapping applies to is not covered by the rule
	write(t, d, "src/main/resources/x.txt", "c\n")
	if out := run(t, "test-presence", ctxAll(t, d), with); len(out.Counts) != 1 {
		t.Errorf("unmapped file counted: %v", out.Counts)
	}
	if _, p := Default()["test-presence"].Decode(map[string]any{"mappings": []any{"no-separator"}}); len(p) == 0 {
		t.Error("a mapping without | is a problem")
	}
}

const layersJava = `[{"name":"domain","path":"src/main/java/com/acme/domain","import":"com.acme.domain"},
{"name":"application","path":"src/main/java/com/acme/application","import":"com.acme.application","allowed":["domain"]},
{"name":"adapter","path":"src/main/java/com/acme/adapter","import":"com.acme.adapter","allowed":["application","domain"]}]`

func TestArchitectureGrepJava(t *testing.T) {
	d := newRepo(t)
	j := "src/main/java/com/acme/"
	write(t, d, j+"domain/Foo.java", "package com.acme.domain;\nimport com.acme.adapter.web.X;\nimport org.springframework.stereotype.Service;\nimport java.util.List;\n")
	write(t, d, j+"application/Svc.java", "package com.acme.application;\nimport com.acme.domain.Foo;\n")
	write(t, d, j+"adapter/web/X.java", "package com.acme.adapter.web;\npublic class X {}\n")
	commit(t, d)
	with := map[string]any{"lang": "java",
		"layers":    yamlList(t, layersJava),
		"forbidden": []any{map[string]any{"layer": "domain", "prefix": "org.springframework"}}}
	out := run(t, "architecture-grep", ctxAll(t, d), with)
	if out.Status != result.Fail || out.Counts[j+"domain/Foo.java"] != 2 || len(out.Counts) != 1 {
		t.Fatalf("status=%s counts=%v findings=%v", out.Status, out.Counts, out.Findings)
	}
	ctx := ctxAll(t, d)
	ctx.Files = []string{j + "application/Svc.java"}
	if out := run(t, "architecture-grep", ctx, with); out.Status != result.Pass {
		t.Errorf("scoped: %s", out.Status)
	}
}

func TestArchitectureGrepPython(t *testing.T) {
	d := newRepo(t)
	write(t, d, "acme/domain/m.py", "from acme.infra import db\nimport os\n")
	write(t, d, "acme/infra/db.py", "from acme.domain import m\n")
	commit(t, d)
	with := map[string]any{"lang": "python", "layers": []any{
		map[string]any{"name": "domain", "path": "acme/domain", "import": "acme.domain"},
		map[string]any{"name": "infra", "path": "acme/infra", "import": "acme.infra", "allowed": []any{"domain"}},
	}}
	out := run(t, "architecture-grep", ctxAll(t, d), with)
	if out.Counts["acme/domain/m.py"] != 1 || len(out.Counts) != 1 {
		t.Fatalf("counts = %v", out.Counts)
	}
	with["lang"] = "ts"
	if _, p := Default()["architecture-grep"].Decode(with); len(p) == 0 || !strings.Contains(p[0], "lang must be") {
		t.Errorf("ts must point at a native tool: %v", p)
	}
}

func TestUnder(t *testing.T) {
	if !under("com.acme.domain.Foo", "com.acme.domain") || under("com.acme.domainx.Foo", "com.acme.domain") || !under("com.acme.domain", "com.acme.domain") {
		t.Error("under")
	}
}

func TestTestPresenceMappingDollarSyntax(t *testing.T) {
	d := newRepo(t)
	write(t, d, "src/a/b.ts", "x\n")
	write(t, d, "src/a/c.ts", "x\n")
	write(t, d, "test/a/b.test.ts", "x\n")
	commit(t, d)
	with := map[string]any{"include": []any{"src"}, "mappings": []any{`^src/(.*)\.ts$|test/$1.test.ts`}}
	out := run(t, "test-presence", ctxAll(t, d), with)
	if len(out.Counts) != 1 || out.Counts["src/a/c.ts"] != 1 || !strings.Contains(out.Findings[0].Message, "test/a/c.test.ts") {
		t.Fatalf("%v %v", out.Counts, out.Findings)
	}
	// the v0.3 \1 spelling still works
	with["mappings"] = []any{`^src/(.*)\.ts$|test/\1.test.ts`}
	if out := run(t, "test-presence", ctxAll(t, d), with); out.Counts["src/a/c.ts"] != 1 || len(out.Counts) != 1 {
		t.Fatalf("\\1: %v", out.Counts)
	}
}
