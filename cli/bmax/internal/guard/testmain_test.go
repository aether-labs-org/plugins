package guard_test

import (
	"os"
	"testing"

	"github.com/aether-labs-org/plugins/cli/bmax/internal/gitenv"
)

// A git hook exports GIT_DIR, GIT_INDEX_FILE and friends. Tests create repositories in temporary directories and run
// git there: with those variables set every such command would act on the repository that started `go test`.
func TestMain(m *testing.M) {
	gitenv.Unset()
	os.Exit(m.Run())
}
