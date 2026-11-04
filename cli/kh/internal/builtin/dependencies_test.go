package builtin

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/aether-labs-org/plugins/cli/kh/internal/result"
)

const pkgJSON = `{
  "name": "app",
  "version": "1.0.0",
  "scripts": { "dependencies": "echo not a dependency" },
  "dependencies": {
    "express": "^4.18.0",
    "left-pad": "1.3.0"
  },
  "devDependencies": { "jest": "^29.0.0" }
}
`

const pyproject = `[project]
name = "app"
dependencies = [
  "requests>=2.31",  # http client
  "pydantic[email]>=2",
]

[project.optional-dependencies]
web = ["flask>=3"]

[dependency-groups]
dev = [
  "pytest>=8",
]

[tool.poetry.dependencies]
python = "^3.11"
httpx = "^0.27"

[tool.poetry.group.test.dependencies]
coverage = { version = "^7", extras = ["toml"] }
`

const pomXML = `<project>
  <parent><groupId>org.parent</groupId><artifactId>parent</artifactId></parent>
  <dependencyManagement>
    <dependencies>
      <dependency><groupId>org.managed</groupId><artifactId>bom</artifactId><version>1</version></dependency>
    </dependencies>
  </dependencyManagement>
  <dependencies>
    <dependency>
      <groupId>org.springframework</groupId>
      <artifactId>spring-core</artifactId>
      <version>6.1.0</version>
      <exclusions><exclusion><groupId>commons-logging</groupId><artifactId>commons-logging</artifactId></exclusion></exclusions>
    </dependency>
    <!-- <dependency><groupId>old</groupId><artifactId>commented</artifactId></dependency> -->
  </dependencies>
  <build><plugins><plugin>
    <artifactId>maven-x</artifactId>
    <dependencies><dependency><groupId>org.plugin</groupId><artifactId>dep</artifactId><version>1</version></dependency></dependencies>
  </plugin></plugins></build>
</project>
`

const gradleKts = `plugins { id("java") }
dependencies {
    implementation("org.slf4j:slf4j-api:2.0.9")
    testImplementation("org.junit.jupiter:junit-jupiter:5.10.0")
    implementation(project(":core"))
    implementation(libs.jackson.databind)
}
`

const gradleGroovy = `dependencies {
    api 'com.google.guava:guava:33.0.0-jre'
    implementation group: 'org.apache.commons', name: 'commons-lang3', version: '3.14.0'
}
`

func TestDepsOfEachManifest(t *testing.T) {
	cases := []struct {
		kind, text string
		want       []string
	}{
		{"pkg", pkgJSON, []string{"express", "jest", "left-pad"}},
		{"toml", pyproject, []string{"coverage", "flask", "httpx", "pydantic", "pytest", "requests"}},
		{"pom", pomXML, []string{"org.springframework:spring-core"}},
		{"gradle", gradleKts, []string{"libs.jackson.databind", "org.junit.jupiter:junit-jupiter", "org.slf4j:slf4j-api"}},
		{"gradle", gradleGroovy, []string{"com.google.guava:guava", "org.apache.commons:commons-lang3"}},
	}
	for _, c := range cases {
		if got := depsOf(c.kind, []byte(c.text)); !reflect.DeepEqual(got, c.want) {
			t.Errorf("%s: got %v want %v", c.kind, got, c.want)
		}
	}
	// CRLF parses like LF
	if got := depsOf("toml", []byte(strings.ReplaceAll(pyproject, "\n", "\r\n"))); len(got) != 6 {
		t.Errorf("CRLF toml: %v", got)
	}
}

// mkd: a committed harness with one manifest of each kind.
func mkd(t *testing.T) string {
	t.Helper()
	d := newRepo(t)
	write(t, d, ".agents/keel.yml", "version: 1\n")
	write(t, d, "docs/adr/.keep", "")
	write(t, d, "package.json", pkgJSON)
	write(t, d, "pyproject.toml", pyproject)
	write(t, d, "pom.xml", pomXML)
	write(t, d, "svc/build.gradle.kts", gradleKts)
	write(t, d, "svc/build.gradle", gradleGroovy)
	commit(t, d)
	return d
}

func depRun(t *testing.T, d string, with map[string]any) Outcome {
	t.Helper()
	return run(t, "dependencies", ctxAll(t, d), with)
}

