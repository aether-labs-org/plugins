package builtin

import (
	"bytes"
	"encoding/json"
	"encoding/xml"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"github.com/aether-labs-org/plugins/cli/bmax/internal/result"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/scope"
)

type dependencies struct{}

type dependenciesParams struct {
	Include []string `json:"include"`
	Exclude []string `json:"exclude"`
}

func (dependencies) Name() string         { return "dependencies" }
func (dependencies) DefaultClass() string { return "security" }

func (dependencies) Decode(with map[string]any) (any, []string) {
	return decodeWith[dependenciesParams](with)
}

const depGuidance = "remove the new dependency, or add an ADR in this same change that names the manifest by path and says why the dependency is needed and why neither the standard library nor an existing dependency will do. Check that the package exists and is the one you mean: a name suggested by a model may not exist, or may be a look-alike. Never add the dependency to an allow-list, edit this check or loosen the config to make this pass."

func manifestKind(path string) string {
	switch filepath.Base(path) {
	case "package.json":
		return "pkg"
	case "pyproject.toml":
		return "toml"
	case "pom.xml":
		return "pom"
	case "build.gradle", "build.gradle.kts":
		return "gradle"
	}
	return ""
}

func uniqSorted(l []string) []string {
	seen := map[string]bool{}
	var out []string
	for _, x := range l {
		if x != "" && !seen[x] {
			seen[x] = true
			out = append(out, x)
		}
	}
	sort.Strings(out)
	return out
}

// depsOf returns the direct dependencies of one manifest, sorted and unique.
func depsOf(kind string, content []byte) []string {
	content = bytes.ReplaceAll(content, []byte("\r"), nil)
	switch kind {
	case "pkg":
		return uniqSorted(depsPackageJSON(content))
	case "toml":
		return uniqSorted(depsPyproject(string(content)))
	case "pom":
		return uniqSorted(depsPom(content))
	case "gradle":
		return uniqSorted(depsGradle(string(content)))
	}
	return nil
}

func depsPackageJSON(b []byte) []string {
	var top map[string]json.RawMessage
	if json.Unmarshal(b, &top) != nil {
		return nil
	}
	var out []string
	for _, sec := range []string{"dependencies", "devDependencies", "peerDependencies", "optionalDependencies"} {
		raw, ok := top[sec]
		if !ok {
			continue
		}
		var m map[string]json.RawMessage
		if json.Unmarshal(raw, &m) == nil {
			for k := range m {
				out = append(out, k)
			}
		}
	}
	return out
}

var (
	normNameRE  = regexp.MustCompile(`^[a-z0-9][a-z0-9._-]*`)
	poetryTable = regexp.MustCompile(`^tool\.poetry\.(group\.[^.]+\.)?(dev-)?dependencies$`)
	poetrySub   = regexp.MustCompile(`^tool\.poetry\.(group\.[^.]+\.)?(dev-)?dependencies\.[^.]+$`)
	poetryKey   = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]*$`)
)

func normPy(s string) string {
	m := normNameRE.FindString(strings.ToLower(s))
	if m == "" {
		return ""
	}
	return strings.NewReplacer(".", "-", "_", "-").Replace(m)
}

func depsPyproject(text string) []string {
	var out []string
	arr, inq := false, false
	br := 0
	var q byte
	var cur strings.Builder
	scan := func(s string) {
		for i := 0; i < len(s) && arr; i++ {
			c := s[i]
			switch {
			case inq:
				if c == q {
					inq = false
					if br == 0 {
						if nm := normPy(cur.String()); nm != "" {
							out = append(out, nm)
						}
					}
					cur.Reset()
				} else {
					cur.WriteByte(c)
				}
			case c == '"' || c == '\'':
				inq, q = true, c
				cur.Reset()
			case c == '#':
				return
			case c == '{':
				br++
			case c == '}':
				if br > 0 {
					br--
				}
			case c == ']':
				arr = false
			}
		}
	}
	table := ""
	for _, line := range strings.Split(text, "\n") {
		if arr {
			scan(line)
			continue
		}
		t := strings.TrimSpace(line)
		if t == "" || t[0] == '#' {
			continue
		}
		if t[0] == '[' {
			h := t
			if i := strings.IndexByte(h, '#'); i >= 0 {
				h = h[:i]
			}
			h = strings.TrimSpace(h)
			h = strings.TrimLeft(h, "[")
			h = strings.TrimRight(h, "]")
			table = strings.TrimSpace(h)
			if poetrySub.MatchString(table) {
				nm := table[strings.Index(table, "dependencies.")+len("dependencies."):]
				nm = normPy(strings.ReplaceAll(nm, `"`, ""))
				if nm != "" && nm != "python" {
					out = append(out, nm)
				}
			}
			continue
		}
		eq := strings.IndexByte(t, '=')
		if eq < 0 {
			continue
		}
		key, val := strings.TrimSpace(t[:eq]), t[eq+1:]
		start := (table == "project" && key == "dependencies") ||
			table == "project.optional-dependencies" || table == "dependency-groups" ||
			(table == "tool.uv" && key == "dev-dependencies")
		if start {
			if i := strings.IndexByte(val, '['); i >= 0 {
				arr, inq, br = true, false, 0
				scan(val[i+1:])
			}
			continue
		}
		if poetryTable.MatchString(table) && poetryKey.MatchString(key) {
			if nm := normPy(key); nm != "" && nm != "python" {
				out = append(out, nm)
			}
		}
	}
	return out
}

