// Package guard is the native port of scripts/sensors/guard.sh (D32), extended to keel.yaml: it fails
// when the harness was loosened since the base commit unless an ADR added in this change names the
// loosened file. Its output obeys the sensor contract byte for byte.
package guard

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"github.com/aether-labs-org/plugins/cli/kh/internal/config"
	"github.com/aether-labs-org/plugins/cli/kh/internal/envfile"
)

const (
	id       = "guard"
	class    = "security"
	Guidance = "undo the loosening and fix the code instead. If loosening is really the decision, add an ADR in this same change that names each file listed above and says why. Editing, deleting or disabling this sensor is the wrong fix."
)

// ADRDirs are the folders read for ADRs added in the change (guard.sh's ADR_DIRS).
var ADRDirs = []string{"docs/adr", "doc/adr", "docs/decisions", "docs/architecture/decisions"}

type finding struct{ file, what string }

type repo struct{ root string }

func (r repo) git(args ...string) (string, error) {
	cmd := exec.Command("git", args...)
	cmd.Dir = r.root
	out, err := cmd.Output()
	return string(out), err
}

func (r repo) atBase(base, path string) (string, bool) {
	out, err := r.git("show", base+":"+path)
	return out, err == nil
}

func (r repo) read(path string) (string, bool) {
	b, err := os.ReadFile(filepath.Join(r.root, path))
	return string(b), err == nil
}

func line1(status, summary string) string {
	return fmt.Sprintf("%s\t%s\t%s\t%s\n", id, class, status, summary)
}

// Run returns guard's contract output and exit code (0 pass, 1 fail).
func Run(root string) (string, int) {
	r := repo{root}
	if _, err := r.git("rev-parse", "--verify", "-q", "HEAD"); err != nil {
		return line1("pass", "No commits yet - nothing to compare."), 0
	}
	base := os.Getenv("KEEL_GUARD_BASE")
	if base == "" {
		if _, err := r.git("rev-parse", "--verify", "-q", "refs/remotes/origin/HEAD"); err == nil {
			mb, _ := r.git("merge-base", "HEAD", "refs/remotes/origin/HEAD")
			base = strings.TrimSpace(mb)
		}
	}
	if base == "" {
		base = "HEAD"
	}
	s, err := r.git("rev-parse", "--short", base)
	if err != nil {
		return line1("fail", "KEEL_GUARD_BASE="+base+" is not a commit.") +
			"  guidance: Set KEEL_GUARD_BASE to the branch the change will merge into (e.g. origin/main), or unset it.\n", 1
	}
	short := strings.TrimSpace(s)
	if _, err := r.git("cat-file", "-e", base+":.agents/state.yml"); err != nil {
		return line1("pass", "Harness installed in this change - nothing to compare (base "+short+")."), 0
	}

	var loose []finding
	add := func(f, w string) { loose = append(loose, finding{f, w}) }
	baselines(r, base, add)
	rules(r, base, add)
	budgets(r, base, add)
	sensors(r, base, add)

	adrs := addedADRs(r, base)
	var left []string
	covered := 0
	for _, l := range loose {
		if namedBy(r, adrs, l.file) {
			covered++
		} else {
			left = append(left, l.file+": "+l.what)
		}
	}
	if len(left) == 0 {
		if covered > 0 {
			return line1("pass", fmt.Sprintf("%d loosening(s) since %s, each named by an ADR added in this change.", covered, short)), 0
		}
		return line1("pass", "No harness file loosened since "+short+"."), 0
	}
	var b strings.Builder
	b.WriteString(line1("fail", fmt.Sprintf("%d loosening(s) of the harness since %s without an ADR.", len(left), short)))
	for i, l := range left {
		if i == 5 {
			break
		}
		b.WriteString("  " + l + "\n")
	}
	b.WriteString("  guidance: " + Guidance + "\n")
	return b.String(), 1
}

func nonEmptyLines(s string) []string {
	var out []string
	for _, l := range strings.Split(s, "\n") {
		if l != "" {
			out = append(out, l)
		}
	}
	return out
}

var awkNumber = regexp.MustCompile(`^[ \t\n\v\f\r]*[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?`)

// awkNum is awk's `$2 + 0`: the longest numeric prefix, 0 when there is none.
func awkNum(s string) float64 {
	m := strings.TrimLeft(awkNumber.FindString(s), " \t\n\v\f\r")
	v, _ := strconv.ParseFloat(m, 64)
	return v
}

// tsvRows yields (path, count) for each line that is not a comment and has at least two TAB fields.
func tsvRows(s string, fn func(path, count string)) {
	lines := strings.Split(s, "\n")
	if strings.HasSuffix(s, "\n") {
		lines = lines[:len(lines)-1]
	}
	for _, l := range lines {
		if strings.HasPrefix(l, "#") {
			continue
		}
		f := strings.Split(l, "\t")
		if len(f) >= 2 {
			fn(f[0], f[1])
		}
	}
}