func sub(t *testing.T, d, file, old, new string) {
	t.Helper()
	p := filepath.Join(d, file)
	b, err := os.ReadFile(p)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(b), old) {
		t.Fatalf("%s lacks %q", file, old)
	}
	os.WriteFile(p, []byte(strings.Replace(string(b), old, new, 1)), 0o644)
}

func TestDependenciesNothingChanged(t *testing.T) {
	d := mkd(t)
	out := depRun(t, d, nil)
	if out.Status != result.Pass || !strings.Contains(out.Summary, "5 manifest(s) checked") {
		t.Fatalf("%s %q", out.Status, out.Summary)
	}
	if ClassOf(Default()["dependencies"]) != "security" {
		t.Error("dependencies is a security builtin")
	}
	ctx := ctxAll(t, d)
	ctx.Measure = true
	m := run(t, "dependencies", ctx, nil)
	want := map[string]int{"package.json": 3, "pyproject.toml": 6, "pom.xml": 1, "svc/build.gradle.kts": 3, "svc/build.gradle": 2}
	if !reflect.DeepEqual(m.Counts, want) {
		t.Errorf("measure = %v", m.Counts)
	}
}

func TestDependenciesVersionBumpAndRemoval(t *testing.T) {
	d := mkd(t)
	sub(t, d, "package.json", `"express": "^4.18.0"`, `"express": "^5.0.0"`)
	sub(t, d, "package.json", `"left-pad": "1.3.0"`, `"left-pad": "1.3.1"`)
	if out := depRun(t, d, nil); out.Status != result.Pass {
		t.Fatalf("bump: %s %q", out.Status, out.Summary)
	}
	sub(t, d, "package.json", `    "left-pad": "1.3.1"`, ``)
	sub(t, d, "package.json", `"express": "^5.0.0",`, `"express": "^5.0.0"`)
	if out := depRun(t, d, nil); out.Status != result.Pass {
		t.Fatalf("removal: %s %q", out.Status, out.Summary)
	}
}

func TestDependenciesNewNeedsAnADR(t *testing.T) {
	d := mkd(t)
	sub(t, d, "package.json", `"jest": "^29.0.0"`, `"jest": "^29.0.0", "lodash": "4.17.21"`)
	out := depRun(t, d, nil)
	if out.Status != result.Fail || len(out.Findings) != 1 || out.Findings[0].File != "package.json" || out.Findings[0].Message != "lodash" {
		t.Fatalf("%s %v", out.Status, out.Findings)
	}
	if !strings.Contains(out.Guidance, "Never add the dependency to an allow-list") {
		t.Errorf("guidance = %q", out.Guidance)
	}
	write(t, d, "docs/adr/0001-lodash.md", "# ADR 0001\nWe add lodash to the dependencies of other-package.json.\n")
	if out := depRun(t, d, nil); out.Status != result.Fail {
		t.Error("an ADR that does not name the manifest unlocked it")
	}
	write(t, d, "docs/adr/0002-lodash.md", "# ADR 0002\nWe add lodash in `package.json` for deep clone.\n")
	out = depRun(t, d, nil)
	if out.Status != result.Pass || !strings.Contains(out.Summary, "1 new direct dependency") {
		t.Fatalf("%s %q", out.Status, out.Summary)
	}
}

func TestDependenciesADRAlreadyAtTheBaseDoesNotUnlock(t *testing.T) {
	d := mkd(t)
	write(t, d, "docs/adr/0003.md", "ADR naming package.json.\n")
	commit(t, d)
	sub(t, d, "package.json", `"jest": "^29.0.0"`, `"jest": "^29.0.0", "lodash": "4.17.21"`)
	if out := depRun(t, d, nil); out.Status != result.Fail {
		t.Errorf("%s", out.Status)
	}
}

func TestDependenciesBaseHonoured(t *testing.T) {
	d := mkd(t)
	base := git(t, d, "rev-parse", "HEAD")
	sub(t, d, "package.json", `"jest": "^29.0.0"`, `"jest": "^29.0.0", "lodash": "4.17.21"`)
	write(t, d, "docs/adr/0003.md", "ADR naming package.json.\n")
	commit(t, d)
	t.Setenv("KEEL_GUARD_BASE", base)
	ctx := ctxAll(t, d)
	if out := run(t, "dependencies", ctx, nil); out.Status != result.Pass {
		t.Errorf("ADR committed since the base: %s %q", out.Status, out.Summary)
	}
	t.Setenv("KEEL_GUARD_BASE", "nonexistent-ref")
	ctx = ctxAll(t, d)
	if out := run(t, "dependencies", ctx, nil); out.Status != result.Fail || !strings.Contains(out.Summary, "is not a commit") {
		t.Errorf("bad base: %s %q", out.Status, out.Summary)
	}
}

