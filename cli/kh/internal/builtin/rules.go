package builtin

import (
	"bytes"
	"embed"
	"fmt"
	"regexp"
	"sort"
	"strings"

	"github.com/aether-labs-org/plugins/cli/kh/internal/result"
)

//go:embed stoplists/*.txt
var stoplists embed.FS

// ---------------------------------------------------------------- file-size

type fileSize struct{}

type fileSizeParams struct {
	Limit   int      `json:"limit"`
	Include []string `json:"include"`
	Exclude []string `json:"exclude"`
}

func (fileSize) Name() string         { return "file-size" }
func (fileSize) DefaultClass() string { return "heuristic" }

func (fileSize) Decode(with map[string]any) (any, []string) {
	p, problems := decodeWith[fileSizeParams](with)
	if p.Limit == 0 {
		p.Limit = 300
	}
	if p.Limit < 1 {
		problems = append(problems, "limit must be at least 1")
	}
	return p, problems
}

func (fileSize) Run(ctx Context, params any) Outcome {
	p := params.(fileSizeParams)
	files := selectFiles(ctx.Files, p.Include, p.Exclude)
	counts := map[string]int{}
	var fs []result.Finding
	checked := 0
	for _, f := range files {
		b, ok := readText(ctx.Root, f)
		if !ok {
			continue
		}
		checked++
		n := bytes.Count(b, []byte{'\n'})
		if n > p.Limit {
			counts[f] = n
			fs = append(fs, result.Finding{File: f, Rule: "file-size", Severity: "error", Message: fmt.Sprintf("%d lines (limit %d)", n, p.Limit)})
		}
	}
	if checked == 0 {
		return noScope()
	}
	sortFindings(fs)
	g := fmt.Sprintf("Split the files above by responsibility so each part stays within %d lines. Do not raise the baseline or the limit in .agents/keel.yml.", p.Limit)
	if len(fs) == 0 {
		return Outcome{Status: result.Pass, Summary: fmt.Sprintf("%d files checked, 0 over %d lines", checked, p.Limit), Counts: counts, Guidance: g}
	}
	return Outcome{Status: result.Fail, Summary: fmt.Sprintf("%d of %d files over %d lines", len(fs), checked, p.Limit), Findings: fs, Counts: counts, Guidance: g}
}

// ------------------------------------------------------------ code-language

type codeLanguage struct{}

type codeLanguageParams struct {
	Include  []string `json:"include"`
	Exclude  []string `json:"exclude"`
	Stoplist string   `json:"stoplist"`
}

func (codeLanguage) Name() string         { return "code-language" }
func (codeLanguage) DefaultClass() string { return "heuristic" }

func (codeLanguage) Decode(with map[string]any) (any, []string) {
	p, problems := decodeWith[codeLanguageParams](with)
	if p.Stoplist == "" {
		p.Stoplist = "pt"
	}
	return p, problems
}

func loadStoplist(ctx Context, name string) (map[string]bool, error) {
	var b []byte
	var err error
	if emb, e := stoplists.ReadFile("stoplists/" + name + ".txt"); e == nil {
		b = emb
	} else {
		b, err = readRepoFile(ctx.Root, name)
		if err != nil {
			return nil, fmt.Errorf("stop-list %s not found", name)
		}
	}
	m := map[string]bool{}
	for _, l := range strings.Split(string(b), "\n") {
		l = strings.TrimSpace(l)
		if l != "" && !strings.HasPrefix(l, "#") {
			m[l] = true
		}
	}
	return m, nil
}

