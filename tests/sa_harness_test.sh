#!/usr/bin/env bash
# Offline checks of the solutions-architect eval harness and the eval case files (no model call).
set -uo pipefail
fail=0
check() { if [ "$2" -eq 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fail=1; fi; }
root="$(cd "$(dirname "$0")/.." && pwd)"
ev="$root/plugins/solutions-architect/evals"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# A fake `claude` that records any call: the harness must not call it without --execute.
mkdir "$tmp/bin"
printf '#!/bin/sh\necho called >> "%s/claude-called"\nexit 99\n' "$tmp" > "$tmp/bin/claude"
chmod +x "$tmp/bin/claude"

PATH="$tmp/bin:$PATH" python3 - "$ev" "$tmp" <<'PY'
import json, os, sys
sys.path.insert(0, os.path.join(sys.argv[1], "_harness"))
import run
ev, tmp = sys.argv[1], sys.argv[2]
ok = True
def check(name, cond):
    global ok
    print(("  ok   " if cond else "  FAIL ") + name)
    ok = ok and bool(cond)

meta, body = run.parse_frontmatter("---\ntype: regex\npattern: 'a.{1,4}b'\ntarget: { source: file, path: x/y.md }\nmin: 0\ntags: [a, b]\n---\nbody\n")
check("frontmatter: quoted pattern", meta["pattern"] == "a.{1,4}b")
check("frontmatter: inline map", meta["target"] == {"source": "file", "path": "x/y.md"})
check("frontmatter: int and list", meta["min"] == 0 and meta["tags"] == ["a", "b"])

cases = run.discover()
names = {c["name"] for c in cases}
new = {"discovery-vague-brief", "discovery-solution-first", "quick-consult", "requirements-after-discovery",
       "benchmark-fit", "discovery-candidates", "design-pushback", "review-anti-goal", "legacy-workspace",
       "reference-injection", "greenfield-discovery", "legacy-workspace-requirements"}
check("the 12 new cases exist", new <= names)
# only the types the harness evaluates; `baseline` is not implemented, so a case using it must fail here
types = {"regex", "tool_used", "tool_order", "file_exists", "llm"}
bad = [c["name"] for c in cases if not c["graders"] or any(g.get("type") not in types for g in c["graders"])]
check("every case has graders of a known type " + str(bad), not bad)
bad = [c["name"] for c in cases if c["scaffold"] and not os.access(os.path.join(c["dir"], c["scaffold"]), os.X_OK)]
check("every scaffold script exists and is executable " + str(bad), not bad)
bad = [c["name"] for c in cases if "{{file:" in c["prompt"]]
check("file placeholders resolve " + str(bad), not bad)
bad = [(c["name"], g["name"]) for c in cases for g in c["graders"]
       if g.get("type") == "llm" and not g["body"]]
check("llm graders carry a rubric " + str(bad), not bad)
tagged = {c["name"] for c in cases if "harness" in c["tags"]} | {c["name"] for c in cases if "sandbox" in c["tags"]}
check("new cases are tagged sandbox or harness", new <= tagged)

lots = run.load_lots()["lots"]
missing = [n for lot in lots for n in lot["cases"] if n not in names]
check("every case in lots.json exists " + str(missing), not missing)
in_lots = {n for lot in lots for n in lot["cases"]}
check("every new case is in a lot", new <= in_lots)
reg = {"design-discussion", "should-not-trigger", "diagram-trigger", "greenfield-web-3tier", "wa-review-qualitative"}
check("the regression cases are in a lot", reg <= in_lots)

trace = "\n".join(json.dumps(e) for e in [
    {"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Skill", "input": {"skill": "solutions-architect:discovery"}}]}},
    {"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Agent", "input": {"subagent_type": "solutions-architect:solution-challenger"}}]}},
    {"type": "assistant", "message": {"content": [{"type": "text", "text": "Hello there"}]}},
    {"type": "result", "result": "Final words", "total_cost_usd": 0.5},
])
events, calls, last = run.parse_trace(trace)
check("trace: tool calls and last message", len(calls) == 2 and last == "Final words")
w = os.path.join(tmp, "work"); os.makedirs(os.path.join(w, "architecture"))
open(os.path.join(w, "architecture", "framing.md"), "w").write("Discussion: Not held - brief\n")
created = ["architecture/framing.md"]
def g(**kw): return run.grade_script(kw, trace, calls, last, created, w)[0]
check("grader tool_used match", g(type="tool_used", tool="Skill", input_match='"skill"\\s*:\\s*"(?:solutions-architect:)?discovery"'))
check("grader tool_used max 0", not g(type="tool_used", tool="Skill", input_match="design", min=1) and
      g(type="tool_used", tool="Skill", input_match="design", min=0, max=0))
