// Package evidence owns execution IDs, the run directory, meta.json and
// retention. Evidence lives in <root>/.agents/run/runs/<id>/.
package evidence

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"time"

	"github.com/aether-labs-org/plugins/cli/kh/internal/result"
)

// Retention limits.
const (
	MaxRuns        = 50
	MaxBytes int64 = 200 << 20
)

// ErrNoRun is returned when a run does not exist or its id is malformed.
var ErrNoRun = errors.New("no such run")

var idRe = regexp.MustCompile(`^\d{8}-\d{6}-[0-9a-f]{4}$`)

// randReader feeds NewID in Create; tests replace it.
var randReader io.Reader = rand.Reader

// Run is one evidence directory.
type Run struct {
	Root, ID, Dir string // Dir is absolute
}

// LogPath is the path of output.log.
func (r Run) LogPath() string { return filepath.Join(r.Dir, "output.log") }

func runsDir(root string) string { return filepath.Join(root, ".agents", "run", "runs") }

// NewID returns "YYYYMMDD-HHMMSS-xxxx" (UTC, 4 lowercase hex digits from rnd).
func NewID(now time.Time, rnd io.Reader) string {
	var b [2]byte
	if _, err := io.ReadFull(rnd, b[:]); err != nil {
		// Fall back to the clock so that an ID is always produced.
		n := now.UnixNano()
		b[0], b[1] = byte(n>>8), byte(n)
	}
	return now.UTC().Format("20060102-150405") + "-" + hex.EncodeToString(b[:])
}

// Create makes the run directory exclusively, picking another ID on collision.
func Create(root string, now time.Time) (Run, error) {
	base := runsDir(root)
	if err := os.MkdirAll(base, 0o700); err != nil {
		return Run{}, err
	}
	for i := 0; i < 10; i++ {
		id := NewID(now, randReader)
		dir := filepath.Join(base, id)
		err := os.Mkdir(dir, 0o700)
		if err == nil {
			return Run{Root: root, ID: id, Dir: dir}, nil
		}
		if !errors.Is(err, fs.ErrExist) {
			return Run{}, err
		}
	}
	return Run{}, errors.New("cannot allocate a unique run id")
}

// WriteMeta writes meta.json atomically (temp file + rename).
func (r Run) WriteMeta(res result.Result) error {
	b, err := json.MarshalIndent(res, "", "  ")
	if err != nil {
		return err
	}
	b = append(b, '\n')
	tmp, err := os.CreateTemp(r.Dir, ".meta-*.tmp")
	if err != nil {
		return err
	}
	name := tmp.Name()
	if _, err := tmp.Write(b); err != nil {
		tmp.Close()
		os.Remove(name)
		return err
	}
	if err := tmp.Close(); err != nil {
		os.Remove(name)
		return err
	}
	if err := os.Rename(name, filepath.Join(r.Dir, "meta.json")); err != nil {
		os.Remove(name)
		return err
	}
	return nil
}

// Load reads meta.json of a run. ErrNoRun when absent or id is malformed.
func Load(root, id string) (result.Result, error) {
	var res result.Result
	if !idRe.MatchString(id) {
		return res, fmt.Errorf("%w: %s", ErrNoRun, id)
	}
	b, err := os.ReadFile(filepath.Join(runsDir(root), id, "meta.json"))
	if err != nil {
		if errors.Is(err, fs.ErrNotExist) {
			return res, fmt.Errorf("%w: %s", ErrNoRun, id)
		}
		return res, err
	}
	if err := json.Unmarshal(b, &res); err != nil {
		return res, fmt.Errorf("meta.json of run %s: %w", id, err)
	}
	return res, nil
}

type entry struct {
	id   string
	size int64
}

func dirSize(dir string) int64 {
	var n int64
	_ = filepath.WalkDir(dir, func(_ string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}
		if info, err := d.Info(); err == nil {
			n += info.Size()
		}
		return nil
	})
	return n
}

// Prune removes the oldest runs until at most maxRuns remain and they use at
// most maxBytes. It never removes current and ignores names that are not IDs.
func Prune(root, current string, maxRuns int, maxBytes int64) error {
	base := runsDir(root)
	des, err := os.ReadDir(base)
	if err != nil {
		if errors.Is(err, fs.ErrNotExist) {
			return nil
		}
		return err
	}
	var runs []entry
	var total int64
	for _, d := range des {
		if !d.IsDir() || !idRe.MatchString(d.Name()) {
			continue
		}
		e := entry{id: d.Name(), size: dirSize(filepath.Join(base, d.Name()))}
		runs = append(runs, e)
		total += e.size
	}
	sort.Slice(runs, func(i, j int) bool { return runs[i].id < runs[j].id })
	count := len(runs)
	var firstErr error
	for _, e := range runs {
		if count <= maxRuns && total <= maxBytes {
			break
		}
		if e.id == current {
			continue
		}
		if err := os.RemoveAll(filepath.Join(base, e.id)); err != nil {
			if firstErr == nil {
				firstErr = err
			}
			continue
		}
		count--
		total -= e.size
	}
	return firstErr
}
