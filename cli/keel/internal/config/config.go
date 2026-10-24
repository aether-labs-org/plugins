// Package config reads and validates .agents/keel.yaml and .agents/keel.lock.
package config

import (
	"bufio"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strings"

	"go.yaml.in/yaml/v3"
)

const (
	File     = ".agents/keel.yaml"
	LockFile = ".agents/keel.lock"

	DefaultFastCeiling = 30
	DefaultSlowCeiling = 600
)

// Config is .agents/keel.yaml, schema version 1.
type Config struct {
	Version  int      `yaml:"version"`
	Requires string   `yaml:"requires"`
	Gate     Gates    `yaml:"gate"`
	Sensors  []Sensor `yaml:"sensors"`
}

type Gates struct {
	Fast Budget `yaml:"fast"`
	Slow Budget `yaml:"slow"`
}

type Budget struct {
	CeilingSeconds int `yaml:"ceiling_seconds"`
}

// Sensor is one entry of `sensors:`. Exactly one of Exec and Adapter is set.
type Sensor struct {
	ID      string `yaml:"id"`
	Gate    string `yaml:"gate"`
	Exec    string `yaml:"exec,omitempty"`
	Adapter string `yaml:"adapter,omitempty"`
}

// Adapters lists the built-in adapters this version knows.
var Adapters = map[string]bool{"guard": true}

var (
	exactVersion = regexp.MustCompile(`^[0-9]+\.[0-9]+\.[0-9]+$`)
	// Any file name gate.sh would run: not empty, no '/', no control character (a TAB or newline would
	// corrupt line 1 of the report), not starting with '_'.
	sensorID = regexp.MustCompile(`^[^_/\x00-\x1f\x7f][^/\x00-\x1f\x7f]*$`)
)

// Ceiling returns the budget in seconds for mode fast or slow.
func (c *Config) Ceiling(mode string) int {
	if mode == "slow" {
		if c.Gate.Slow.CeilingSeconds > 0 {
			return c.Gate.Slow.CeilingSeconds
		}
		return DefaultSlowCeiling
	}
	if c.Gate.Fast.CeilingSeconds > 0 {
		return c.Gate.Fast.CeilingSeconds
	}
	return DefaultFastCeiling
}

// SensorsFor returns the sensors of one gate, in the order gate.sh ran them: by "<id>.sh", bytewise.
func (c *Config) SensorsFor(mode string) []Sensor {
	var out []Sensor
	for _, s := range c.Sensors {
		if s.Gate == mode {
			out = append(out, s)
		}
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].ID+".sh" < out[j].ID+".sh" })
	return out
}

// Find returns the sensor with the given id.
func (c *Config) Find(id string) (Sensor, bool) {
	for _, s := range c.Sensors {
		if s.ID == id {
			return s, true
		}
	}
	return Sensor{}, false
}

// Parse decodes keel.yaml strictly: unknown keys and wrong types are errors.
func Parse(data []byte) (*Config, error) {
	var c Config
	dec := yaml.NewDecoder(bytes.NewReader(data))
	dec.KnownFields(true)
	if err := dec.Decode(&c); err != nil {
		if errors.Is(err, io.EOF) {
			return nil, fmt.Errorf("%s is empty", File)
		}
		return nil, fmt.Errorf("%s: %v", File, err)
	}
	return &c, nil
}

// Load reads and validates keel.yaml under root. It does not check the pin; see CheckPin.
func Load(root string) (*Config, error) {
	data, err := os.ReadFile(filepath.Join(root, File))
	if err != nil {
		return nil, fmt.Errorf("no %s - run keel import or /keel-harness:build", File)
	}
	c, err := Parse(data)
	if err != nil {
		return nil, err
	}
	if errs := c.Validate(root); len(errs) > 0 {
		return nil, errors.Join(errs...)
	}
	return c, nil
}