func depsPom(b []byte) []string {
	dec := xml.NewDecoder(bytes.NewReader(b))
	dec.Strict = false
	var out []string
	mgmt, plug, excl := 0, 0, 0
	indep := false
	var g, a string
	var capture *string
	var text strings.Builder
	for {
		tok, err := dec.Token()
		if err != nil {
			if err != io.EOF {
				return out
			}
			break
		}
		switch t := tok.(type) {
		case xml.StartElement:
			switch t.Name.Local {
			case "dependencyManagement":
				mgmt++
			case "plugin":
				plug++
			case "exclusion":
				excl++
			case "dependency":
				if mgmt == 0 && plug == 0 {
					indep, g, a = true, "", ""
				}
			case "groupId":
				if indep && excl == 0 {
					capture = &g
					text.Reset()
				}
			case "artifactId":
				if indep && excl == 0 {
					capture = &a
					text.Reset()
				}
			}
		case xml.CharData:
			if capture != nil {
				text.Write(t)
			}
		case xml.EndElement:
			switch t.Name.Local {
			case "dependencyManagement":
				mgmt--
			case "plugin":
				plug--
			case "exclusion":
				excl--
			case "groupId", "artifactId":
				if capture != nil {
					*capture = strings.TrimSpace(text.String())
					capture = nil
				}
			case "dependency":
				if indep && g != "" && a != "" {
					out = append(out, g+":"+a)
				}
				indep = false
			}
		}
	}
	return out
}

var (
	gradleCfg     = regexp.MustCompile(`^[ \t]*(?:api|implementation|compileOnly|runtimeOnly|annotationProcessor|kapt|ksp|compile|runtime|testCompile|testRuntime|developmentOnly|[a-z][A-Za-z]*(?:Implementation|Api|CompileOnly|RuntimeOnly|AnnotationProcessor))(?:[ \t(]|$)`)
	gradleComment = regexp.MustCompile(`^[ \t]*(?://|/\*|\*)`)
	gradleTrail   = regexp.MustCompile(`[ \t]//.*$`)
	gradleProject = regexp.MustCompile(`project[ \t]*\(`)
	gradleGroup   = regexp.MustCompile(`group[ \t]*[:=][ \t]*["'][^"']+["']`)
	gradleName    = regexp.MustCompile(`name[ \t]*[:=][ \t]*["'][^"']+["']`)
	gradleCoord   = regexp.MustCompile(`["'][^"':]+:[^"':]+(?::[^"']*)?["']`)
	gradleLibs    = regexp.MustCompile(`libs\.[A-Za-z0-9_.-]+`)
	quoted        = regexp.MustCompile(`["']([^"']*)["']`)
)

func firstQuoted(s string) string {
	if m := quoted.FindStringSubmatch(s); m != nil {
		return m[1]
	}
	return ""
}

func depsGradle(text string) []string {
	var out []string
	for _, line := range strings.Split(text, "\n") {
		if gradleComment.MatchString(line) {
			continue
		}
		line = gradleTrail.ReplaceAllString(line, "")
		loc := gradleCfg.FindStringIndex(line)
		if loc == nil {
			continue
		}
		rest := line[loc[1]-1:]
		if gradleProject.MatchString(rest) {
			continue
		}
		if gm := gradleGroup.FindString(rest); gm != "" {
			if nm := gradleName.FindString(rest); nm != "" {
				out = append(out, firstQuoted(gm)+":"+firstQuoted(nm))
			}
			continue
		}
		if cm := gradleCoord.FindString(rest); cm != "" {
			f := strings.Split(cm[1:len(cm)-1], ":")
			out = append(out, f[0]+":"+f[1])
			continue
		}
		if lm := gradleLibs.FindString(rest); lm != "" {
			out = append(out, lm)
		}
	}
	return out
}

func gitShow(root, base, path string) []byte {
	b, err := scope.Git(root, "show", base+":"+path)
	if err != nil {
		return nil
	}
	return b
}

