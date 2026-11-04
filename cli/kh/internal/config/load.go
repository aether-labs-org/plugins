package config

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"time"

	"go.yaml.in/yaml/v3"
)

type rawGithooks struct {
	Mode      string `yaml:"mode"`
	PreCommit string `yaml:"pre-commit"`
	PrePush   string `yaml:"pre-push"`
	CommitMsg string `yaml:"commit-msg"`
}

type rawScript struct {
	Run        string         `yaml:"run"`
	Builtin    string         `yaml:"builtin"`
	Exec       string         `yaml:"exec"`
	With       map[string]any `yaml:"with"`
	Format     string         `yaml:"format"`
	Pattern    string         `yaml:"pattern"`
	Reports    string         `yaml:"reports"`
	Files      string         `yaml:"files"`
	PassFiles  *bool          `yaml:"pass_files"`
	Timeout    string         `yaml:"timeout"`
	Retries    int            `yaml:"retries"`
	Class      string         `yaml:"class"`
	Baseline   string         `yaml:"baseline"`
	Guidance   string         `yaml:"guidance"`
	Decision   string         `yaml:"decision"`
	Doc        string         `yaml:"doc"`
	Exemplar   string         `yaml:"exemplar"`
	Legacy     string         `yaml:"legacy"`
	Requires   []string       `yaml:"requires"`
	Config     []string       `yaml:"config"`
	Exceptions []Exception    `yaml:"exceptions"`
}

type rawGate struct {
	Scripts []string `yaml:"scripts"`
	Changes string   `yaml:"changes"`
	Ceiling string   `yaml:"ceiling"`
}

type rawConfig struct {
	Version   int         `yaml:"version"`
	ADRDir    string      `yaml:"adr_dir"`
	ReviewDue string      `yaml:"review_due"`
	Guides    []string    `yaml:"guides"`
	Githooks  rawGithooks `yaml:"githooks"`
	Scripts   yaml.Node   `yaml:"scripts"`
	Gates     yaml.Node   `yaml:"gates"`
}

// yamlKeys lists the yaml tag names of a struct type.
func yamlKeys(t reflect.Type) map[string]bool {
	m := map[string]bool{}
	for i := 0; i < t.NumField(); i++ {
		tag := t.Field(i).Tag.Get("yaml")
		if tag == "" || tag == "-" {
			continue
		}
		m[strings.Split(tag, ",")[0]] = true
	}
	return m
}

func checkKeys(n *yaml.Node, t reflect.Type, path string, issues *[]Issue) {
	allowed := yamlKeys(t)
	for i := 0; i+1 < len(n.Content); i += 2 {
		k := n.Content[i].Value
		if !allowed[k] {
			*issues = append(*issues, Issue{path, fmt.Sprintf("unknown key %q", k)})
		}
	}
}

func joinPath(a, b string) string {
	if a == "" {
		return b
	}
	return a + "." + b
}

// Load reads <root>/.agents/keel.yml and decodes it strictly: unknown keys and
// type errors come back as a *ValidationError. CRLF is tolerated.
func Load(root string) (*Config, error) {
	b, err := os.ReadFile(filepath.Join(root, ".agents", "keel.yml"))
	if err != nil {
		return nil, err
	}
	return Parse(b)
}

// Parse decodes the bytes of a keel.yml like Load.
func Parse(b []byte) (*Config, error) {
	var doc yaml.Node
	if err := yaml.Unmarshal(b, &doc); err != nil {
		return nil, &ValidationError{[]Issue{{"", "invalid YAML: " + strings.TrimPrefix(err.Error(), "yaml: ")}}}
	}
	c := &Config{ADRDir: DefaultADRDir, Scripts: map[string]Script{}, Gates: map[string]Gate{}}
	if doc.Kind == 0 || len(doc.Content) == 0 {
		return c, nil
	}
	top := doc.Content[0]
	if top.Kind != yaml.MappingNode {
		return nil, &ValidationError{[]Issue{{"", "the document must be a mapping"}}}
	}
	var issues []Issue
	checkKeys(top, reflect.TypeOf(rawConfig{}), "", &issues)
	var raw rawConfig
	if err := top.Decode(&raw); err != nil {
		var te *yaml.TypeError
		if errors.As(err, &te) {
			for _, m := range te.Errors {
				issues = append(issues, Issue{"", m})
			}
		} else {
			issues = append(issues, Issue{"", err.Error()})
		}
	}
	// githooks keys
	for i := 0; i+1 < len(top.Content); i += 2 {
		if top.Content[i].Value == "githooks" && top.Content[i+1].Kind == yaml.MappingNode {
			checkKeys(top.Content[i+1], reflect.TypeOf(rawGithooks{}), "githooks", &issues)
		}
	}
	c.Version = raw.Version
	if raw.ADRDir != "" {
		c.ADRDir = raw.ADRDir
	}
	c.ReviewDue = raw.ReviewDue
	c.Guides = raw.Guides
	c.Githooks = Githooks{Mode: raw.Githooks.Mode, PreCommit: raw.Githooks.PreCommit, PrePush: raw.Githooks.PrePush, CommitMsg: raw.Githooks.CommitMsg}
	loadScripts(c, &raw.Scripts, &issues)
	loadGates(c, &raw.Gates, &issues)
	if len(issues) > 0 {
		return nil, &ValidationError{issues}
	}
	if _, ok := c.Scripts[GuardID]; !ok {
		c.Scripts[GuardID] = Script{ID: GuardID, Builtin: GuardID, Timeout: DefaultTimeout}
	}
	return c, nil
}