// 1. Baselines: a TSV row whose count grew or appeared; any other file (native store) with more lines.
func baselines(r repo, base string, add func(string, string)) {
	a, _ := r.git("ls-tree", "-r", "--name-only", base, "--", ".agents/baselines/")
	b, _ := r.git("ls-files", "--cached", "--others", "--exclude-standard", "--", ".agents/baselines/")
	set := map[string]bool{}
	for _, f := range nonEmptyLines(a + "\n" + b) {
		set[f] = true
	}
	files := make([]string, 0, len(set))
	for f := range set {
		files = append(files, f)
	}
	sort.Strings(files)
	for _, f := range files {
		old, _ := r.atBase(base, f)
		cur, _ := r.read(f)
		cur = strings.ReplaceAll(cur, "\r", "")
		if strings.HasSuffix(f, ".tsv") {
			prev := map[string]float64{}
			tsvRows(old, func(p, c string) { prev[p] = awkNum(c) })
			tsvRows(cur, func(p, c string) {
				o := prev[p]
				if n := awkNum(c); n > o {
					add(f, fmt.Sprintf("%s %d -> %d", p, int64(o), int64(n)))
				}
			})
			continue
		}
		if o, n := len(nonEmptyLines(old)), len(nonEmptyLines(cur)); n > o {
			add(f, fmt.Sprintf("native baseline grew from %d to %d lines", o, n))
		}
	}
}

var envKey = regexp.MustCompile(`^[ \t\n\v\f\r]*([A-Z_][A-Z0-9_]*)=`)

// envGet mirrors guard.sh's env_get: a file that does not parse yields "" for every key.
func envGet(name, data, key string) string {
	vals, err := envfile.Parse(name, data)
	if err != nil {
		return ""
	}
	return vals[key]
}

func isNum(s string) bool {
	if s == "" {
		return false
	}
	for i := 0; i < len(s); i++ {
		if s[i] < '0' || s[i] > '9' {
			return false
		}
	}
	return true
}

func atoi(s string) int64 { n, _ := strconv.ParseInt(s, 10, 64); return n }

// countLines is `grep -c '[^[:space:]]'`: lines with at least one non-blank character.
func countLines(s string) int {
	n := 0
	for _, l := range strings.Split(s, "\n") {
		if strings.TrimLeft(l, " \t\v\f\r") != "" {
			n++
		}
	}
	return n
}

// 2. Rule env files: relaxed limits, widened lists, changed enforcement, deleted rules.
func rules(r repo, base string, add func(string, string)) {
	ls, _ := r.git("ls-tree", "--name-only", base, "--", ".agents/rules/")
	for _, f := range nonEmptyLines(ls) {
		if !strings.HasSuffix(f, ".env") {
			continue
		}
		cur, ok := r.read(f)
		if !ok {
			add(f, "rule deleted")
			continue
		}
		old, _ := r.atBase(base, f)
		keys := map[string]bool{}
		for _, src := range []string{old, cur} {
			for _, l := range strings.Split(src, "\n") {
				if m := envKey.FindStringSubmatch(l); m != nil {
					keys[m[1]] = true
				}
			}
		}
		sorted := make([]string, 0, len(keys))
		for k := range keys {
			sorted = append(sorted, k)
		}
		sort.Strings(sorted)
		for _, k := range sorted {
			o, n := envGet(f, old, k), envGet(f, cur, k)
			if o == n {
				continue
			}
			switch {
			case strings.Contains(k, "MIN"):
				if isNum(o) && isNum(n) && atoi(n) < atoi(o) {
					add(f, fmt.Sprintf("%s lowered from %s to %s", k, o, n))
				}
			case strings.Contains(k, "LIMIT") || strings.Contains(k, "MAX"):
				if isNum(o) && isNum(n) && atoi(n) > atoi(o) {
					add(f, fmt.Sprintf("%s raised from %s to %s", k, o, n))
				}
			case k == "ALLOWED" || k == "EXCLUDE" || k == "IGNORE_IMPORTS":
				if countLines(n) > countLines(o) {
					add(f, k+" widened")
				}
			case k == "INCLUDE" || k == "FORBIDDEN":
				if countLines(n) < countLines(o) {
					add(f, k+" narrowed")
				}
			case k == "ENFORCEMENT":
				add(f, fmt.Sprintf("ENFORCEMENT changed from '%s' to '%s'", o, n))
			}
		}
	}
}

// budget is one ceiling as read from keel.yaml or gate.env.
type budget struct {
	file, key, value string
}

