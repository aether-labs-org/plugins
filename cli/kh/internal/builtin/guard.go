package builtin

import (
	"fmt"
	"strings"

	"github.com/aether-labs-org/plugins/cli/kh/internal/guard"
	"github.com/aether-labs-org/plugins/cli/kh/internal/result"
	"github.com/aether-labs-org/plugins/cli/kh/internal/scope"
)

func init() { register(guardBuiltin{}) }

type guardBuiltin struct{}

type guardParams struct{}

func (guardBuiltin) Name() string         { return "guard" }
func (guardBuiltin) DefaultClass() string { return "security" }

func (guardBuiltin) Decode(with map[string]any) (any, []string) {
	return decodeWith[guardParams](with)
}

const guardGuidance = "undo the loosening and fix the code instead. If loosening is really the decision, add an ADR in this same change that names the script (.agents/keel.yml#<id>) or the file listed above and says why. Naming the whole .agents/keel.yml releases nothing. Editing, deleting or disabling the guard is itself a loosening."

func (guardBuiltin) Run(ctx Context, _ any) Outcome {
	if ctx.Base == "" {
		return Outcome{Status: result.Skip, Summary: "no base commit yet"}
	}
	short, err := scope.Git(ctx.Root, "rev-parse", "--short", ctx.Base)
	if err != nil {
		return Outcome{Status: result.Fail, Summary: fmt.Sprintf("KEEL_GUARD_BASE=%s is not a commit.", ctx.Base),
			Guidance: "Set KEEL_GUARD_BASE to the branch the change will merge into (e.g. origin/main), or unset it."}
	}
	sh := strings.TrimSpace(string(short))
	if _, err := scope.Git(ctx.Root, "cat-file", "-e", ctx.Base+":.agents/keel.yml"); err != nil {
		return Outcome{Status: result.Pass, Summary: fmt.Sprintf("Harness installed in this change - nothing to compare (base %s).", sh)}
	}
	violations, released, err := guard.Check(ctx.Root, ctx.Base)
	if err != nil {
		return Outcome{Status: result.Error, Summary: err.Error()}
	}
	if len(violations) == 0 {
		if len(released) > 0 {
			return Outcome{Status: result.Pass, Summary: fmt.Sprintf("%d loosening(s) since %s, each named by an ADR added in this change.", len(released), sh)}
		}
		return Outcome{Status: result.Pass, Summary: fmt.Sprintf("No harness file loosened since %s.", sh)}
	}
	var fs []result.Finding
	for _, v := range violations {
		fs = append(fs, result.Finding{File: v.Target, Rule: "guard", Severity: "error", Message: v.What})
	}
	return Outcome{Status: result.Fail, Summary: fmt.Sprintf("%d loosening(s) of the harness since %s without an ADR.", len(violations), sh), Findings: fs, Guidance: guardGuidance}
}