func parseDuration(s, path string, issues *[]Issue) time.Duration {
	d, err := time.ParseDuration(s)
	if err != nil || d <= 0 {
		*issues = append(*issues, Issue{path, fmt.Sprintf("invalid duration %q (a positive duration such as 30s or 10m)", s)})
		return 0
	}
	return d
}

func loadScripts(c *Config, n *yaml.Node, issues *[]Issue) {
	if n.Kind == 0 {
		return
	}
	if n.Kind != yaml.MappingNode {
		*issues = append(*issues, Issue{"scripts", "must be a mapping of script id to command or mapping"})
		return
	}
	for i := 0; i+1 < len(n.Content); i += 2 {
		id := n.Content[i].Value
		v := n.Content[i+1]
		path := joinPath("scripts", id)
		s := Script{ID: id, Timeout: DefaultTimeout}
		switch v.Kind {
		case yaml.ScalarNode:
			s.Run = v.Value
		case yaml.MappingNode:
			checkKeys(v, reflect.TypeOf(rawScript{}), path, issues)
			var rs rawScript
			if err := v.Decode(&rs); err != nil {
				var te *yaml.TypeError
				if errors.As(err, &te) {
					for _, m := range te.Errors {
						*issues = append(*issues, Issue{path, m})
					}
				} else {
					*issues = append(*issues, Issue{path, err.Error()})
				}
				continue
			}
			s.Run, s.Builtin, s.Exec, s.With = rs.Run, rs.Builtin, rs.Exec, rs.With
			s.Format, s.Pattern, s.Reports, s.Files, s.PassFiles = rs.Format, rs.Pattern, rs.Reports, rs.Files, rs.PassFiles
			s.Retries, s.Class, s.Baseline, s.Guidance, s.Decision = rs.Retries, rs.Class, rs.Baseline, rs.Guidance, rs.Decision
			s.Doc, s.Exemplar, s.Legacy = rs.Doc, rs.Exemplar, rs.Legacy
			s.Requires, s.Config, s.Exceptions = rs.Requires, rs.Config, rs.Exceptions
			if rs.Timeout != "" {
				if d := parseDuration(rs.Timeout, path+".timeout", issues); d > 0 {
					s.Timeout = d
				}
			}
		default:
			*issues = append(*issues, Issue{path, "must be a command string or a mapping"})
			continue
		}
		c.Scripts[id] = s
		c.Order = append(c.Order, id)
	}
}

func loadGates(c *Config, n *yaml.Node, issues *[]Issue) {
	if n.Kind == 0 {
		return
	}
	if n.Kind != yaml.MappingNode {
		*issues = append(*issues, Issue{"gates", "must be a mapping of gate name to gate"})
		return
	}
	for i := 0; i+1 < len(n.Content); i += 2 {
		name := n.Content[i].Value
		v := n.Content[i+1]
		path := joinPath("gates", name)
		if v.Kind != yaml.MappingNode {
			*issues = append(*issues, Issue{path, "must be a mapping"})
			continue
		}
		checkKeys(v, reflect.TypeOf(rawGate{}), path, issues)
		var rg rawGate
		if err := v.Decode(&rg); err != nil {
			var te *yaml.TypeError
			if errors.As(err, &te) {
				for _, m := range te.Errors {
					*issues = append(*issues, Issue{path, m})
				}
			} else {
				*issues = append(*issues, Issue{path, err.Error()})
			}
			continue
		}
		g := Gate{Name: name, Scripts: rg.Scripts, Changes: rg.Changes}
		if g.Changes == "" {
			g.Changes = "worktree"
		}
		if rg.Ceiling != "" {
			g.Ceiling = parseDuration(rg.Ceiling, path+".ceiling", issues)
		}
		c.Gates[name] = g
	}
}

// LoadValid is Load followed by Validate; it returns a *ValidationError when
// anything is wrong.
func LoadValid(root string, wv WithValidator) (*Config, error) {
	c, err := Load(root)
	if err != nil {
		return nil, err
	}
	if issues := Validate(c, wv); len(issues) > 0 {
		return nil, &ValidationError{issues}
	}
	return c, nil
}
