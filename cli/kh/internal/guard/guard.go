// Package guard detects loosenings of the harness itself: what an agent could
// change so that the gate turns green without the code getting better. A
// loosening passes only when an ADR added since the base names the loosened
// script (.agents/keel.yml#<id>) or the file.
package guard

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/aether-labs-org/plugins/cli/kh/internal/config"
	"github.com/aether-labs-org/plugins/cli/kh/internal/scope"
)

// Loosening is one change that makes the harness weaker.
type Loosening struct {
	Target string // ".agents/keel.yml#<id>" or a repository path
	What   string
	// Alt is a second name that releases the loosening (the script id for a
	// config or baseline file, or the file for a script).
	Alt string
}

const keelFile = ".agents/keel.yml"

// ScriptRef names a script of keel.yml the way an ADR does.
func ScriptRef(id string) string { return keelFile + "#" + id }

// Released reports whether an ADR added since the base names the loosening.
// addedADRs maps ADR path to content. Naming the whole keel.yml releases nothing.
func Released(l Loosening, addedADRs map[string]string) bool {
	for _, content := range addedADRs {
		if mentions(content, l.Target) || (l.Alt != "" && mentions(content, l.Alt)) {
			return true
		}
	}
	return false
}

// mentions reports whether content names target by its whole path or ref, not
// inside a longer one (file.tsv.bak, xdir/file.tsv, keel.yml#lint-extra).
func mentions(content, target string) bool {
	re := regexp.MustCompile(`(^|[^A-Za-z0-9_./#-])(\./)?` + regexp.QuoteMeta(target) + `($|[^A-Za-z0-9_.-]|\.([^A-Za-z0-9_-]|$))`)
	for _, line := range strings.Split(strings.ReplaceAll(content, "\r", ""), "\n") {
		if re.MatchString(line) {
			return true
		}
	}
	return false
}

type repo struct{ root, base string }

func (r repo) atBase(path string) ([]byte, bool) {
	b, err := scope.Git(r.root, "show", r.base+":"+path)
	return b, err == nil
}

func (r repo) now(path string) ([]byte, bool) {
	b, err := os.ReadFile(filepath.Join(r.root, filepath.FromSlash(path)))
	return b, err == nil
}

func (r repo) baseFiles(prefix string) []string {
	out, err := scope.Git(r.root, "ls-tree", "-r", "--name-only", "-z", r.base, "--", prefix)
	if err != nil {
		return nil
	}
	return splitZ(out)
}

