// Package importer writes .agents/keel.yaml (and .agents/keel.lock) from a bash-engine install:
// the sensors gate.sh would run, in its order, and the budgets of .agents/gate.env.
package importer

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"github.com/aether-labs-org/plugins/cli/kh/internal/config"
)

// Native maps a bash sensor file name to the built-in adapter that replaces it in this version.
var Native = map[string]string{"guard": "guard"}

// ceiling reads KEY like gate.sh: CR removed, first `^KEY=<digits>` line, else def.
func ceiling(root, key string, def int) int {
	b, err := os.ReadFile(filepath.Join(root, ".agents/gate.env"))
	if err != nil {
		return def
	}
	re := regexp.MustCompile(`^` + key + `=([0-9]+)`)
	for _, l := range strings.Split(strings.ReplaceAll(string(b), "\r", ""), "\n") {
		if m := re.FindStringSubmatch(l); m != nil {
			if n, err := strconv.Atoi(m[1]); err == nil {
				return n
			}
		}
	}
	return def
}

// discover lists the sensors gate.sh would run from dir: top-level *.sh files not starting with `_`.
func discover(root, dir, gate string) []config.Sensor {
	files, _ := filepath.Glob(filepath.Join(root, dir, "*.sh"))
	sort.Strings(files)
	var out []config.Sensor
	for _, f := range files {
		id := strings.TrimSuffix(filepath.Base(f), ".sh")
		if strings.HasPrefix(id, "_") {
			continue
		}
		if st, err := os.Stat(f); err != nil || !st.Mode().IsRegular() {
			continue
		}
		s := config.Sensor{ID: id, Gate: gate, Exec: dir + "/" + id + ".sh"}
		if a, ok := Native[id]; ok && gate == "fast" {
			s.Exec, s.Adapter = "", a
		}
		out = append(out, s)
	}
	return out
}

// Render writes c in keel's canonical layout, so a diff of keel.yaml stays readable.
func Render(c *config.Config) string {
	var b strings.Builder
	b.WriteString("# Managed by keel. The sensors and budgets of this repository's gates; check with `kh validate`.\n")
	fmt.Fprintf(&b, "version: %d\nrequires: %s\ngate:\n  fast:\n    ceiling_seconds: %d\n  slow:\n    ceiling_seconds: %d\n",
		c.Version, c.Requires, c.Ceiling("fast"), c.Ceiling("slow"))
	if len(c.Sensors) == 0 {
		b.WriteString("sensors: []\n")
		return b.String()
	}
	b.WriteString("sensors:\n")
	for _, s := range c.Sensors {
		fmt.Fprintf(&b, "  - id: %s\n    gate: %s\n", s.ID, s.Gate)
		if s.Adapter != "" {
			fmt.Fprintf(&b, "    adapter: %s\n", s.Adapter)
		} else {
			fmt.Fprintf(&b, "    exec: %s\n", s.Exec)
		}
	}
	return b.String()
}

// ReadSums parses `sha256sum` output whose names are `<os>-<arch>/kh` (as in engine/SHA256SUMS).
func ReadSums(path string) (map[string]string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	sums := map[string]string{}
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		fields := strings.Fields(sc.Text())
		if len(fields) != 2 {
			continue
		}
		name := strings.TrimPrefix(fields[1], "*")
		if plat, ok := strings.CutSuffix(name, "/kh"); ok {
			sums[plat] = fields[0]
		}
	}
	if len(sums) == 0 {
		return nil, fmt.Errorf("%s has no <os>-<arch>/kh rows", path)
	}
	return sums, sc.Err()
}

// RenderLock writes the lock file for version with the given checksums, platforms sorted.
func RenderLock(version string, sums map[string]string) string {
	var b strings.Builder
	b.WriteString("# Managed by keel. The pinned kh build; written by kh import --sums or /keel-harness:build, never by hand.\n")
	fmt.Fprintf(&b, "version\t%s\n", version)
	plats := make([]string, 0, len(sums))
	for p := range sums {
		plats = append(plats, p)
	}
	sort.Strings(plats)
	for _, p := range plats {
		fmt.Fprintf(&b, "%s\t%s\n", p, sums[p])
	}
	return b.String()
}

// Import builds the config of a bash-engine install under root for kh version.
func Import(root, version string) *config.Config {
	c := &config.Config{Version: 1, Requires: version}
	c.Gate.Fast.CeilingSeconds = ceiling(root, "CEILING_SECONDS", config.DefaultFastCeiling)
	c.Gate.Slow.CeilingSeconds = ceiling(root, "SLOW_CEILING_SECONDS", config.DefaultSlowCeiling)
	c.Sensors = append(discover(root, "scripts/sensors", "fast"), discover(root, "scripts/sensors/slow", "slow")...)
	if _, err := os.Stat(filepath.Join(root, ".agents/state.yml")); err == nil {
		if _, ok := c.Find("guard"); !ok {
			c.Sensors = append([]config.Sensor{{ID: "guard", Gate: "fast", Adapter: "guard"}}, c.Sensors...)
			sort.SliceStable(c.Sensors, func(i, j int) bool {
				return c.Sensors[i].Gate == "fast" && c.Sensors[j].Gate == "slow" ||
					c.Sensors[i].Gate == c.Sensors[j].Gate && c.Sensors[i].ID+".sh" < c.Sensors[j].ID+".sh"
			})
		}
	}
	return c
}