func TestDependenciesAlreadyPresentIsNotNew(t *testing.T) {
	d := mkd(t)
	sub(t, d, "package.json", `"jest": "^29.0.0"`, `"jest": "^29.0.0", "left-pad": "1.3.0"`)
	if out := depRun(t, d, nil); out.Status != result.Pass {
		t.Errorf("%s", out.Status)
	}
}

func TestDependenciesPeerAndScripts(t *testing.T) {
	d := mkd(t)
	sub(t, d, "package.json", `"devDependencies": { "jest": "^29.0.0" }`, `"devDependencies": { "jest": "^29.0.0" }, "peerDependencies": { "react": "18" }`)
	if out := depRun(t, d, nil); out.Status != result.Fail || out.Findings[0].Message != "react" {
		t.Fatalf("peer: %v", out.Findings)
	}
	d = mkd(t)
	sub(t, d, "package.json", `"scripts": { "dependencies": "echo not a dependency" }`, `"scripts": { "dependencies": "echo", "x": "y" }`)
	if out := depRun(t, d, nil); out.Status != result.Pass {
		t.Errorf("a script called dependencies is not a block: %v", out.Findings)
	}
}

func TestDependenciesPyproject(t *testing.T) {
	cases := []struct{ old, new, added string }{
		{`  "requests>=2.31",  # http client`, "  \"requests>=2.32\",  # bumped\n  \"rich>=13\",", "rich"},
		{`web = ["flask>=3"]`, `web = ["flask>=3", "jinja2"]`, "jinja2"},
		{`  "pytest>=8",`, "  \"pytest>=8\",\n  \"ruff\",", "ruff"},
		{`httpx = "^0.27"`, "httpx = \"^0.28\"\nanyio = \"^4\"", "anyio"},
		{`coverage = { version = "^7", extras = ["toml"] }`, "coverage = { version = \"^7\" }\nfreezegun = \"*\"", "freezegun"},
	}
	for _, c := range cases {
		d := mkd(t)
		sub(t, d, "pyproject.toml", c.old, c.new)
		out := depRun(t, d, nil)
		if out.Status != result.Fail || len(out.Findings) != 1 || out.Findings[0].Message != c.added {
			t.Errorf("%s: %s %v", c.added, out.Status, out.Findings)
		}
	}
	d := mkd(t)
	sub(t, d, "pyproject.toml", `"pydantic[email]>=2"`, `"pydantic>=2.5"`)
	if out := depRun(t, d, nil); out.Status != result.Pass {
		t.Errorf("extras do not change the name: %v", out.Findings)
	}
}

func TestDependenciesPom(t *testing.T) {
	d := mkd(t)
	sub(t, d, "pom.xml", `<version>6.1.0</version>`, `<version>6.2.0</version>`)
	if out := depRun(t, d, nil); out.Status != result.Pass {
		t.Errorf("bump: %s", out.Status)
	}
	sub(t, d, "pom.xml", `<!-- <dependency><groupId>old</groupId><artifactId>commented</artifactId></dependency> -->`, `<dependency><groupId>org.jsoup</groupId><artifactId>jsoup</artifactId></dependency>`)
	if out := depRun(t, d, nil); out.Status != result.Fail || out.Findings[0].Message != "org.jsoup:jsoup" {
		t.Errorf("new: %v", out.Findings)
	}
	d = mkd(t)
	sub(t, d, "pom.xml", `<dependency><groupId>org.managed</groupId><artifactId>bom</artifactId><version>1</version></dependency>`, `<dependency><groupId>org.m2</groupId><artifactId>b2</artifactId></dependency>`)
	sub(t, d, "pom.xml", `<groupId>commons-logging</groupId>`, `<groupId>x</groupId>`)
	sub(t, d, "pom.xml", `<groupId>org.plugin</groupId>`, `<groupId>org.plugin2</groupId>`)
	if out := depRun(t, d, nil); out.Status != result.Pass {
		t.Errorf("management, exclusions and plugin dependencies are not direct: %v", out.Findings)
	}
}

