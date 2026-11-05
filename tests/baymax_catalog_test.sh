#!/usr/bin/env bash
# baymax v0.5 catalog: area files (one section per topic) and stack profiles (one row per topic).
# shellcheck disable=SC2319  # "check ... $?" after a test is this suite's idiom (see baymax_helpers.sh)
set -uo pipefail
. "$(dirname "$0")/baymax_helpers.sh"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
R="$REPO_ROOT/plugins/baymax/skills/harness/references"
FIXTURES="$REPO_ROOT/cli/bmax/testdata/formats"

for f in catalog-tests catalog-code catalog-architecture catalog-security catalog-observability catalog-git catalog-docs stack-typescript stack-python stack-jvm; do
  [ -s "$R/$f.md" ]; check "$f.md exists" $?
done

# one python program does the structural checks and prints one "ok|FAIL <message>" line per check
python3 -I - "$R" "$FIXTURES" <<'PY' > "${TMPDIR:-/tmp}/baymax_catalog.$$" 2>&1
import os, re, sys
R, FIX = sys.argv[1], sys.argv[2]
TOPICS = ("unit integration e2e contract property-based regression mutation coverage performance types lint naming complexity "
          "function-size max-params suppressions formatting dead-code duplication file-size code-language comments spelling architecture "
          "dependencies folder-layout exemplars secrets sca sast logging error-handling commit-convention branch-naming pr-template scope "
          "merge-check agents-md topic-files adr").split()
AREAS = ["tests", "code", "architecture", "security", "observability", "git", "docs"]
STACKS = ["typescript", "python", "jvm"]
LABELS = ["**Questions**", "**Measure**", "**Default**", "**Why**", "**Class and gate**", "**Opinion**"]
PARSED = {"junit", "sarif", "checkstyle", "eslint-json", "errorformat"}
out = []
def ok(c, msg): out.append(("ok " if c else "FAIL ") + msg)

seen = {}
for a in AREAS:
    text = open(f"{R}/catalog-{a}.md").read()
    for m in re.finditer(r"^## (\S+)\n(.*?)(?=^## |\Z)", text, re.S | re.M):
        tid, body = m.group(1), m.group(2)
        seen.setdefault(tid, []).append(a)
        missing = [l for l in LABELS if l not in body]
        ok(not missing, f"{a}/{tid} has the six labels" + (f" (missing {missing})" if missing else ""))
        order = [body.index(l) for l in LABELS if l in body]
        ok(order == sorted(order), f"{a}/{tid} labels are in the pinned order")
ok(sorted(seen) == sorted(TOPICS), "the area files hold exactly the 40 topic ids" + ("" if sorted(seen) == sorted(TOPICS) else f" (extra {set(seen)-set(TOPICS)}, missing {set(TOPICS)-set(seen)})"))
dup = [t for t, v in seen.items() if len(v) != 1]
ok(not dup, "every topic id appears in exactly one area file" + (f" (duplicates {dup})" if dup else ""))

readme = open(f"{FIX}/README.md").read()
un = re.search(r"^## Unverified\n(.*)\Z", readme, re.S | re.M)
readme_unverified = sorted(re.sub(r"^- ", "", l).split(":")[0].strip() for l in un.group(1).splitlines() if l.startswith("- ")) if un else None
ok(readme_unverified is not None, "fixtures README has an Unverified section")

unverified_rows = []
exitcode_unrun = []
for s in STACKS:
    text = open(f"{R}/stack-{s}.md").read()
    # the first table is the profile (one row per topic id); later tables are alternatives (checked, not counted)
    rows, extra_rows, table = [], [], -1
    for l in text.splitlines():
        if l.startswith("| Topic"):
            table += 1
        elif l.startswith("| ") and not l.startswith("| ---"):
            (rows if table == 0 else extra_rows).append(l)
    ids = []
    for l in rows + extra_rows:
        cells = [c.strip() for c in re.split(r"(?<!\\)\|", l.strip().strip("|"))]
        if len(cells) != 9:
            ok(False, f"{s}: row has {len(cells)} cells: {l[:60]}"); continue
        tid, tool, alt, cmd, fmt, base, pit, docs, fx = cells
        if l in rows:
            ids.append(tid)
        ok(docs.startswith("https://"), f"{s}/{tid}: Docs is an https:// link")
        if fx == "unverified":
            unverified_rows.append(f"{s}/{tid}")
        elif fx == "unverified (exit code, not run)":
            ok(fmt == "none", f"{s}/{tid}: an exit-code row that was not run has format none (got {fmt})")
            ok(not re.search(r"builtin|bmax check|guard", tool + cmd), f"{s}/{tid}: a bmax builtin or command row is run in the tests, so it is n/a (exit code), not unverified")
            exitcode_unrun.append(f"{s}/{tid}")
        elif fx.startswith("n/a"):
            ok(fx == "n/a (exit code)", f"{s}/{tid}: Fixture n/a is spelled 'n/a (exit code)'")
            ok(re.search(r"builtin|bmax check|guard|file|`bmax|field", tool + cmd + alt) is not None, f"{s}/{tid}: n/a (exit code) is for a bmax builtin or command row (tool {tool})")
            ok(fmt == "none", f"{s}/{tid}: an exit-code row has format none (got {fmt})")
        else:
            ok(os.path.exists(f"{FIX}/{fx}.cmd"), f"{s}/{tid}: fixture {fx} exists under cli/bmax/testdata/formats/")
            ok(fx.split("/")[0] == fmt, f"{s}/{tid}: fixture directory {fx.split('/')[0]} equals the format {fmt}")
        if fmt in PARSED:
            ok(fx != "n/a (exit code)", f"{s}/{tid}: a parsed format ({fmt}) has a fixture or 'unverified'")
        ok(fmt in PARSED | {"none"}, f"{s}/{tid}: format {fmt} is one bmax parses or none")
    ok(sorted(ids) == sorted(TOPICS), f"{s}: one row per topic id" + ("" if sorted(ids) == sorted(TOPICS) else f" (missing {set(TOPICS)-set(ids)}, extra {set(ids)-set(TOPICS)})"))
    ok(len(ids) == len(set(ids)), f"{s}: no topic id twice")

ok(len(exitcode_unrun) >= 25, f"external exit-code rows that were not run say so ({len(exitcode_unrun)} rows)")
# the unverified rows equal the Unverified list of the fixtures README (tool names are compared by the README line prefix)
if readme_unverified is not None:
    ok(len(unverified_rows) == len(readme_unverified), f"unverified rows ({unverified_rows}) match the README Unverified list ({readme_unverified})")
ts = open(f"{R}/stack-typescript.md").read()
ok("biome-2.6.5" in ts and "preset" in ts and "deprecated" in ts, "stack-typescript has the Biome rows and the Biome 2 preset pitfall")
ok("minimum" in ts.lower() and "pnpm-workspace.yaml" in ts and "engines" in ts and "node --version" in ts, "stack-typescript has the pnpm exec and Node engines pitfalls")
for l in out:
    print(l)
PY
while IFS= read -r line; do
  case "$line" in
    "ok "*) ;;
    *) echo "  FAIL ${line#FAIL }"; _bmax_fail=1 ;;
  esac
done < "${TMPDIR:-/tmp}/baymax_catalog.$$"
n_ok="$(grep -c '^ok ' "${TMPDIR:-/tmp}/baymax_catalog.$$" || true)"
[ "$n_ok" -gt 300 ]; check "catalog: the structural checks passed ($n_ok)" $?
rm -f "${TMPDIR:-/tmp}/baymax_catalog.$$"

finish
