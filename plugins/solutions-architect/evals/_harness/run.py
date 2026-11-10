#!/usr/bin/env python3
"""Eval harness for cases that need Bash, which `claude plugin eval` cannot give on every machine.

Reads the same case layout as `claude plugin eval` (prompt.md, case.yaml, graders/*.md), runs
each case with `claude -p` in a scratch directory, saves the stream-json trace and applies the
graders: regex, tool_used, tool_order and file_exists by script, llm by a judge `claude -p`.

Nothing here calls a model unless --execute is given. Without it the harness prints the
commands it would run (the default) or the cost estimate (--estimate).

Usage:
  run.py --plugin <dir> --label <name> [--case <name>...] [--runs N] [--model M]
         [--max-budget-usd X] [--out <dir>] [--estimate | --execute]
  run.py --lot <lot name> --plugin <dir> --label <name> [--execute]   (lots.json)
Python standard library only.
"""
import argparse
import fnmatch
import json
import math
import os
import re
import shlex
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
EVALS = os.path.dirname(HERE)
KEEP_ENV = ("PATH", "HOME", "LANG", "LC_ALL", "TERM", "TMPDIR", "SHELL", "USER", "XDG_CONFIG_HOME",
            "XDG_DATA_HOME", "XDG_CACHE_HOME", "ANTHROPIC_API_KEY", "ANTHROPIC_BASE_URL",
            "CLAUDE_CODE_OAUTH_TOKEN", "HTTPS_PROXY", "HTTP_PROXY", "NO_PROXY", "SSL_CERT_FILE")
# Cost model (see lots.json "basis"): USD per million tokens, Sonnet class.
PRICE = {"cache_read": 0.30, "cache_write": 3.75, "output": 15.0, "judge_in": 1.0, "judge_out": 5.0}


# ---------------------------------------------------------------- parsing

def _scalar(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "'\"":
        q = v[0]
        inner = v[1:-1]
        return inner.replace("''", "'") if q == "'" else inner.replace('\\"', '"')
    if re.fullmatch(r"-?\d+", v):
        return int(v)
    if v in ("true", "false"):
        return v == "true"
    return v


def _split_top(s):
    out, cur, q = [], "", None
    for ch in s:
        if q:
            cur += ch
            if ch == q:
                q = None
        elif ch in "'\"":
            q = ch
            cur += ch
        elif ch == ",":
            out.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur)
    return out


def parse_value(v):
    v = v.strip()
    if v.startswith("[") and v.endswith("]"):
        return [_scalar(x) for x in _split_top(v[1:-1])]
    if v.startswith("{") and v.endswith("}"):
        d = {}
        for part in _split_top(v[1:-1]):
            k, _, val = part.partition(":")
            d[k.strip()] = _scalar(val)
        return d
    return _scalar(v)


def parse_frontmatter(text):
    """Return (dict, body). Handles the flat `key: value` subset the eval cases use."""
    m = re.match(r"---\n(.*?)\n---\n?(.*)\Z", text, re.S)
    if not m:
        return {}, text
    meta = {}
    for line in m.group(1).splitlines():
        if not line.strip() or line.lstrip().startswith("#") or ":" not in line:
            continue
        k, _, v = line.partition(":")
        meta[k.strip()] = parse_value(v)
    return meta, m.group(2)


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def load_case(cdir):
    name = os.path.basename(cdir)
    meta, body = {}, ""
    pm = os.path.join(cdir, "prompt.md")
    if os.path.isfile(pm):
        meta, body = parse_frontmatter(read(pm))
    scaffold, tags = None, meta.get("tags", [])
    cy = os.path.join(cdir, "case.yaml")
    if os.path.isfile(cy):
        txt = read(cy)
        m = re.search(r"^\s*scaffold_script:\s*(\S+)", txt, re.M)
        scaffold = m.group(1) if m else None
        t = re.search(r"^tags:\s*(\[.*\])", txt, re.M)
        if t and not tags:
            tags = parse_value(t.group(1))
    body = re.sub(r"\{\{file:([^}]+)\}\}",
                  lambda mo: read(os.path.join(cdir, mo.group(1).strip())).rstrip("\n"), body)
    graders = []
    gdir = os.path.join(cdir, "graders")
    if os.path.isdir(gdir):
        for fn in sorted(os.listdir(gdir)):
            if fn.endswith(".md"):
                gm, gb = parse_frontmatter(read(os.path.join(gdir, fn)))
                gm["name"] = fn[:-3]
                gm["body"] = gb.strip()
                graders.append(gm)
    return {"name": name, "dir": cdir, "meta": meta, "prompt": body.strip(), "scaffold": scaffold,
            "tags": tags, "graders": graders}