// budgetsOf reads the fast and slow ceilings from keel.yaml when it exists, else from gate.env.
func budgetsOf(yamlData string, yamlOK bool, envData string, envOK bool) ([]budget, bool) {
	if yamlOK {
		if c, err := config.Parse([]byte(yamlData)); err == nil {
			return []budget{
				{config.File, "gate.fast.ceiling_seconds", strconv.Itoa(c.Ceiling("fast"))},
				{config.File, "gate.slow.ceiling_seconds", strconv.Itoa(c.Ceiling("slow"))},
			}, true
		}
	}
	if envOK {
		return []budget{
			{".agents/gate.env", "CEILING_SECONDS", envGet(".agents/gate.env", envData, "CEILING_SECONDS")},
			{".agents/gate.env", "SLOW_CEILING_SECONDS", envGet(".agents/gate.env", envData, "SLOW_CEILING_SECONDS")},
		}, true
	}
	return nil, false
}

// 3. Gate budgets, wherever they live at the base and now (an engine switch moves them).
func budgets(r repo, base string, add func(string, string)) {
	by, byOK := r.atBase(base, config.File)
	be, beOK := r.atBase(base, ".agents/gate.env")
	ny, nyOK := r.read(config.File)
	ne, neOK := r.read(".agents/gate.env")
	old, ok1 := budgetsOf(by, byOK, be, beOK)
	cur, ok2 := budgetsOf(ny, nyOK, ne, neOK)
	if !ok1 || !ok2 {
		return
	}
	for i := range cur {
		o, n := old[i].value, cur[i].value
		if isNum(o) && isNum(n) && atoi(n) > atoi(o) {
			add(cur[i].file, fmt.Sprintf("%s raised from %s to %s", cur[i].key, o, n))
		}
	}
}

// sensorSet maps "gate/id" to the file a reviewer must name: the exec path, or keel.yaml itself.
type sensorSet struct {
	keys   []string
	labels map[string]string
}

func fromConfig(data string) (sensorSet, bool) {
	c, err := config.Parse([]byte(data))
	if err != nil {
		return sensorSet{}, false
	}
	s := sensorSet{labels: map[string]string{}}
	for _, e := range c.Sensors {
		k := e.Gate + "/" + e.ID
		label := config.File
		if e.Exec != "" {
			label = e.Exec
		}
		s.keys = append(s.keys, k)
		s.labels[k] = label
	}
	return s, true
}

func fromFiles(paths []string) sensorSet {
	s := sensorSet{labels: map[string]string{}}
	for _, p := range paths {
		if !strings.HasSuffix(p, ".sh") || strings.HasPrefix(filepath.Base(p), "_") {
			continue
		}
		dir := filepath.Dir(p)
		if dir != "scripts/sensors" && dir != "scripts/sensors/slow" {
			continue
		}
		gate := "fast"
		if dir == "scripts/sensors/slow" {
			gate = "slow"
		}
		k := gate + "/" + strings.TrimSuffix(filepath.Base(p), ".sh")
		s.keys = append(s.keys, k)
		s.labels[k] = p
	}
	return s
}

// 4. Sensors removed, disabled or dropped from keel.yaml since the base.
func sensors(r repo, base string, add func(string, string)) {
	var old sensorSet
	data, ok := r.atBase(base, config.File)
	if ok {
		old, ok = fromConfig(data)
	}
	if !ok {
		ls, _ := r.git("ls-tree", "--name-only", base, "--", "scripts/sensors/", "scripts/sensors/slow/")
		old = fromFiles(nonEmptyLines(ls))
	}
	var cur sensorSet
	data, ok = r.read(config.File)
	if ok {
		cur, ok = fromConfig(data)
	}
	if !ok {
		var paths []string
		for _, d := range []string{"scripts/sensors", "scripts/sensors/slow"} {
			m, _ := filepath.Glob(filepath.Join(r.root, d, "*.sh"))
			for _, f := range m {
				if st, err := os.Stat(f); err == nil && st.Mode().IsRegular() {
					paths = append(paths, d+"/"+filepath.Base(f))
				}
			}
		}
		cur = fromFiles(paths)
	}
	for _, k := range old.keys {
		if _, ok := cur.labels[k]; !ok {
			add(old.labels[k], "sensor removed or disabled")
		}
	}
}

func addedADRs(r repo, base string) []string {
	set := map[string]bool{}
	for _, d := range ADRDirs {
		a, _ := r.git("diff", "--name-only", "--diff-filter=A", base, "--", d)
		b, _ := r.git("ls-files", "--others", "--exclude-standard", "--", d)
		for _, f := range nonEmptyLines(a + "\n" + b) {
			set[f] = true
		}
	}
	out := make([]string, 0, len(set))
	for f := range set {
		out = append(out, f)
	}
	sort.Strings(out)
	return out
}

func namedBy(r repo, adrs []string, file string) bool {
	for _, a := range adrs {
		if b, ok := r.read(a); ok && strings.Contains(b, file) {
			return true
		}
	}
	return false
}