func (dependencies) Run(ctx Context, params any) Outcome {
	p := params.(dependenciesParams)
	cands, err := scope.Candidates(ctx.Root)
	if err != nil {
		return Outcome{Status: result.Error, Summary: err.Error()}
	}
	var manifests []string
	for _, f := range selectFiles(cands, p.Include, p.Exclude) {
		if manifestKind(f) == "" || strings.HasPrefix(f, "node_modules/") || strings.Contains(f, "/node_modules/") {
			continue
		}
		manifests = append(manifests, f)
	}
	if ctx.Measure {
		counts := map[string]int{}
		for _, m := range manifests {
			b, _ := os.ReadFile(filepath.Join(ctx.Root, filepath.FromSlash(m)))
			counts[m] = len(depsOf(manifestKind(m), b))
		}
		return Outcome{Status: result.Pass, Summary: "measured", Counts: counts}
	}
	if ctx.Base == "" {
		return Outcome{Status: result.Pass, Summary: "No commits yet - nothing to compare."}
	}
	short, err := scope.Git(ctx.Root, "rev-parse", "--short", ctx.Base)
	if err != nil {
		return Outcome{Status: result.Fail, Summary: fmt.Sprintf("BMAX_GUARD_BASE=%s is not a commit.", ctx.Base),
			Guidance: "Set BMAX_GUARD_BASE to the branch the change will merge into (e.g. origin/main), or unset it."}
	}
	sh := strings.TrimSpace(string(short))
	if _, err := scope.Git(ctx.Root, "cat-file", "-e", ctx.Base+":.agents/bmax.yml"); err != nil {
		return Outcome{Status: result.Pass, Summary: fmt.Sprintf("Harness installed in this change - nothing to compare (base %s).", sh)}
	}
	// New direct dependencies: in the manifest now, not at the base.
	type newDep struct{ manifest, name string }
	var news []newDep
	for _, m := range manifests {
		cur, _ := os.ReadFile(filepath.Join(ctx.Root, filepath.FromSlash(m)))
		old := map[string]bool{}
		for _, d := range depsOf(manifestKind(m), gitShow(ctx.Root, ctx.Base, m)) {
			old[d] = true
		}
		for _, d := range depsOf(manifestKind(m), cur) {
			if !old[d] {
				news = append(news, newDep{m, d})
			}
		}
	}
	// ADRs added since the base (committed or not).
	adrDir := strings.TrimSuffix(ctx.Cfg.ADRDir, "/")
	adrs := map[string]bool{}
	if out, err := scope.Git(ctx.Root, "diff", "--name-only", "-z", "--diff-filter=A", ctx.Base, "--", adrDir); err == nil {
		for _, f := range bytes.Split(out, []byte{0}) {
			if len(f) > 0 {
				adrs[string(f)] = true
			}
		}
	}
	if out, err := scope.Git(ctx.Root, "ls-files", "-z", "--others", "--exclude-standard", "--", adrDir); err == nil {
		for _, f := range bytes.Split(out, []byte{0}) {
			if len(f) > 0 {
				adrs[string(f)] = true
			}
		}
	}
	var adrText []string
	for a := range adrs {
		if b, err := os.ReadFile(filepath.Join(ctx.Root, filepath.FromSlash(a))); err == nil {
			adrText = append(adrText, string(b))
		}
	}
	named := func(manifest string) bool {
		re := regexp.MustCompile(`(^|[^A-Za-z0-9_./-])(\./)?` + regexp.QuoteMeta(manifest) + `($|[^A-Za-z0-9_.-]|\.([^A-Za-z0-9_-]|$))`)
		for _, t := range adrText {
			for _, line := range strings.Split(t, "\n") {
				if re.MatchString(line) {
					return true
				}
			}
		}
		return false
	}
	var left []result.Finding
	covered := 0
	for _, n := range news {
		if named(n.manifest) {
			covered++
		} else {
			left = append(left, result.Finding{File: n.manifest, Rule: "dependencies", Severity: "error", Message: n.name})
		}
	}
	if len(left) == 0 {
		if covered > 0 {
			return Outcome{Status: result.Pass, Summary: fmt.Sprintf("%d new direct dependency(ies) since %s, each in a manifest named by an ADR added in this change.", covered, sh), Guidance: depGuidance}
		}
		return Outcome{Status: result.Pass, Summary: fmt.Sprintf("%d manifest(s) checked, no new direct dependency since %s.", len(manifests), sh), Guidance: depGuidance}
	}
	return Outcome{Status: result.Fail, Summary: fmt.Sprintf("%d new direct dependency(ies) since %s without an ADR naming the manifest.", len(left), sh), Findings: left, Guidance: depGuidance}
}