def discover(names=None, evals=EVALS):
    cases = []
    for fn in sorted(os.listdir(evals)):
        cdir = os.path.join(evals, fn)
        if fn.startswith("_") or not os.path.isdir(cdir):
            continue
        if not (os.path.isfile(os.path.join(cdir, "prompt.md")) or os.path.isfile(os.path.join(cdir, "case.yaml"))):
            continue
        if names and not any(fnmatch.fnmatch(fn, n) for n in names):
            continue
        cases.append(load_case(cdir))
    return cases


# ---------------------------------------------------------------- trace and graders

def parse_trace(text):
    """stream-json lines -> (events, tool_calls[(name, json_input)], last_message)."""
    events, calls, last = [], [], ""
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            ev = json.loads(line)
        except json.JSONDecodeError:
            continue
        events.append(ev)
        if ev.get("type") == "assistant":
            for block in (ev.get("message") or {}).get("content") or []:
                if block.get("type") == "tool_use":
                    calls.append((block.get("name", ""), json.dumps(block.get("input", {}))))
                elif block.get("type") == "text" and not ev.get("parent_tool_use_id"):
                    last = block.get("text", "")
        elif ev.get("type") == "result" and isinstance(ev.get("result"), str):
            last = ev["result"]
    return events, calls, last


def target_text(spec, trace_text, last, created, workdir):
    spec = spec if spec is not None else "last_message"
    if isinstance(spec, dict) and spec.get("source") == "file":
        p = os.path.join(workdir, spec["path"])
        return read(p) if os.path.isfile(p) else ""
    if spec == "trace":
        return trace_text
    if spec == "files":
        return "\n".join(created)
    return last


def _rx_flags(g):
    """JavaScript semantics: ^ and $ match at line ends only with the m flag; i is case-insensitive."""
    f = str(g.get("flags", ""))
    return (re.I if "i" in f else 0) | (re.M if "m" in f else 0)


def grade_script(g, trace_text, calls, last, created, workdir):
    """Deterministic graders. Returns (passed, detail)."""
    t = g.get("type")
    if t == "regex":
        text = target_text(g.get("target"), trace_text, last, created, workdir)
        n = len(re.findall(g["pattern"], text, _rx_flags(g)))
        match = str(g.get("match", "contains"))
        if match == "not_contains":
            return n == 0, f"{n} match(es), wanted none"
        if match.startswith("count:"):
            return n == int(match[6:]), f"{n} match(es)"
        return n > 0, f"{n} match(es)"
    if t == "tool_used":
        rx = re.compile(g["input_match"]) if g.get("input_match") else None
        n = sum(1 for name, inp in calls if name == g["tool"] and (rx is None or rx.search(inp)))
        lo, hi = g.get("min", 1), g.get("max")
        return n >= lo and (hi is None or n <= hi), f"{n} call(s), min {lo}, max {hi}"
    if t == "tool_order":
        def idx(spec):
            if isinstance(spec, str):
                spec = {"tool": spec}
            rx = re.compile(spec["input_match"]) if spec.get("input_match") else None
            for i, (name, inp) in enumerate(calls):
                if name == spec["tool"] and (rx is None or rx.search(inp)):
                    return i
            return None
        a, b = idx(g["before"]), idx(g["after"])
        return a is not None and b is not None and a < b, f"before={a} after={b}"
    if t == "file_exists":
        hits = [f for f in created if fnmatch.fnmatch(f, g["path"])]
        want = g.get("exists", True)
        return (bool(hits) == bool(want)), f"{len(hits)} created file(s) match {g['path']}"
    return False, f"unsupported grader type {t}"