// flaggedWords ports the awk of the v0.3 sensor: words made of ASCII letters
// and non-ASCII bytes, split at lower-to-upper camel case, outside string
// literals (the quote state resets at each line). A word is flagged when it has
// a non-ASCII byte or, at two letters or more, is in the stop-list.
func flaggedWords(src []byte, stop map[string]bool) []string {
	var out []string
	for _, line := range bytes.Split(src, []byte{'\n'}) {
		var word []byte
		nonascii, prevLower := false, false
		var q byte
		flush := func() {
			if len(word) == 0 {
				return
			}
			lw := strings.ToLower(string(word))
			if nonascii || (len(lw) >= 2 && stop[lw]) {
				out = append(out, lw)
			}
			word, nonascii = word[:0], false
		}
		for k := 0; k < len(line); k++ {
			c := line[k]
			if q != 0 {
				if c == '\\' {
					k++
				} else if c == q {
					q = 0
				}
				continue
			}
			if c == '"' || c == '\'' {
				flush()
				q, prevLower = c, false
				continue
			}
			isAlpha := (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c >= 0x80
			if isAlpha {
				if c >= 'A' && c <= 'Z' && prevLower {
					flush()
				}
				if c >= 0x80 {
					nonascii = true
				}
				word = append(word, c)
				prevLower = (c >= 'a' && c <= 'z') || c >= 0x80
			} else {
				flush()
				prevLower = false
			}
		}
		flush()
	}
	return out
}

func (codeLanguage) Run(ctx Context, params any) Outcome {
	p := params.(codeLanguageParams)
	stop, err := loadStoplist(ctx, p.Stoplist)
	if err != nil {
		return Outcome{Status: result.Skip, Summary: err.Error()}
	}
	files := selectFiles(ctx.Files, p.Include, p.Exclude)
	counts := map[string]int{}
	var fs []result.Finding
	checked := 0
	for _, f := range files {
		b, ok := readText(ctx.Root, f)
		if !ok {
			continue
		}
		checked++
		w := flaggedWords(b, stop)
		if len(w) > 0 {
			counts[f] = len(w)
			fs = append(fs, result.Finding{File: f, Rule: "code-language", Severity: "error", Message: fmt.Sprintf("%d flagged word(s), e.g. %s", len(w), w[0])})
		}
	}
	if checked == 0 {
		return noScope()
	}
	sortFindings(fs)
	g := "Rename the identifiers and rewrite the comments listed above in the project's code language. User-facing text belongs in string literals or i18n files, which this check ignores."
	if len(fs) == 0 {
		return Outcome{Status: result.Pass, Summary: fmt.Sprintf("%d files checked, no non-English words", checked), Counts: counts, Guidance: g}
	}
	return Outcome{Status: result.Fail, Summary: fmt.Sprintf("%d of %d files with non-English words", len(fs), checked), Findings: fs, Counts: counts, Guidance: g}
}

// ------------------------------------------------------------ folder-layout

type folderLayout struct{}

type folderLayoutParams struct {
	Include []string `json:"include"`
	Exclude []string `json:"exclude"`
	Allowed []string `json:"allowed"`
}

func (folderLayout) Name() string { return "folder-layout" }

func (folderLayout) Decode(with map[string]any) (any, []string) {
	p, problems := decodeWith[folderLayoutParams](with)
	if len(problems) == 0 && len(p.Allowed) == 0 {
		problems = append(problems, "allowed is required: the patterns a file may match")
	}
	return p, problems
}

// shellPattern compiles a shell `case` pattern: * crosses "/", ? is one
// character, [...] a class.
func shellPattern(p string) *regexp.Regexp {
	var b strings.Builder
	b.WriteString("^")
	for i := 0; i < len(p); i++ {
		switch c := p[i]; c {
		case '*':
			b.WriteString(".*")
		case '?':
			b.WriteString(".")
		case '[':
			j := strings.IndexByte(p[i:], ']')
			if j > 1 {
				cls := p[i+1 : i+j]
				if strings.HasPrefix(cls, "!") {
					cls = "^" + cls[1:]
				}
				b.WriteString("[" + cls + "]")
				i += j
			} else {
				b.WriteString(`\[`)
			}
		default:
			b.WriteString(regexp.QuoteMeta(string(c)))
		}
	}
	b.WriteString("$")
	return regexp.MustCompile(b.String())
}

func (folderLayout) Run(ctx Context, params any) Outcome {
	p := params.(folderLayoutParams)
	var pats []*regexp.Regexp
	for _, a := range p.Allowed {
		pats = append(pats, shellPattern(a))
	}
	files := selectFiles(ctx.Files, p.Include, p.Exclude)
	counts := map[string]int{}
	var fs []result.Finding
	checked := 0
	for _, f := range files {
		if !exists(ctx.Root, f) {
			continue
		}
		checked++
		ok := false
		for _, re := range pats {
			if re.MatchString(f) {
				ok = true
				break
			}
		}
		if !ok {
			counts[f] = 1
			fs = append(fs, result.Finding{File: f, Rule: "folder-layout", Severity: "error", Message: "not in an allowed location"})
		}
	}
	if checked == 0 {
		return noScope()
	}
	sortFindings(fs)
	g := "Move each file above to where the architecture guide says it belongs. Never widen allowed in .agents/keel.yml or raise the baseline to make this pass."
	if len(fs) == 0 {
		return Outcome{Status: result.Pass, Summary: fmt.Sprintf("%d files checked, all in an allowed location", checked), Counts: counts, Guidance: g}
	}
	return Outcome{Status: result.Fail, Summary: fmt.Sprintf("%d of %d files outside the allowed layout", len(fs), checked), Findings: fs, Counts: counts, Guidance: g}
}

// ------------------------------------------------------------------ pattern

type pattern struct{}

type patternParams struct {
	Pattern string   `json:"pattern"`
	Include []string `json:"include"`
	Exclude []string `json:"exclude"`
	Message string   `json:"message"`
	Fix     string   `json:"fix"`
}

func (pattern) Name() string         { return "pattern" }
func (pattern) DefaultClass() string { return "heuristic" }

func (pattern) Decode(with map[string]any) (any, []string) {
	p, problems := decodeWith[patternParams](with)
	if len(problems) > 0 {
		return p, problems
	}
	if p.Pattern == "" {
		return p, []string{"pattern is required"}
	}
	if _, err := regexp.Compile(p.Pattern); err != nil {
		return p, []string{"pattern is not a valid regular expression: " + err.Error()}
	}
	return p, nil
}

func (pattern) Run(ctx Context, params any) Outcome {
	p := params.(patternParams)
	re := regexp.MustCompile(p.Pattern)
	files := selectFiles(ctx.Files, p.Include, p.Exclude)
	counts := map[string]int{}
	var fs []result.Finding
	checked := 0
	for _, f := range files {
		b, ok := readText(ctx.Root, f)
		if !ok {
			continue
		}
		checked++
		n := 0
		first := 0
		for i, line := range bytes.Split(b, []byte{'\n'}) {
			if re.Match(line) {
				if n == 0 {
					first = i + 1
				}
				n++
			}
		}
		if n > 0 {
			counts[f] = n
			fs = append(fs, result.Finding{File: f, Line: first, Rule: "pattern", Severity: "error", Message: fmt.Sprintf("%d match(es)", n)})
		}
	}
	if checked == 0 {
		return noScope()
	}
	sortFindings(fs)
	msg := p.Message
	if msg == "" {
		msg = "Remove the matches listed above."
	}
	g := msg
	if p.Fix != "" {
		g += " " + p.Fix
	}
	g += " Never add a suppression to make this pass, and do not raise the baseline or change the pattern in .agents/keel.yml."
	if len(fs) == 0 {
		return Outcome{Status: result.Pass, Summary: fmt.Sprintf("%d files checked, no matches", checked), Counts: counts, Guidance: g}
	}
	return Outcome{Status: result.Fail, Summary: fmt.Sprintf("%d of %d files with matches", len(fs), checked), Findings: fs, Counts: counts, Guidance: g}
}

// ------------------------------------------------------------ test-presence

type testPresence struct{}

type testPresenceParams struct {
	Include  []string `json:"include"`
	Exclude  []string `json:"exclude"`
	Mappings []string `json:"mappings"`
}

func (testPresence) Name() string         { return "test-presence" }
func (testPresence) DefaultClass() string { return "heuristic" }

type mapping struct {
	from *regexp.Regexp
	to   string
}

var backref = regexp.MustCompile(`\\([0-9])`)

func parseMappings(ms []string) ([]mapping, []string) {
	var out []mapping
	var problems []string
	for _, m := range ms {
		from, to, ok := strings.Cut(m, "|")
		if !ok || from == "" || to == "" {
			problems = append(problems, fmt.Sprintf("mapping %q must be from|to", m))
			continue
		}
		re, err := regexp.Compile(from)
		if err != nil {
			problems = append(problems, fmt.Sprintf("mapping %q: %v", m, err))
			continue
		}
		out = append(out, mapping{re, backref.ReplaceAllString(to, "${$1}")})
	}
	return out, problems
}

func (testPresence) Decode(with map[string]any) (any, []string) {
	p, problems := decodeWith[testPresenceParams](with)
	if len(problems) > 0 {
		return p, problems
	}
	if len(p.Mappings) == 0 {
		return p, []string{"mappings is required: lines from|to mapping a main file to its test"}
	}
	_, problems = parseMappings(p.Mappings)
	return p, problems
}

func (testPresence) Run(ctx Context, params any) Outcome {
	p := params.(testPresenceParams)
	maps, _ := parseMappings(p.Mappings)
	files := selectFiles(ctx.Files, p.Include, p.Exclude)
	counts := map[string]int{}
	var fs []result.Finding
	checked := 0
	for _, f := range files {
		if !exists(ctx.Root, f) {
			continue
		}
		checked++
		applied, found, first := false, false, ""
		for _, m := range maps {
			if !m.from.MatchString(f) {
				continue
			}
			applied = true
			t := m.from.ReplaceAllString(f, m.to)
			if first == "" {
				first = t
			}
			if exists(ctx.Root, t) {
				found = true
				break
			}
		}
		if applied && !found {
			counts[f] = 1
			fs = append(fs, result.Finding{File: f, Rule: "test-presence", Severity: "error", Message: "no test found (expected " + first + ")"})
		}
	}
	if checked == 0 {
		return noScope()
	}
	sortFindings(fs)
	g := "Write the missing test at the mapped path, for the behaviour you changed. Do not create an empty test to pass, and do not add the file to the baseline."
	if len(fs) == 0 {
		return Outcome{Status: result.Pass, Summary: fmt.Sprintf("%d files checked, all have a test", checked), Counts: counts, Guidance: g}
	}
	return Outcome{Status: result.Fail, Summary: fmt.Sprintf("%d of %d files without a test", len(fs), checked), Findings: fs, Counts: counts, Guidance: g}
}

// -------------------------------------------------------- architecture-grep

type architectureGrep struct{}

type layerSpec struct {
	Name    string   `json:"name"`
	Path    string   `json:"path"`
	Import  string   `json:"import"`
	Allowed []string `json:"allowed"`
}

type forbiddenSpec struct {
	Layer  string `json:"layer"`
	Prefix string `json:"prefix"`
}

type architectureGrepParams struct {
	Lang      string          `json:"lang"`
	Layers    []layerSpec     `json:"layers"`
	Forbidden []forbiddenSpec `json:"forbidden"`
}

func (architectureGrep) Name() string { return "architecture-grep" }

func (architectureGrep) Decode(with map[string]any) (any, []string) {
	p, problems := decodeWith[architectureGrepParams](with)
	if len(problems) > 0 {
		return p, problems
	}
	switch p.Lang {
	case "java", "kotlin", "python":
	default:
		problems = append(problems, "lang must be java, kotlin or python (use a native tool for other languages)")
	}
	if len(p.Layers) == 0 {
		problems = append(problems, "layers is required")
	}
	names := map[string]bool{}
	for i, l := range p.Layers {
		if l.Name == "" || l.Path == "" || l.Import == "" {
			problems = append(problems, fmt.Sprintf("layers[%d]: name, path and import are required", i))
		}
		names[l.Name] = true
	}
	for i, l := range p.Layers {
		for _, a := range l.Allowed {
			if !names[a] {
				problems = append(problems, fmt.Sprintf("layers[%d]: allowed names unknown layer %q", i, a))
			}
		}
	}
	for i, f := range p.Forbidden {
		if !names[f.Layer] || f.Prefix == "" {
			problems = append(problems, fmt.Sprintf("forbidden[%d]: layer must name a layer and prefix is required", i))
		}
	}
	return p, problems
}

// under reports whether import t is the package prefix p or inside it.
func under(t, p string) bool {
	if p == "" || !strings.HasPrefix(t, p) {
		return false
	}
	return strings.HasSuffix(p, ".") || len(t) == len(p) || t[len(p)] == '.'
}

var (
	pyImport   = regexp.MustCompile(`^[ \t]*(?:from|import)[ \t]+([^ \t\r]+)`)
	javaImport = regexp.MustCompile(`^[ \t]*import[ \t]+(?:static[ \t]+)?([^; \t\r]+)`)
)

func (architectureGrep) Run(ctx Context, params any) Outcome {
	p := params.(architectureGrepParams)
	ext := map[string]string{"java": ".java", "kotlin": ".kt", "python": ".py"}[p.Lang]
	re := javaImport
	if p.Lang == "python" {
		re = pyImport
	}
	counts := map[string]int{}
	var fs []result.Finding
	checked := 0
	for _, f := range ctx.Files {
		if !strings.HasSuffix(f, ext) || !exists(ctx.Root, f) {
			continue
		}
		mine := -1
		for i, l := range p.Layers {
			if strings.HasPrefix(f, strings.TrimSuffix(l.Path, "/")+"/") && (mine < 0 || len(l.Path) > len(p.Layers[mine].Path)) {
				mine = i
			}
		}
		if mine < 0 {
			continue
		}
		b, ok := readText(ctx.Root, f)
		if !ok {
			continue
		}
		checked++
		allowed := map[string]bool{}
		for _, a := range p.Layers[mine].Allowed {
			allowed[a] = true
		}
		n := 0
		for ln, line := range bytes.Split(b, []byte{'\n'}) {
			m := re.FindSubmatch(line)
			if m == nil {
				continue
			}
			t := string(m[1])
			for i, l := range p.Layers {
				if i != mine && under(t, l.Import) && !allowed[l.Name] {
					n++
					fs = append(fs, result.Finding{File: f, Line: ln + 1, Rule: "architecture-grep", Severity: "error",
						Message: fmt.Sprintf("%s must not import %s (layer %s)", p.Layers[mine].Name, t, l.Name)})
					break
				}
			}
			for _, fb := range p.Forbidden {
				if fb.Layer == p.Layers[mine].Name && under(t, fb.Prefix) {
					n++
					fs = append(fs, result.Finding{File: f, Line: ln + 1, Rule: "architecture-grep", Severity: "error",
						Message: fmt.Sprintf("%s must not import %s", fb.Layer, t)})
				}
			}
		}
		counts[f] = n
	}
	if checked == 0 {
		return noScope()
	}
	for f, n := range counts {
		if n == 0 {
			delete(counts, f)
		}
	}
	sortFindings(fs)
	g := "Move the dependency behind a port owned by the inner layer, or move the code to the layer allowed to depend on it. Do not edit the layers in .agents/keel.yml or raise the baseline to make this pass."
	if len(fs) == 0 {
		return Outcome{Status: result.Pass, Summary: fmt.Sprintf("%d files checked, no architecture violations", checked), Counts: counts, Guidance: g}
	}
	files := map[string]bool{}
	for _, f := range fs {
		files[f.File] = true
	}
	keys := make([]string, 0, len(files))
	for k := range files {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return Outcome{Status: result.Fail, Summary: fmt.Sprintf("%d of %d files with architecture violations", len(keys), checked), Findings: fs, Counts: counts, Guidance: g}
}
