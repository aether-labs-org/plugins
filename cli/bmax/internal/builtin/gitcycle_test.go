package builtin

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/aether-labs-org/plugins/cli/bmax/internal/result"
)

const billingPlan = "# Billing\n\nStatus: active\nScope: src/billing/**\n\n## Acceptance\n- [ ] done\n"

func changedCtx(t *testing.T, d string, files ...string) Context {
	ctx := ctxAll(t, d)
	ctx.Files, ctx.All = files, false
	return ctx
}

func TestScopeBuiltin(t *testing.T) {
	d := newRepo(t)
	write(t, d, "seed.txt", "1")
	commit(t, d)
	// no active plan -> skip
	out := run(t, "scope", changedCtx(t, d, "src/auth/x.ts"), nil)
	if out.Status != result.Skip || out.Summary != "no active plan" {
		t.Fatalf("%s %q", out.Status, out.Summary)
	}
	write(t, d, ".agents/plans/billing.md", billingPlan)
	out = run(t, "scope", changedCtx(t, d, "src/auth/x.ts", "src/billing/a.ts", ".agents/plans/billing.md", ".agents/progress.md"), nil)
	if out.Status != result.Fail || len(out.Findings) != 1 || out.Findings[0].File != "src/auth/x.ts" {
		t.Fatalf("%s %v", out.Status, out.Findings)
	}
	if out.Guidance != "add the path to the plan's Scope or revert the change" {
		t.Errorf("guidance = %q", out.Guidance)
	}
	if out := run(t, "scope", changedCtx(t, d, "src/billing/deep/a.ts"), nil); out.Status != result.Pass {
		t.Errorf("inside scope: %s", out.Status)
	}
	// plan files alone: nothing to judge
	if out := run(t, "scope", changedCtx(t, d, ".agents/plans/billing.md", ".agents/lessons.md"), nil); out.Status != result.Skip {
		t.Errorf("only plan files: %s", out.Status)
	}
	// a malformed plan is not an active plan
	write(t, d, ".agents/plans/billing.md", "Status: active\n")
	if out := run(t, "scope", changedCtx(t, d, "src/auth/x.ts"), nil); out.Status != result.Skip {
		t.Errorf("malformed plan: %s", out.Status)
	}
	ctx := ctxAll(t, d)
	if ClassOf(Default()["scope"]) != "heuristic" || ClassOf(Default()["merge-check"]) != "correctness" || ClassOf(Default()["branch-name"]) != "heuristic" {
		t.Error("default classes")
	}
	_ = ctx
}

// remoteRepo: a clone of a bare "origin" with origin/main and a topic branch.
func remoteRepo(t *testing.T) (work, other string) {
	t.Helper()
	root, _ := filepath.EvalSymlinks(t.TempDir())
	origin := filepath.Join(root, "origin.git")
	git(t, root, "init", "-q", "--bare", "-b", "main", origin)
	work = filepath.Join(root, "work")
	git(t, root, "clone", "-q", origin, work)
	git(t, work, "checkout", "-q", "-b", "main")
	write(t, work, "shared.txt", "line one\nline two\nline three\n")
	git(t, work, "add", "-A")
	git(t, work, "commit", "-q", "-m", "seed")
	git(t, work, "push", "-q", "-u", "origin", "main")
	other = filepath.Join(root, "other")
	git(t, root, "clone", "-q", origin, other)
	t.Setenv("BMAX_GUARD_BASE", "")
	return work, other
}

func TestMergeCheck(t *testing.T) {
	work, other := remoteRepo(t)
	// someone else edits line two on main and pushes two commits
	write(t, other, "shared.txt", "line one\nTHEIRS\nline three\n")
	git(t, other, "commit", "-q", "-am", "theirs")
	write(t, other, "extra.txt", "x")
	git(t, other, "add", "-A")
	git(t, other, "commit", "-q", "-m", "more")
	git(t, other, "push", "-q", "origin", "main")
	git(t, work, "fetch", "-q", "origin")
	// no conflict yet: 2 commits behind
	out := run(t, "merge-check", ctxAll(t, work), nil)
	if out.Status != result.Pass || !strings.Contains(out.Summary, "2 commits behind origin/main") {
		t.Fatalf("clean: %s %q", out.Status, out.Summary)
	}
	// we edit the same line
	write(t, work, "shared.txt", "line one\nOURS\nline three\n")
	git(t, work, "commit", "-q", "-am", "ours")
	out = run(t, "merge-check", ctxAll(t, work), nil)
	if out.Status != result.Fail || len(out.Findings) != 1 || out.Findings[0].File != "shared.txt" || !strings.Contains(out.Summary, "2 commits behind origin/main") {
		t.Fatalf("conflict: %s %q %v", out.Status, out.Summary, out.Findings)
	}
}