def judge_prompt(g, trace_text, last, created, workdir):
    focus = g.get("focus")
    text = target_text(focus, trace_text, last, created, workdir)
    if focus == "trace":
        lines = text.splitlines()
        if len(lines) > 24:
            lines = lines[:12] + ["..."] + lines[-12:]
        text = "\n".join(lines)
    text = text[:60000]
    return ("You are grading one run of an agent against a rubric. Read the material, then answer "
            "with exactly one word on the first line: PASS or FAIL. Then one short reason.\n\n"
            f"RUBRIC:\n{g['body']}\n\nMATERIAL:\n{text}\n")


def judge_command(model):
    return ["claude", "-p", "--model", model, "--tools", "", "--no-session-persistence",
            "--setting-sources", "project", "--output-format", "text", "--max-budget-usd", "0.10"]


def parse_verdict(out):
    first = out.strip().splitlines()[0].strip().upper() if out.strip() else ""
    return first.startswith("PASS")


def run_judge(g, trace_text, last, created, workdir, model):
    """Returns (passed, detail, errored). A judge call that exits non-zero, times out or prints
    nothing is an error vote, never a FAIL; with no 2-of-3 majority among real votes it is an error."""
    prompt = judge_prompt(g, trace_text, last, created, workdir)
    votes, errors = [], []
    for _ in range(3):
        try:
            r = subprocess.run(judge_command(model), input=prompt, capture_output=True, text=True, timeout=300)
        except subprocess.TimeoutExpired:
            errors.append("timeout")
            continue
        if r.returncode != 0 or not r.stdout.strip():
            errors.append(f"exit {r.returncode}: {(r.stderr or r.stdout).strip()[-120:]}")
            continue
        votes.append(parse_verdict(r.stdout))
        if votes.count(True) >= 2 or votes.count(False) >= 2:
            break
    if votes.count(True) >= 2:
        return True, f"votes {votes}", False
    if votes.count(False) >= 2:
        return False, f"votes {votes}", False
    return False, f"judge error: votes {votes}, errors {errors}", True


def score(results):
    """Weighted fraction passed. Graders that errored count as not passed here; summaries count them apart."""
    total = sum(r["weight"] for r in results) or 1
    return sum(r["weight"] for r in results if r["passed"]) / total


# ---------------------------------------------------------------- running

def claude_command(case, plugin, model, budget):
    """`claude -p` has no --max-turns flag in `claude --help` (v2.1.319), so the case's max_turns
    bounds only the estimate; the run is bounded by --max-budget-usd and timeout_seconds.
    The case's `model` wins over the harness default; tools granted by --allow-tools / lots.json
    (case["extra_tools"]) are added to the case's allowed_tools."""
    allowed = list(case["meta"].get("allowed_tools", [])) + list(case.get("extra_tools") or [])
    cmd = ["claude", "-p", "--plugin-dir", plugin, "--output-format", "stream-json", "--verbose",
           "--no-session-persistence", "--permission-mode", "dontAsk", "--setting-sources", "project",
           "--model", str(case["meta"].get("model") or model), "--max-budget-usd", str(budget),
           "--allowedTools", ",".join(sorted(set(allowed)))]
    return cmd


def clean_env():
    env = {k: v for k, v in os.environ.items() if k in KEEP_ENV}
    env["EVAL_HARNESS"] = "1"
    return env


def list_files(root):
    out = set()
    for d, _, fs in os.walk(root):
        for f in fs:
            out.add(os.path.relpath(os.path.join(d, f), root))
    return out


