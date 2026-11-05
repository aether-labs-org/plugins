package memory

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/aether-labs-org/plugins/cli/bmax/internal/config"
)

func write(t *testing.T, root, rel, body string) {
	t.Helper()
	p := filepath.Join(root, filepath.FromSlash(rel))
	os.MkdirAll(filepath.Dir(p), 0o755)
	if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

const goodPlan = "# Add billing export\n\nStatus: active\nScope: src/billing/**, docs/billing.md\n\n## Acceptance\n- [ ] export endpoint returns CSV\n- [x] tests pass\n\n## Notes\nnothing\n"

func msgs(is []Issue) string {
	var s []string
	for _, i := range is {
		s = append(s, i.File+":"+strconv.Itoa(i.Line)+": "+i.Msg)
	}
	return strings.Join(s, "\n")
}

func TestValidFilesPass(t *testing.T) {
	d := t.TempDir()
	write(t, d, ".agents/plans/billing.md", goodPlan)
	write(t, d, ".agents/progress.md", "# Progress\n\n- 2026-11-04 billing-export: done — shipped the CSV export [ADR 0004]\n- 2026-11-03 fix-login: partial — the redirect still loops\n- 2026-11-02 try-cache: abandoned — too slow\n")
	write(t, d, ".agents/lessons.md", "# Lessons\n\n## 2026-11-04 Mock the clock\nProblem: tests flaked at midnight\nSolution: inject a clock\nDestination: rule testing-clock\n\n## 2026-11-05 Other\nProblem: x\nSolution: y\nDestination: none\n")
	plans, issues, err := ActivePlans(d)
	if err != nil || len(issues) != 0 || len(plans) != 1 {
		t.Fatalf("plans=%v issues=%s err=%v", plans, msgs(issues), err)
	}
	p := plans[0]
	if p.Title != "Add billing export" || p.Status != "active" || len(p.Scope) != 2 || p.Scope[1] != "docs/billing.md" || p.Acceptance != 2 {
		t.Errorf("plan = %+v", p)
	}
	if is := CheckProgress(d); len(is) != 0 {
		t.Errorf("progress: %s", msgs(is))
	}
	if is := CheckLessons(d); len(is) != 0 {
		t.Errorf("lessons: %s", msgs(is))
	}
	if n, is, err := All(d); err != nil || n != 3 || len(is) != 0 {
		t.Errorf("All: %d %s %v", n, msgs(is), err)
	}
}

func TestNoMemoryFiles(t *testing.T) {
	d := t.TempDir()
	if n, is, err := All(d); n != 0 || len(is) != 0 || err != nil {
		t.Errorf("%d %v %v", n, is, err)
	}
}

func TestPlanViolations(t *testing.T) {
	cases := []struct{ name, body, want string }{
		{"no title", "Status: active\nScope: a\n## Acceptance\n- [ ] x\n", "line 1 must be the title"},
		{"no status", "# t\nScope: a\n## Acceptance\n- [ ] x\n", "missing a line: Status: active"},
		{"closed status", "# t\nStatus: done\nScope: a\n## Acceptance\n- [ ] x\n", "Status must be active"},
		{"no scope", "# t\nStatus: active\n## Acceptance\n- [ ] x\n", "missing a line: Scope"},
		{"empty scope", "# t\nStatus: active\nScope:   \n## Acceptance\n- [ ] x\n", "Scope must list at least one glob"},
		{"no acceptance", "# t\nStatus: active\nScope: a\n", "missing the heading: ## Acceptance"},
		{"empty acceptance", "# t\nStatus: active\nScope: a\n## Acceptance\n\n## Notes\n- [ ] not here\n", "needs at least one checklist item"},
	}
	for _, c := range cases {
		d := t.TempDir()
		write(t, d, ".agents/plans/p.md", c.body)
		plans, is, _ := ActivePlans(d)
		if len(plans) != 0 || !strings.Contains(msgs(is), c.want) {
			t.Errorf("%s: plans=%v issues=%s", c.name, plans, msgs(is))
		}
	}
}

func TestProgressViolations(t *testing.T) {
	d := t.TempDir()
	write(t, d, ".agents/progress.md", "# Progress\n- 2026-11-04 ok-slug: done — fine\nfree text line\n- 2026-11-04 Bad_Slug: done — x\n- 2026-11-04 s: finished — x\n- 2026-11-04 s: done - ascii dash\n")
	is := CheckProgress(d)
	if len(is) != 4 || is[0].Line != 3 || is[1].Line != 4 || is[2].Line != 5 || is[3].Line != 6 {
		t.Fatalf("issues: %v", is)
	}
}

func TestLessonsViolations(t *testing.T) {
	d := t.TempDir()
	write(t, d, ".agents/lessons.md", "## 2026-11-04 No destination\nProblem: a\nSolution: b\n\n## 2026-11-04 Bad destination\nProblem: a\nSolution: b\nDestination: somewhere\n\n## undated\nProblem: a\n\n## 2026-11-05 Missing problem\nSolution: b\nDestination: ADR 0004\n")
	got := msgs(CheckLessons(d))
	for _, want := range []string{"entry lacks a line: Destination", "Destination must be", "entry heading must be", "entry lacks a line: Problem"} {
		if !strings.Contains(got, want) {
			t.Errorf("missing %q in:\n%s", want, got)
		}
	}
	d = t.TempDir()
	write(t, d, ".agents/lessons.md", "## 2026-11-04 t\nProblem: a\nSolution: b\nDestination: ADR 0004\n## 2026-11-05 t2\nProblem: a\nSolution: b\nDestination: guide docs/testing.md\n")
	if is := CheckLessons(d); len(is) != 0 {
		t.Errorf("valid destinations: %s", msgs(is))
	}
}

func TestForbiddenHomePath(t *testing.T) {
	is := Forbidden("f.md", "see /home/igors/Code/x and /Users/ana/proj\nfine\n")
	if len(is) != 2 || is[0].Line != 1 {
		t.Fatalf("%v", is)
	}
}

func TestForbiddenRunRef(t *testing.T) {
	if is := Forbidden("f.md", "evidence in .agents/run/runs/x\n"); len(is) != 1 {
		t.Errorf("%v", is)
	}
}

func TestForbiddenRunID(t *testing.T) {
	if is := Forbidden("f.md", "failed in run 20261104-185124-34d0 earlier\nversion 2026-11-04 is fine\n"); len(is) != 1 || is[0].Line != 1 {
		t.Errorf("%v", is)
	}
}

func TestForbiddenToken(t *testing.T) {
	tok := "ghp_" + strings.Repeat("a1B2", 9)
	if is := Forbidden("f.md", "token "+tok+"\n"); len(is) != 1 || is[0].Msg != "secret-looking text" {
		t.Errorf("%v", is)
	}
}

func TestForbiddenAppliesToAllKinds(t *testing.T) {
	d := t.TempDir()
	write(t, d, ".agents/plans/p.md", goodPlan+"see /home/x/y\n")
	write(t, d, ".agents/progress.md", "- 2026-11-04 s: done — see .agents/run/runs/z\n")
	write(t, d, ".agents/lessons.md", "## 2026-11-04 t\nProblem: run 20261104-185124-34d0\nSolution: b\nDestination: none\n")
	_, is, _ := All(d)
	got := msgs(is)
	for _, f := range []string{".agents/plans/p.md", ".agents/progress.md", ".agents/lessons.md"} {
		if !strings.Contains(got, f) {
			t.Errorf("no issue for %s:\n%s", f, got)
		}
	}
}

func TestCRLFMemory(t *testing.T) {
	d := t.TempDir()
	write(t, d, ".agents/plans/p.md", strings.ReplaceAll(goodPlan, "\n", "\r\n"))
	write(t, d, ".agents/progress.md", "# Progress\r\n- 2026-11-04 s: done — ok\r\n")
	write(t, d, ".agents/lessons.md", "## 2026-11-04 t\r\nProblem: a\r\nSolution: b\r\nDestination: none\r\n")
	if n, is, err := All(d); err != nil || n != 3 || len(is) != 0 {
		t.Fatalf("%d %s %v", n, msgs(is), err)
	}
}

func TestSchemaMemoryMentionsFields(t *testing.T) {
	b, ok := config.Schema("memory")
	if !ok {
		t.Fatal("no memory schema")
	}
	for _, f := range []string{"Status", "Scope", "Acceptance", "Problem", "Solution", "Destination"} {
		if !strings.Contains(string(b), f) {
			t.Errorf("schema lacks %s", f)
		}
	}
}
