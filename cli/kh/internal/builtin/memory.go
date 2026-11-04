package builtin

import (
	"fmt"

	"github.com/aether-labs-org/plugins/cli/kh/internal/memory"
	"github.com/aether-labs-org/plugins/cli/kh/internal/result"
)

func init() { register(memoryBuiltin{}) }

type memoryBuiltin struct{}

type memoryParams struct{}

func (memoryBuiltin) Name() string { return "memory" }

func (memoryBuiltin) Decode(with map[string]any) (any, []string) {
	return decodeWith[memoryParams](with)
}

const memoryGuidance = "fix the memory files above: formats are in `kh schema memory`. Memory is shared: keep absolute user paths, local evidence references and secrets out of it, and commit only what another person needs."

func (memoryBuiltin) Run(ctx Context, _ any) Outcome {
	n, issues, err := memory.All(ctx.Root)
	if err != nil {
		return Outcome{Status: result.Error, Summary: err.Error()}
	}
	if len(issues) == 0 {
		if n == 0 {
			return Outcome{Status: result.Pass, Summary: "no memory files"}
		}
		return Outcome{Status: result.Pass, Summary: fmt.Sprintf("%d memory file(s) checked", n)}
	}
	var fs []result.Finding
	for _, i := range issues {
		fs = append(fs, result.Finding{File: i.File, Line: i.Line, Rule: "memory", Severity: "error", Message: i.Msg})
	}
	return Outcome{Status: result.Fail, Summary: fmt.Sprintf("%d problem(s) in %d memory file(s)", len(issues), n), Findings: fs, Guidance: memoryGuidance}
}
