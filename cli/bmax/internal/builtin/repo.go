package builtin

import (
	"os"
	"path/filepath"
)

func readRepoFile(root, rel string) ([]byte, error) {
	return os.ReadFile(filepath.Join(root, filepath.FromSlash(rel)))
}