func TestMergeCheckNoUpstreamAndUnborn(t *testing.T) {
	d := newRepo(t)
	if out := run(t, "merge-check", ctxAll(t, d), nil); out.Status != result.Skip || out.Summary != "no commits yet" {
		t.Errorf("unborn: %s %q", out.Status, out.Summary)
	}
	write(t, d, "a.txt", "1")
	commit(t, d)
	if out := run(t, "merge-check", ctxAll(t, d), nil); out.Status != result.Skip || out.Summary != "no upstream" {
		t.Errorf("no upstream: %s %q", out.Status, out.Summary)
	}
}

func TestMergeCheckFallsBackToOriginHead(t *testing.T) {
	work, _ := remoteRepo(t)
	git(t, work, "branch", "-q", "topic")
	git(t, work, "checkout", "-q", "topic")
	git(t, work, "remote", "set-head", "origin", "main")
	out := run(t, "merge-check", ctxAll(t, work), nil)
	if out.Status != result.Pass || !strings.Contains(out.Summary, "commits behind origin/main") {
		t.Fatalf("%s %q", out.Status, out.Summary)
	}
}

func TestCheckMessage(t *testing.T) {
	pat := `^(feat|fix|docs)(\(.+\))?!?: .+`
	cases := []struct {
		msg   string
		ok    bool
		first string
	}{
		{"feat: add x\n\nbody\n", true, "feat: add x"},
		{"fix(api)!: change\n", true, "fix(api)!: change"},
		{"wip\n", false, "wip"},
		{"# a comment\n\nfeat: after comments\n# another\n", true, "feat: after comments"},
		{"feat: crlf\r\n\r\nbody\r\n", true, "feat: crlf"},
		{"# only comments\n", false, ""},
		{"", false, ""},
	}
	for _, c := range cases {
		ok, first := CheckMessage(c.msg, pat)
		if ok != c.ok || first != c.first {
			t.Errorf("%q: ok=%v first=%q", c.msg, ok, first)
		}
	}
	if ok, _ := CheckMessage("feat: x", "("); ok {
		t.Error("invalid pattern must not match")
	}
}

func TestCommitMessageBuiltin(t *testing.T) {
	d := newRepo(t)
	with := map[string]any{"pattern": `^(feat|fix): .+`}
	if out := run(t, "commit-message", ctxAll(t, d), with); out.Status != result.Skip || out.Summary != "runs from the commit-msg hook" {
		t.Fatalf("outside the hook: %s %q", out.Status, out.Summary)
	}
	f := filepath.Join(d, "MSG")
	os.WriteFile(f, []byte("feat: good\n"), 0o644)
	ctx := ctxAll(t, d)
	ctx.CommitMsgFile = f
	if out := run(t, "commit-message", ctx, with); out.Status != result.Pass {
		t.Errorf("good: %s", out.Status)
	}
	os.WriteFile(f, []byte("oops\n"), 0o644)
	out := run(t, "commit-message", ctx, with)
	if out.Status != result.Fail || out.Findings[0].Message != "oops" {
		t.Errorf("bad: %s %v", out.Status, out.Findings)
	}
	ctx.CommitMsgFile = filepath.Join(d, "missing")
	if out := run(t, "commit-message", ctx, with); out.Status != result.Error {
		t.Errorf("unreadable: %s", out.Status)
	}
	for _, name := range []string{"commit-message", "branch-name"} {
		if _, p := Default()[name].Decode(nil); len(p) == 0 {
			t.Errorf("%s: pattern is required", name)
		}
		if _, p := Default()[name].Decode(map[string]any{"pattern": "("}); len(p) == 0 {
			t.Errorf("%s: invalid pattern accepted", name)
		}
	}
}

func TestBranchNameBuiltin(t *testing.T) {
	d := newRepo(t)
	write(t, d, "a.txt", "1")
	commit(t, d)
	git(t, d, "checkout", "-q", "-b", "feat/billing")
	with := map[string]any{"pattern": `^(feat|fix|chore)/[a-z0-9-]+$`}
	if out := run(t, "branch-name", ctxAll(t, d), with); out.Status != result.Pass {
		t.Fatalf("good: %s %q", out.Status, out.Summary)
	}
	git(t, d, "checkout", "-q", "-b", "WIP_Branch")
	if out := run(t, "branch-name", ctxAll(t, d), with); out.Status != result.Fail || !strings.Contains(out.Summary, "WIP_Branch") {
		t.Fatalf("bad: %s %q", out.Status, out.Summary)
	}
	git(t, d, "checkout", "-q", "--detach")
	if out := run(t, "branch-name", ctxAll(t, d), with); out.Status != result.Skip || out.Summary != "detached HEAD" {
		t.Fatalf("detached: %s %q", out.Status, out.Summary)
	}
}