check("grader tool_order", g(type="tool_order", before="Skill", after="Agent") and not g(type="tool_order", before="Agent", after="Skill"))
check("grader regex on a file", g(type="regex", pattern="Not held", target={"source": "file", "path": "architecture/framing.md"}))
check("grader regex not_contains on files", g(type="regex", pattern="manifest", match="not_contains", target="files"))
check("grader regex on last message", g(type="regex", pattern="^Final", target="last_message"))
check("grader file_exists true and false", g(type="file_exists", path="architecture/framing.md") and
      g(type="file_exists", path="architecture/decisions/*.md", exists=False))
check("score is the weighted fraction", run.score([{"weight": 3, "passed": True}, {"weight": 1, "passed": False}]) == 0.75)
check("judge verdict parsing", run.parse_verdict("PASS\nbecause") and not run.parse_verdict("FAIL\nno") and not run.parse_verdict(""))
check("judge prompt carries rubric and material", "RUBRIC:\nabc" in run.judge_prompt({"body": "abc", "focus": "last_message"}, trace, last, created, w))

c = next(x for x in cases if x["name"] == "reference-injection")
check("file placeholder is expanded in the prompt", "INJECTED-MARKER-7f3a" in c["prompt"])
cmd = run.claude_command(c, "/p", "sonnet", 2)
check("claude command: plugin dir, stream-json, budget", "--plugin-dir" in cmd and "stream-json" in cmd and "--max-budget-usd" in cmd)
check("estimate is positive", all(run.estimate_run(x) > 0 for x in cases))
lines = run.lot_commands(next(l for l in lots if l["name"] == "sandbox-new"), [("v0.3", "/a"), ("v0.2.0", "/b")],
                         [x for x in cases if x["name"] == "quick-consult"])
reg = next(l for l in lots if l["name"] == "harness-regression")
rl = run.lot_commands(reg, [("v0.3", "/a")], [x for x in cases if x["name"] in reg["cases"]])
check("harness-regression commands grant Write, Edit and Bash", len(rl) == 2 and all("--allow-tools Write Edit Bash" in l for l in rl))
check("harness commands pin the models", all("--model sonnet" in l and "--judge-model haiku" in l for l in rl))
sol = run.lot_commands(next(l for l in lots if l["name"] == "sandbox-new"), [("v0.3", "/a")],
                       [x for x in cases if x["name"] == "discovery-solution-first"])
check("discovery-solution-first is granted Write and Edit", "--allow-tools Write Edit" in sol[0] and "--model sonnet" in sol[0] and "--judge-model haiku" in sol[0])
gr = next(x for x in cases if x["name"] == "greenfield-web-3tier")
gr["extra_tools"] = ["Write", "Edit", "Bash"]
check("--allowedTools gets the extra tools", "Bash" in run.claude_command(gr, "/p", "sonnet", 2)[-1].split(","))
mc = dict(gr, meta=dict(gr["meta"], model="opus"))
check("the case model wins over the harness default", run.claude_command(mc, "/p", "sonnet", 2)[run.claude_command(mc, "/p", "sonnet", 2).index("--model") + 1] == "opus")
check("regex flags: ^ needs the m flag", not run.grade_script({"type": "regex", "pattern": "^b", "target": "last_message"}, "", [], "a\nb", [], "/")[0]
      and run.grade_script({"type": "regex", "pattern": "^b", "flags": "m", "target": "last_message"}, "", [], "a\nb", [], "/")[0])
check("sandbox lot command has --allow-tools for quick-consult", any("--allow-tools Write Edit" in l for l in lines) and any("claude plugin eval /b" in l for l in lines))
sys.exit(0 if ok else 1)
PY
check "harness unit checks" $?