def run_once(case, plugin, model, budget, judge_model, outdir, n):
    work = tempfile.mkdtemp(prefix=f"sa-eval-{case['name']}-")
    if case["scaffold"]:
        env = clean_env()
        r = subprocess.run(["bash", os.path.join(case["dir"], case["scaffold"])], cwd=work, env=env,
                           capture_output=True, text=True, timeout=120)
        if r.returncode:
            return {"run": n, "error": "scaffold failed: " + r.stderr[-300:], "score": 0.0, "results": []}
    before = list_files(work)
    timeout = int(case["meta"].get("timeout_seconds", 600))
    try:
        r = subprocess.run(claude_command(case, plugin, model, budget), input=case["prompt"], cwd=work,
                           env=clean_env(), capture_output=True, text=True, timeout=timeout)
        trace_text, err, exit_code = r.stdout, r.stderr[-300:], r.returncode
    except subprocess.TimeoutExpired as exc:
        trace_text, err, exit_code = (exc.stdout or b"").decode() if isinstance(exc.stdout, bytes) else (exc.stdout or ""), "timeout", None
    created = sorted(list_files(work) - before)
    run_dir = os.path.join(outdir, case["name"], f"run-{n}")
    os.makedirs(run_dir, exist_ok=True)
    with open(os.path.join(run_dir, "trace.jsonl"), "w", encoding="utf-8") as fh:
        fh.write(trace_text)
    events, calls, last = parse_trace(trace_text)
    cost = next((e.get("total_cost_usd") for e in reversed(events) if e.get("type") == "result"), None)
    results = []
    for g in case["graders"]:
        errored = False
        if g.get("type") == "llm":
            ok, detail, errored = run_judge(g, trace_text, last, created, work, judge_model)
        else:
            ok, detail = grade_script(g, trace_text, calls, last, created, work)
        results.append({"grader": g["name"], "type": g.get("type"), "weight": g.get("weight", 1),
                        "passed": bool(ok), "error": errored, "detail": detail})
    out = {"run": n, "cost_usd": cost, "exit_code": exit_code, "error": err or None, "workdir": work,
           "grader_errors": sum(1 for r in results if r["error"]),
           "score": score(results), "results": results}
    with open(os.path.join(run_dir, "grades.json"), "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=2)
    return out


# ---------------------------------------------------------------- estimate

def estimate_run(case, price=PRICE):
    """Rough USD per run: half the turn cap is used, context grows 1.5k tokens a turn from 15k."""
    cap = int(case["meta"].get("max_turns", 10))
    t = max(8, math.ceil(cap / 2))
    reads = 15000 * t + 750 * t * t
    cost = reads * price["cache_read"] / 1e6 + t * 1500 * price["cache_write"] / 1e6 + t * 600 * price["output"] / 1e6
    if "Agent" in case["meta"].get("allowed_tools", []):
        cost *= 1.3
    llm = sum(1 for g in case["graders"] if g.get("type") == "llm")
    judge = llm * 3 * (8000 * price["judge_in"] + 150 * price["judge_out"]) / 1e6
    return round(cost + judge, 2)


# ---------------------------------------------------------------- lots

def load_lots():
    with open(os.path.join(HERE, "lots.json"), encoding="utf-8") as fh:
        return json.load(fh)


def lot_commands(lot, arms, cases, model="sonnet", judge_model="haiku"):
    """Commands for one lot, one arm per (label, plugin dir). Never run here; printed for approval.
    Both environments pin the same agent and judge models, the ones the estimate assumes."""
    out = []
    for label, plugin in arms:
        for c in cases:
            ceiling = max(1, math.ceil(2 * estimate_run(c) * lot["runs"]))
            tools = (lot.get("allow_tools") or {}).get(c["name"])
            if lot["environment"] == "sandbox":
                cmd = ["claude", "plugin", "eval", plugin, "--scaffold", "--ablation", "none", "--trust-plugin",
                       "--no-publish", "--runs", str(lot["runs"]), "--case", c["name"],
                       "--model", model, "--judge-model", judge_model,
                       "--max-cost-usd", str(ceiling),
                       "--json", f"{label}-{c['name']}.json"]
                if tools:
                    cmd += ["--allow-tools"] + tools
            else:
                cmd = [sys.executable, os.path.join(HERE, "run.py"), "--plugin", plugin, "--label", label,
                       "--case", c["name"], "--runs", str(lot["runs"]),
                       "--model", model, "--judge-model", judge_model,
                       "--max-budget-usd", str(max(1, math.ceil(2 * estimate_run(c))))]
                if tools:
                    cmd += ["--allow-tools"] + tools
                cmd += ["--execute"]
            out.append(" ".join(shlex.quote(x) for x in cmd))
    return out


def write_summary(outdir, name, runs):
    """One summary file per case plus an aggregate rebuilt from them, so a later case never
    overwrites an earlier one. `runs` is the list of run_once results."""
    os.makedirs(outdir, exist_ok=True)
    entry = {"scores": [r["score"] for r in runs],
             "runs": len(runs),
             "run_errors": sum(1 for r in runs if r.get("exit_code") != 0),
             "grader_errors": sum(r.get("grader_errors", 0) for r in runs),
             "cost_usd": round(sum(r.get("cost_usd") or 0 for r in runs), 4)}
    with open(os.path.join(outdir, f"summary-{name}.json"), "w", encoding="utf-8") as fh:
        json.dump(entry, fh, indent=2)
    agg = {}
    for fn in sorted(os.listdir(outdir)):
        if fn.startswith("summary-") and fn.endswith(".json"):
            with open(os.path.join(outdir, fn), encoding="utf-8") as fh:
                agg[fn[len("summary-"):-len(".json")]] = json.load(fh)
    with open(os.path.join(outdir, "summary.json"), "w", encoding="utf-8") as fh:
        json.dump(agg, fh, indent=2)
    return entry


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--plugin", help="plugin directory under test (absolute path)")
    ap.add_argument("--label", default="run", help="name of the arm, e.g. v0.2.0 or v0.3")
    ap.add_argument("--case", action="append", help="case name glob (repeatable)")
    ap.add_argument("--lot", help="a lot from lots.json (sets the cases and runs)")
    ap.add_argument("--runs", type=int)
    ap.add_argument("--model", default="sonnet")
    ap.add_argument("--judge-model", default="haiku")
    ap.add_argument("--max-budget-usd", type=float, default=3.0, help="per run ceiling")
    ap.add_argument("--out", default=os.path.join(EVALS, "results"))
    ap.add_argument("--estimate", action="store_true")
    ap.add_argument("--commands", nargs=2, metavar=("V03_DIR", "V020_DIR"),
                    help="with --lot: print the commands for both arms (nothing is executed)")
    ap.add_argument("--allow-tools", nargs="+", metavar="TOOL",
                    help="tools added to the case's allowed_tools (e.g. Write Edit Bash)")
    ap.add_argument("--execute", action="store_true", help="really call the model (costs money)")
    a = ap.parse_args(argv)

    names, runs, lot = a.case, a.runs, None
    if a.lot:
        lot = next((x for x in load_lots()["lots"] if x["name"] == a.lot), None)
        if not lot:
            sys.exit(f"unknown lot {a.lot}")
        names, runs = lot["cases"], runs or lot["runs"]
    runs = runs or 3
    cases = discover(names)
    if not cases:
        sys.exit("no case matched")
    for c in cases:
        c["extra_tools"] = list(a.allow_tools or []) + list(((lot or {}).get("allow_tools") or {}).get(c["name"], []))
    if a.commands:
        if not a.lot:
            sys.exit("--commands needs --lot")
        for line in lot_commands(lot, [("v0.3", a.commands[0]), ("v0.2.0", a.commands[1])], cases,
                                 a.model, a.judge_model):
            print(line)
        return 0
    if a.estimate or not a.execute:
        total = 0.0
        for c in cases:
            per = estimate_run(c)
            total += per * runs
            print(f"{c['name']}: ~USD {per} per run x {runs} = ~USD {round(per * runs, 2)}")
            if not a.estimate:
                if not a.plugin:
                    sys.exit("--plugin is required")
                print("  scaffold:", c["scaffold"] or "-")
                print("  command: " + " ".join(shlex.quote(x) for x in claude_command(c, a.plugin, a.model, a.max_budget_usd))
                      + "  < prompt (stdin)")
        print(f"total ~USD {round(total, 2)} (estimate, not a quote; basis in lots.json)")
        if not a.execute:
            print("dry run: nothing was executed; add --execute to run")
        return 0
    if not a.plugin:
        sys.exit("--plugin is required")
    outdir = os.path.join(a.out, a.label)
    for c in cases:
        results = []
        for n in range(1, runs + 1):
            res = run_once(c, a.plugin, a.model, a.max_budget_usd, a.judge_model, outdir, n)
            results.append(res)
            print(f"{a.label} {c['name']} run {n}: score {res['score']:.2f} cost {res.get('cost_usd')} "
                  f"exit {res.get('exit_code')} grader errors {res.get('grader_errors', 0)}")
        entry = write_summary(outdir, c["name"], results)
        print(f"{a.label} {c['name']}: {entry}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
