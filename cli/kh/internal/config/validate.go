package config

import (
	"fmt"
	"regexp"
	"sort"
	"time"
)

// Formats are the report formats kh parses.
var Formats = []string{"junit", "sarif", "checkstyle", "eslint-json", "errorformat"}

var (
	idRE    = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9_-]*$`)
	dateRE  = regexp.MustCompile(`^\d{4}-\d{2}-\d{2}$`)
	classes = map[string]bool{"": true, "security": true, "correctness": true, "heuristic": true}
)

func hasString(l []string, s string) bool {
	for _, x := range l {
		if x == s {
			return true
		}
	}
	return false
}

func validDate(s string) bool {
	if !dateRE.MatchString(s) {
		return false
	}
	_, err := time.Parse("2006-01-02", s)
	return err == nil
}

// Validate checks everything Load cannot: references between entities, value
// ranges and the `with:` blocks (through wv; nil skips builtin checks).
func Validate(c *Config, wv WithValidator) []Issue {
	var is []Issue
	add := func(path, format string, a ...any) { is = append(is, Issue{path, fmt.Sprintf(format, a...)}) }

	if c.Version != 1 {
		if c.Version == 0 {
			add("version", "required: set version: 1")
		} else {
			add("version", "unsupported version %d (this kh reads version 1)", c.Version)
		}
	}
	if c.ReviewDue != "" && !validDate(c.ReviewDue) {
		add("review_due", "must be a date YYYY-MM-DD")
	}
	switch c.Githooks.Mode {
	case "", "native", "external":
	default:
		add("githooks.mode", "githooks.mode must be native or external")
	}

	ids := append([]string(nil), c.Order...)
	if _, ok := c.Scripts[GuardID]; ok && !hasString(ids, GuardID) {
		ids = append(ids, GuardID)
	}
	for _, id := range ids {
		validateScript(c.Scripts[id], wv, add)
	}

	gnames := make([]string, 0, len(c.Gates))
	for n := range c.Gates {
		gnames = append(gnames, n)
	}
	sort.Strings(gnames)
	for _, n := range gnames {
		g := c.Gates[n]
		path := "gates." + n
		switch g.Changes {
		case "worktree", "staged", "branch":
		default:
			add(path+".changes", "changes must be worktree, staged or branch")
		}
		if len(g.Scripts) == 0 {
			add(path+".scripts", "a gate needs at least one script")
		}
		for _, sid := range g.Scripts {
			if _, ok := c.Scripts[sid]; !ok {
				add(path+".scripts", "unknown script %q", sid)
			}
		}
	}
	for _, rn := range RequiredGates {
		g, ok := c.Gates[rn]
		if !ok {
			add("gates", "required gate %q is missing", rn)
			continue
		}
		if !hasString(g.Scripts, GuardID) {
			add("gates."+rn, "gate %q must list guard", rn)
		}
	}

	gh := c.Githooks
	for _, h := range []struct{ key, val string }{{"pre-commit", gh.PreCommit}, {"pre-push", gh.PrePush}} {
		if h.val == "" {
			continue
		}
		if _, ok := c.Gates[h.val]; !ok {
			add("githooks."+h.key, "githooks.%s names unknown gate %q", h.key, h.val)
		}
	}
	if gh.CommitMsg != "" {
		if _, ok := c.Scripts[gh.CommitMsg]; !ok {
			add("githooks.commit-msg", "githooks.commit-msg names unknown script %q", gh.CommitMsg)
		}
	}
	for _, g := range c.Guides {
		if g == "" {
			add("guides", "empty path")
		}
	}
	return is
}

func validateScript(s Script, wv WithValidator, add func(path, format string, a ...any)) {
	path := "scripts." + s.ID
	if !idRE.MatchString(s.ID) {
		add(path, "invalid script id %q", s.ID)
	}
	n := 0
	for _, v := range []string{s.Run, s.Builtin, s.Exec} {
		if v != "" {
			n++
		}
	}
	if n != 1 {
		add(path, "exactly one of run, builtin, exec is required")
	}
	if s.ID == GuardID && s.Builtin != GuardID {
		add(path, "guard is reserved for the guard builtin: use builtin: guard or leave it undeclared")
	}
	if s.With != nil && s.Builtin == "" {
		add(path+".with", "with is only valid together with builtin")
	}
	if s.Builtin != "" && wv != nil {
		known, problems := wv(s.Builtin, s.With)
		if !known {
			add(path+".builtin", "unknown builtin %q", s.Builtin)
		} else {
			for _, p := range problems {
				add(path+".with", "%s", p)
			}
		}
	}
	if s.Format != "" {
		if !hasString(Formats, s.Format) {
			add(path+".format", "unknown format %q (one of %v)", s.Format, Formats)
		}
	}
	if s.Format == "errorformat" {
		if s.Pattern == "" {
			add(path+".format", "format errorformat needs pattern")
		}
	}
	if s.Pattern != "" {
		re, err := regexp.Compile(s.Pattern)
		if err != nil {
			add(path+".pattern", "invalid regular expression: %v", err)
		} else if s.Format == "errorformat" && !hasString(re.SubexpNames(), "message") && !hasString(re.SubexpNames(), "file") {
			add(path+".pattern", "needs a named group (?P<file>...) or (?P<message>...)")
		}
	}
	if s.Retries < 0 || s.Retries > MaxRetries {
		add(path+".retries", "retries must be 0-%d", MaxRetries)
	}
	if !classes[s.Class] {
		add(path+".class", "class must be security, correctness or heuristic")
	}
	if s.Baseline != "" {
		switch s.Class {
		case "security":
			add(path+".baseline", "security scripts never take a baseline")
		case "correctness":
			add(path+".baseline", "only heuristic scripts take a TSV baseline")
		}
		if s.Format == "" && s.Builtin == "" {
			add(path+".baseline", "baseline needs a format or builtin that reports files")
		}
	}
	for i, e := range s.Exceptions {
		if e.Path == "" {
			add(fmt.Sprintf("%s.exceptions[%d]", path, i), "path is required")
		}
		if !validDate(e.Until) {
			add(fmt.Sprintf("%s.exceptions[%d]", path, i), "until must be a date YYYY-MM-DD")
		}
	}
	for _, r := range s.Requires {
		if r == "" {
			add(path+".requires", "empty tool name")
		}
	}
}