func TestDependenciesGradle(t *testing.T) {
	d := mkd(t)
	sub(t, d, "svc/build.gradle.kts", `    implementation("org.slf4j:slf4j-api:2.0.9")`, "    implementation(\"org.slf4j:slf4j-api:2.0.10\")\n    runtimeOnly(\"com.h2database:h2:2.2.224\")")
	out := depRun(t, d, nil)
	if out.Status != result.Fail || len(out.Findings) != 1 || out.Findings[0].Message != "com.h2database:h2" {
		t.Fatalf("kts: %v", out.Findings)
	}
	d = mkd(t)
	sub(t, d, "svc/build.gradle.kts", `    implementation(project(":core"))`, "    implementation(project(\":core\"))\n    implementation(project(\":other\"))\n    implementation(libs.kotlin.stdlib)")
	if out := depRun(t, d, nil); len(out.Findings) != 1 || out.Findings[0].Message != "libs.kotlin.stdlib" {
		t.Fatalf("alias: %v", out.Findings)
	}
	d = mkd(t)
	sub(t, d, "svc/build.gradle", `    api 'com.google.guava:guava:33.0.0-jre'`, "    api 'com.google.guava:guava:33.0.0-jre'\n    implementation group: 'org.yaml', name: 'snakeyaml', version: '2.2'")
	if out := depRun(t, d, nil); len(out.Findings) != 1 || out.Findings[0].Message != "org.yaml:snakeyaml" {
		t.Fatalf("groovy map: %v", out.Findings)
	}
	write(t, d, "docs/adr/0001.md", "ADR for svc/build.gradle only.\n")
	if out := depRun(t, d, nil); out.Status != result.Pass {
		t.Errorf("an ADR naming the nested path must unlock it: %v", out.Findings)
	}
	write(t, d, "docs/adr/0001.md", "ADR for svc/build.gradle.kts only (see also build.gradle).\n")
	if out := depRun(t, d, nil); out.Status != result.Fail {
		t.Errorf("naming a different or shorter path unlocked it")
	}
}

func TestDependenciesNewManifestsAndStates(t *testing.T) {
	d := mkd(t)
	write(t, d, "web/package.json", `{ "dependencies": { "react": "18" } }`)
	if out := depRun(t, d, nil); out.Status != result.Fail || out.Findings[0].File != "web/package.json" {
		t.Fatalf("untracked manifest: %v", out.Findings)
	}
	write(t, d, "web/package.json", `{ "dependencies": {} }`)
	if out := depRun(t, d, nil); out.Status != result.Pass {
		t.Errorf("empty manifest: %v", out.Findings)
	}
	// node_modules is ignored
	write(t, d, "node_modules/x/package.json", `{ "dependencies": { "evil": "1" } }`)
	if out := depRun(t, d, nil); out.Status != result.Pass {
		t.Errorf("node_modules counted: %v", out.Findings)
	}
	// include / exclude
	write(t, d, "web/package.json", `{ "dependencies": { "react": "18" } }`)
	if out := depRun(t, d, map[string]any{"include": []any{"svc"}}); out.Status != result.Pass {
		t.Errorf("include: %v", out.Findings)
	}
	if out := depRun(t, d, map[string]any{"exclude": []any{"web"}}); out.Status != result.Pass {
		t.Errorf("exclude: %v", out.Findings)
	}
}

func TestDependenciesHarnessInstalledInThisChange(t *testing.T) {
	d := newRepo(t)
	write(t, d, "package.json", `{ "dependencies": {} }`)
	commit(t, d)
	write(t, d, "package.json", `{ "dependencies": { "react": "18" } }`)
	write(t, d, ".agents/keel.yml", "version: 1\n")
	out := depRun(t, d, nil)
	if out.Status != result.Pass || !strings.Contains(out.Summary, "installed in this change") {
		t.Fatalf("%s %q", out.Status, out.Summary)
	}
}

func TestDependenciesNoCommitsYet(t *testing.T) {
	d := newRepo(t)
	write(t, d, "package.json", `{ "dependencies": { "react": "18" } }`)
	out := depRun(t, d, nil)
	if out.Status != result.Pass || !strings.Contains(out.Summary, "No commits yet") {
		t.Fatalf("%s %q", out.Status, out.Summary)
	}
}