// Validate returns every problem found; nil when the file is usable.
func (c *Config) Validate(root string) []error {
	var errs []error
	add := func(format string, a ...any) { errs = append(errs, fmt.Errorf(File+": "+format, a...)) }
	if c.Version != 1 {
		add("version must be 1, got %d", c.Version)
	}
	if !exactVersion.MatchString(c.Requires) {
		add("requires must be an exact version such as 0.1.0 (ranges are not accepted), got %q", c.Requires)
	}
	if c.Gate.Fast.CeilingSeconds < 0 || c.Gate.Slow.CeilingSeconds < 0 {
		add("gate ceiling_seconds must be positive")
	}
	seen := map[string]bool{}
	for i, s := range c.Sensors {
		where := fmt.Sprintf("sensors[%d] (id %q)", i, s.ID)
		if !sensorID.MatchString(s.ID) {
			add("%s: id must be a file name without '/' or control characters, not starting with '_'", where)
		}
		if seen[s.ID] {
			add("%s: duplicate id", where)
		}
		seen[s.ID] = true
		if s.Gate != "fast" && s.Gate != "slow" {
			add("%s: gate must be fast or slow, got %q", where, s.Gate)
		}
		switch {
		case (s.Exec == "") == (s.Adapter == ""):
			add("%s: set exactly one of exec and adapter", where)
		case s.Adapter != "" && !Adapters[s.Adapter]:
			add("%s: unknown adapter %q", where, s.Adapter)
		case s.Exec != "":
			clean := filepath.ToSlash(filepath.Clean(s.Exec))
			if filepath.IsAbs(s.Exec) || strings.HasPrefix(clean, "../") || clean != s.Exec || strings.HasPrefix(s.Exec, "-") {
				add("%s: exec must be a clean path inside the repository, got %q", where, s.Exec)
			} else if st, err := os.Stat(filepath.Join(root, s.Exec)); err != nil || !st.Mode().IsRegular() {
				add("%s: exec file %s does not exist", where, s.Exec)
			}
			if strings.TrimSuffix(filepath.Base(s.Exec), ".sh") != s.ID {
				add("%s: id must equal the exec file name without .sh", where)
			}
		}
	}
	// The gate cannot notice its own guard being dropped, so an installed harness must list it.
	if _, err := os.Stat(filepath.Join(root, ".agents/state.yml")); err == nil {
		g, ok := c.Find("guard")
		if !ok || g.Adapter != "guard" || g.Gate != "fast" {
			add("an installed harness (.agents/state.yml) must list the guard sensor: `- id: guard`, `gate: fast`, `adapter: guard` (D32)")
		}
	}
	// A sensor file the gate would have run but keel.yaml does not list would never run: refuse.
	for _, dir := range []string{"scripts/sensors", "scripts/sensors/slow"} {
		files, _ := filepath.Glob(filepath.Join(root, dir, "*.sh"))
		for _, f := range files {
			id := strings.TrimSuffix(filepath.Base(f), ".sh")
			if strings.HasPrefix(id, "_") || seen[id] {
				continue
			}
			if st, err := os.Stat(f); err == nil && st.Mode().IsRegular() {
				add("%s/%s.sh is not listed under sensors:, so it would never run - list it or move it to scripts/sensors/disabled/", dir, id)
			}
		}
	}
	return errs
}

// Lock is .agents/keel.lock: the pinned version and the sha256 of each platform's binary.
type Lock struct {
	Version string
	Sums    map[string]string // "linux-amd64" -> hex sha256
}

// ReadLock parses a lock file: `#` comments, then TAB-separated `version<TAB>X` and `<os>-<arch><TAB><sha256>` rows.
func ReadLock(path string) (*Lock, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("no %s - run /keel-harness:build", LockFile)
	}
	defer f.Close()
	l := &Lock{Sums: map[string]string{}}
	sc := bufio.NewScanner(f)
	for n := 1; sc.Scan(); n++ {
		line := strings.TrimRight(sc.Text(), "\r")
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		k, v, ok := strings.Cut(line, "\t")
		if !ok {
			return nil, fmt.Errorf("%s:%d: expected KEY<TAB>VALUE", LockFile, n)
		}
		if k == "version" {
			l.Version = v
		} else {
			l.Sums[k] = v
		}
	}
	return l, sc.Err()
}

// Platform is the lock key of the running binary.
func Platform() string { return runtime.GOOS + "-" + runtime.GOARCH }

// CheckPin fails unless keel.yaml, keel.lock and the running binary agree: same version, and the
// binary's sha256 equals the lock row for this platform. A mismatch is a fail, never a warning.
func CheckPin(root string, c *Config, running string) error {
	if c.Requires != running {
		return fmt.Errorf("%s requires keel %s, but this is keel %s - run /keel-harness:build to align the pin", File, c.Requires, running)
	}
	l, err := ReadLock(filepath.Join(root, LockFile))
	if err != nil {
		return err
	}
	if l.Version != c.Requires {
		return fmt.Errorf("%s pins keel %s but %s requires %s - run /keel-harness:build", LockFile, l.Version, File, c.Requires)
	}
	want, ok := l.Sums[Platform()]
	if !ok {
		return fmt.Errorf("%s has no checksum for %s", LockFile, Platform())
	}
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	got, err := FileSHA256(exe)
	if err != nil {
		return err
	}
	if got != want {
		return fmt.Errorf("this keel binary (%s) is not the build %s pins for %s - run /keel-harness:build", exe, LockFile, Platform())
	}
	return nil
}

// FileSHA256 returns the hex sha256 of a file.
func FileSHA256(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}