func splitZ(b []byte) []string {
	var out []string
	for _, p := range strings.Split(string(b), "\x00") {
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}

// Check compares the work tree with base. It returns the loosenings no added
// ADR releases, then the released ones. The base must contain
// .agents/keel.yml; the caller handles an unborn HEAD or a first install.
func Check(root, base string) (violations, released []Loosening, err error) {
	r := repo{root, base}
	baseYML, ok := r.atBase(keelFile)
	if !ok {
		return nil, nil, fmt.Errorf("%s does not exist at %s", keelFile, base)
	}
	old, err := config.Parse(baseYML)
	if err != nil {
		return nil, nil, fmt.Errorf("%s at the base: %v", keelFile, err)
	}
	cur, err := config.Load(root)
	if err != nil {
		if os.IsNotExist(err) {
			return []Loosening{{Target: keelFile, What: "config deleted"}}, nil, nil
		}
		return nil, nil, fmt.Errorf("%s: %v", keelFile, err)
	}

	var all []Loosening
	add := func(target, what, alt string) { all = append(all, Loosening{Target: target, What: what, Alt: alt}) }

	r.configLoosenings(old, cur, add)
	r.baselineLoosenings(old, cur, add)
	r.configFiles(old, cur, add)
	r.hookEntries(add)
	r.guides(old, cur, add)
	adrEdits := r.acceptedADRs(old, add)
	_ = adrEdits
	r.strictness(add)

	added := r.addedADRs(old, cur)
	for _, l := range all {
		if Released(l, added) {
			released = append(released, l)
		} else {
			violations = append(violations, l)
		}
	}
	return violations, released, nil
}

func dur(d time.Duration) string {
	s := d.String()
	s = strings.TrimSuffix(s, "0s")
	if s == "" {
		return "0s"
	}
	if strings.HasSuffix(d.String(), "m0s") {
		return d.String()[:len(d.String())-2]
	}
	return d.String()
}

func (repo) configLoosenings(old, cur *config.Config, add func(target, what, alt string)) {
	// gates: scripts removed, ceilings raised
	gnames := make([]string, 0, len(old.Gates))
	for n := range old.Gates {
		gnames = append(gnames, n)
	}
	sort.Strings(gnames)
	for _, n := range gnames {
		og := old.Gates[n]
		cg := cur.Gates[n]
		have := map[string]bool{}
		for _, s := range cg.Scripts {
			have[s] = true
		}
		for _, s := range og.Scripts {
			if !have[s] {
				add(ScriptRef(s), "removed from gate "+n, "")
			}
		}
		if _, ok := cur.Gates[n]; ok && og.Ceiling > 0 && (cg.Ceiling == 0 || cg.Ceiling > og.Ceiling) {
			add(ScriptRef(n), "ceiling raised", "")
		}
	}
	// githooks entries
	for _, h := range []struct{ key, o, c string }{
		{"pre-commit", old.Githooks.PreCommit, cur.Githooks.PreCommit},
		{"pre-push", old.Githooks.PrePush, cur.Githooks.PrePush},
		{"commit-msg", old.Githooks.CommitMsg, cur.Githooks.CommitMsg},
	} {
		if h.o != "" && h.c == "" {
			add(ScriptRef("githooks"), "githooks "+h.key+" removed", "")
		}
	}
	// scripts
	for _, id := range old.Order {
		os_, ok := old.Scripts[id]
		cs, ok2 := cur.Scripts[id]
		if !ok {
			continue
		}
		// a config: entry that is gone (or its whole script) stops protecting the file
		kept := map[string]bool{}
		for _, f := range cs.Config {
			kept[f] = true
		}
		for _, f := range os_.Config {
			if !kept[f] {
				add(f, "config removed", ScriptRef(id))
			}
		}
		if !ok2 {
			continue
		}
		ref := ScriptRef(id)
		if cs.Timeout > os_.Timeout {
			add(ref, fmt.Sprintf("timeout raised %s -> %s", dur(os_.Timeout), dur(cs.Timeout)), "")
		}
		if cs.Retries > os_.Retries {
			add(ref, "retries raised", "")
		}
		if os_.Class == "security" && cs.Class != "security" {
			add(ref, "class changed from security", "")
		}
		if cs.Files != os_.Files && cs.Files != "" {
			add(ref, "files narrowed", "")
		}
		if os_.Format != "" && cs.Format == "" {
			add(ref, "format removed", "")
		}
		if os_.Decision != "" || cs.Decision != "" {
			if cs.Run != os_.Run || cs.Exec != os_.Exec || cs.Builtin != os_.Builtin || cs.Pattern != os_.Pattern {
				add(ref, "run changed on a script with decision", "")
			}
			if !sameJSON(os_.With, cs.With) {
				add(ref, "with changed on a script with decision", "")
			}
		}
		// exceptions added or extended
		oldUntil := map[string]string{}
		for _, e := range os_.Exceptions {
			if u, ok := oldUntil[e.Path]; !ok || e.Until > u {
				oldUntil[e.Path] = e.Until
			}
		}
		for _, e := range cs.Exceptions {
			if u, ok := oldUntil[e.Path]; !ok || e.Until > u {
				add(ref, "exception added or extended "+e.Path, "")
			}
		}
	}
	// the guard itself must stay the builtin
	if cs, ok := cur.Scripts[config.GuardID]; ok && cs.Builtin != config.GuardID {
		add(ScriptRef(config.GuardID), "guard replaced", "")
	}
}

func sameJSON(a, b map[string]any) bool {
	x, _ := json.Marshal(a)
	y, _ := json.Marshal(b)
	return string(x) == string(y)
}

// parseTSV reads the rows of a TSV baseline leniently: comments and malformed
// lines are ignored.
func parseTSV(b []byte) map[string]int {
	m := map[string]int{}
	for _, line := range strings.Split(strings.ReplaceAll(string(b), "\r", ""), "\n") {
		if strings.HasPrefix(line, "#") || line == "" {
			continue
		}
		p, c, ok := strings.Cut(line, "\t")
		if !ok {
			continue
		}
		n := 0
		if _, err := fmt.Sscanf(c, "%d", &n); err == nil {
			m[p] = n
		}
	}
	return m
}

func (r repo) baselineLoosenings(old, cur *config.Config, add func(target, what, alt string)) {
	files := map[string]bool{}
	for _, f := range r.baseFiles(".agents/baselines/") {
		files[f] = true
	}
	if out, err := scope.Git(r.root, "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", ".agents/baselines/"); err == nil {
		for _, f := range splitZ(out) {
			files[f] = true
		}
	}
	scriptsOf := map[string][]string{}
	for _, c := range []*config.Config{old, cur} {
		for id, s := range c.Scripts {
			if s.Baseline != "" {
				files[s.Baseline] = true
				scriptsOf[s.Baseline] = append(scriptsOf[s.Baseline], id)
			}
		}
	}
	names := make([]string, 0, len(files))
	for f := range files {
		names = append(names, f)
	}
	sort.Strings(names)
	for _, f := range names {
		alt := ""
		if ids := scriptsOf[f]; len(ids) > 0 {
			sort.Strings(ids)
			alt = ScriptRef(ids[0])
		}
		ob, _ := r.atBase(f)
		cb, exists := r.now(f)
		if !exists {
			cb = nil
		}
		if strings.HasSuffix(f, ".tsv") {
			om, cm := parseTSV(ob), parseTSV(cb)
			paths := make([]string, 0, len(cm))
			for p := range cm {
				paths = append(paths, p)
			}
			sort.Strings(paths)
			for _, p := range paths {
				o, had := om[p]
				if cm[p] > o {
					if had {
						add(f, fmt.Sprintf("baseline row grown %s %d -> %d", p, o, cm[p]), alt)
					} else {
						add(f, "baseline row added "+p, alt)
					}
				}
			}
			continue
		}
		on, cn := countLines(ob), countLines(cb)
		if cn > on {
			add(f, fmt.Sprintf("native baseline grew from %d to %d lines", on, cn), alt)
		}
	}
}

func countLines(b []byte) int {
	n := 0
	for _, l := range strings.Split(string(b), "\n") {
		if strings.TrimSpace(l) != "" {
			n++
		}
	}
	return n
}

// configFiles: a file named in any script's config: that changed.
func (r repo) configFiles(old, cur *config.Config, add func(target, what, alt string)) {
	owner := map[string]string{}
	for _, c := range []*config.Config{old, cur} {
		for id, s := range c.Scripts {
			for _, f := range s.Config {
				if _, ok := owner[f]; !ok || id < owner[f] {
					owner[f] = id
				}
			}
		}
	}
	names := make([]string, 0, len(owner))
	for f := range owner {
		names = append(names, f)
	}
	sort.Strings(names)
	for _, f := range names {
		ob, hadBase := r.atBase(f)
		cb, has := r.now(f)
		if hadBase != has || (has && strings.TrimRight(strings.ReplaceAll(string(ob), "\r\n", "\n"), "\n") != strings.TrimRight(strings.ReplaceAll(string(cb), "\r\n", "\n"), "\n")) {
			if !hadBase && !has {
				continue
			}
			add(f, "config file changed", ScriptRef(owner[f]))
		}
	}
}

type hookEntry struct {
	Event, Matcher, Command string
	Timeout                 int
}

func hooksOf(b []byte) map[string]bool {
	var doc struct {
		Hooks map[string][]struct {
			Matcher string `json:"matcher"`
			Hooks   []struct {
				Command string `json:"command"`
				Timeout int    `json:"timeout"`
			} `json:"hooks"`
		} `json:"hooks"`
	}
	out := map[string]bool{}
	if json.Unmarshal(b, &doc) != nil {
		return out
	}
	for ev, groups := range doc.Hooks {
		for _, g := range groups {
			for _, h := range g.Hooks {
				if strings.Contains(h.Command, "kh") && strings.Contains(h.Command, " hook ") {
					out[fmt.Sprintf("%s|%s|%s|%d", ev, g.Matcher, h.Command, h.Timeout)] = true
				}
			}
		}
	}
	return out
}

// hookEntries: a kh hook entry of .claude/settings.json removed or changed.
func (r repo) hookEntries(add func(target, what, alt string)) {
	const settings = ".claude/settings.json"
	ob, ok := r.atBase(settings)
	if !ok {
		return
	}
	cb, _ := r.now(settings)
	oh, ch := hooksOf(ob), hooksOf(cb)
	for k := range oh {
		if !ch[k] {
			add(settings, "kh hook entry removed or changed", "")
			return
		}
	}
}

func (r repo) guides(old, cur *config.Config, add func(target, what, alt string)) {
	have := map[string]bool{}
	for _, g := range cur.Guides {
		have[g] = true
	}
	for _, g := range old.Guides {
		if _, existed := r.atBase(g); !existed {
			continue
		}
		if _, exists := r.now(g); !exists {
			add(g, "guide deleted", "")
		} else if !have[g] {
			add(g, "guide removed from guides", ScriptRef("guides"))
		}
	}
}

// acceptedADRs: accepted ADRs at the base that were edited or deleted.
func (r repo) acceptedADRs(old *config.Config, add func(target, what, alt string)) int {
	dir := strings.TrimSuffix(old.ADRDir, "/")
	n := 0
	for _, f := range r.baseFiles(dir + "/") {
		ob, _ := r.atBase(f)
		if StatusOf(string(ob)) != "accepted" {
			continue
		}
		cb, exists := r.now(f)
		switch {
		case !exists:
			add(f, "accepted ADR deleted", "")
			n++
		case adrEdited(string(ob), string(cb)):
			add(f, "accepted ADR edited", "")
			n++
		}
	}
	return n
}

func (r repo) strictness(add func(target, what, alt string)) {
	out, err := scope.Git(r.root, "ls-tree", "-r", "--name-only", "-z", r.base)
	if err != nil {
		return
	}
	for _, f := range splitZ(out) {
		if !isStrictnessFile(f) {
			continue
		}
		ob, _ := r.atBase(f)
		cb, exists := r.now(f)
		for _, w := range strictnessLoosenings(f, string(ob), string(cb), exists) {
			add(f, w, "")
		}
	}
}

// addedADRs returns the ADRs added since the base (committed or not), by path.
func (r repo) addedADRs(old, cur *config.Config) map[string]string {
	dirs := map[string]bool{strings.TrimSuffix(old.ADRDir, "/"): true, strings.TrimSuffix(cur.ADRDir, "/"): true}
	paths := map[string]bool{}
	for d := range dirs {
		if out, err := scope.Git(r.root, "diff", "--name-only", "-z", "--diff-filter=A", r.base, "--", d); err == nil {
			for _, f := range splitZ(out) {
				paths[f] = true
			}
		}
		if out, err := scope.Git(r.root, "ls-files", "-z", "--others", "--exclude-standard", "--", d); err == nil {
			for _, f := range splitZ(out) {
				paths[f] = true
			}
		}
	}
	m := map[string]string{}
	for p := range paths {
		if b, ok := r.now(p); ok {
			m[p] = string(b)
		}
	}
	return m
}