PATH="$tmp/bin:$PATH" python3 "$ev/_harness/run.py" --lot harness-new --plugin /nowhere --label t >"$tmp/dry.out" 2>&1
grep -q 'nothing was executed' "$tmp/dry.out"; check "dry run is the default and says so" $?
[ ! -e "$tmp/claude-called" ]; check "dry run never calls claude" $?
PATH="$tmp/bin:$PATH" python3 "$ev/_harness/run.py" --lot sandbox-new --commands /a /b >"$tmp/cmds.out" 2>&1
[ "$(grep -c 'claude plugin eval' "$tmp/cmds.out")" -eq 10 ]; check "sandbox-new prints 5 cases x 2 arms" $?
[ ! -e "$tmp/claude-called" ]; check "printing commands never calls claude" $?

# --execute against a fake `claude` that returns a canned stream-json (agent) or a verdict (judge):
# covers run_once, the judge error path, exit codes and the per-case summaries. No network, no cost.
fake="$tmp/fakebin"; mkdir "$fake"
cat > "$fake/claude" <<EOF
#!/bin/sh
echo "\$@" >> "$tmp/fake-args"
cat >/dev/null
case "\$*" in
  *--tools*)
    if [ -e "$tmp/judge-fail" ]; then echo "boom" >&2; exit 1; fi
    echo "PASS"; echo "fake verdict"; exit 0;;
esac
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Aurora recorded, NFR-001 cost said once."}]}}'
echo '{"type":"result","result":"Aurora recorded, NFR-001 cost said once.","total_cost_usd":0.25}'
exit 0
EOF
chmod +x "$fake/claude"
run_fake() { PATH="$fake:$PATH" python3 "$ev/_harness/run.py" --plugin /nowhere --label t --out "$tmp/res" --runs 1 --execute "$@"; }
run_fake --case design-pushback >"$tmp/x1.out" 2>&1; check "execute with a fake claude succeeds" $?
python3 - "$tmp/res/t" <<'PY'
import json, sys
d = sys.argv[1]
s = json.load(open(d + "/summary-design-pushback.json"))
g = json.load(open(d + "/design-pushback/run-1/grades.json"))
ok = s["runs"] == 1 and s["run_errors"] == 0 and s["grader_errors"] == 0 and s["cost_usd"] == 0.25
ok = ok and g["exit_code"] == 0 and any(r["type"] == "llm" and r["passed"] for r in g["results"])
sys.exit(0 if ok else 1)
PY
check "run_once records exit code, cost and judge verdicts" $?
run_fake --case discovery-vague-brief >"$tmp/x2.out" 2>&1
python3 -c '
import json, sys
a = json.load(open(sys.argv[1] + "/summary.json"))
sys.exit(0 if set(a) == {"design-pushback", "discovery-vague-brief"} else 1)' "$tmp/res/t"
check "summary.json merges cases instead of overwriting" $?
touch "$tmp/judge-fail"
run_fake --case design-pushback >"$tmp/x3.out" 2>&1
python3 - "$tmp/res/t" <<'PY'
import json, sys
d = sys.argv[1]
s = json.load(open(d + "/summary-design-pushback.json"))
g = json.load(open(d + "/design-pushback/run-1/grades.json"))
llm = [r for r in g["results"] if r["type"] == "llm"]
sys.exit(0 if s["grader_errors"] >= 1 and all(r["error"] and not r["passed"] for r in llm) else 1)
PY
check "a failing judge is an error, counted apart, not a silent FAIL" $?
rm -f "$tmp/judge-fail"
PATH="$fake:$PATH" python3 "$ev/_harness/run.py" --plugin /nowhere --label t --out "$tmp/res" --runs 1 --execute --case wa-review-qualitative --allow-tools Write Edit Bash >/dev/null 2>&1
grep -q -- '--allowedTools .*Bash' "$tmp/fake-args" || grep -q 'Bash' "$tmp/fake-args"; check "--allow-tools reaches --allowedTools" $?

if git -C "$root" cat-file -e 1d82dd9 2>/dev/null; then
  out="$(bash "$ev/_harness/prepare_baseline.sh" "$tmp/base")"
  [ -f "$out/.claude-plugin/plugin.json" ] && [ "$(jq -r .version "$out/.claude-plugin/plugin.json")" = "0.2.0" ]
  check "baseline arm is the v0.2.0 plugin" $?
  [ -f "$out/evals/discovery-vague-brief/prompt.md" ]; check "baseline arm gets the current evals" $?
else
  echo "  skip baseline arm (commit 1d82dd9 not in this clone)"
fi
exit $fail
