package gate

import "github.com/aether-labs-org/plugins/cli/bmax/internal/scope"

func scopeBase(changes string) scope.Base {
	switch changes {
	case "staged":
		return scope.Staged
	case "branch":
		return scope.Branch
	}
	return scope.Worktree
}
