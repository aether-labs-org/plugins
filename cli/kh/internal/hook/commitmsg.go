package hook

import (
	"context"
	"fmt"
	"io"

	"github.com/aether-labs-org/plugins/cli/kh/internal/builtin"
	"github.com/aether-labs-org/plugins/cli/kh/internal/config"
	"github.com/aether-labs-org/plugins/cli/kh/internal/result"
	"github.com/aether-labs-org/plugins/cli/kh/internal/scope"
	"github.com/aether-labs-org/plugins/cli/kh/internal/script"
)

// CommitMsg runs the commit-message script named by githooks.commit-msg on the
// message file git passes to the hook. Exit 1 (with the pattern on stderr) when
// the message does not match; 0 when it matches or the hook is not adopted.
func CommitMsg(ctx context.Context, root, file string, errw io.Writer) int {
	cfg, err := config.LoadValid(root, builtin.Default().Validator())
	if err != nil {
		fmt.Fprintln(errw, "kh: commit-msg: "+firstLine(err.Error()))
		return 1
	}
	id := cfg.Githooks.CommitMsg
	if id == "" {
		return 0
	}
	ex := script.Exec{Root: root, Cfg: cfg, Changes: scope.Staged, CommitMsgFile: file, KhVersion: Version}
	res, err := ex.Script(ctx, id, nil)
	if err != nil {
		fmt.Fprintln(errw, "kh: commit-msg: "+err.Error())
		return 1
	}
	switch res.Status {
	case result.Pass, result.Skip:
		return 0
	}
	fmt.Fprintf(errw, "kh: commit message rejected: %s\n", res.Summary)
	if res.Guidance != "" {
		fmt.Fprintf(errw, "  %s\n", res.Guidance)
	}
	for _, f := range res.Findings {
		fmt.Fprintf(errw, "  first line: %q\n", f.Message)
	}
	return 1
}
