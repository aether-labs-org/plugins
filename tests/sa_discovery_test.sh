#!/usr/bin/env bash
# The discovery skill (v0.3): benchmark catalog shape, agent tool limits, template sections.
# Offline: it never opens a link (scripts/check_links.py without --offline does, and is not run here).
set -uo pipefail
fail=0
check() { if [ "$2" -eq 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fail=1; fi; }
root="$(cd "$(dirname "$0")/.." && pwd)"
p="$root/plugins/solutions-architect"
bm="$p/skills/discovery/references/benchmarks.md"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

python3 "$p/scripts/check_links.py" --offline "$bm" >"$tmp/out"; rc=$?
check "benchmark catalog has the expected shape" "$rc"
head -1 "$tmp/out" | grep -q $'^check-links\tcorrectness\tpass\t'; check "check_links.py line 1 follows the sensor contract" $?

python3 - "$bm" <<'PY'
import re, sys
sys.path.insert(0, sys.argv[1].rsplit("/skills/", 1)[0] + "/scripts")
import check_links
entries, problems = check_links.parse(sys.argv[1])
classes = {"Failure isolation and resilience", "Decomposition and coupling", "Data and consistency",
           "Integration and events", "Scale", "Operations and SRE", "Cost and platform", "Migration"}
ok = True
per = {}
for e in entries:
    per[e["class"]] = per.get(e["class"], 0) + 1
if set(per) != classes:
    print("    classes differ:", sorted(set(per) ^ classes)); ok = False
for c in sorted(classes):
    if per.get(c, 0) < 2:
        print(f"    class '{c}' has {per.get(c, 0)} entries, needs 2"); ok = False
anti = [e for e in entries if e["kind"] == "anti-case"]
if len(anti) < 3:
    print(f"    only {len(anti)} anti-cases, needs 3"); ok = False
late = [e["title"] for e in entries if e["accessed"] < "2026-11-05"]
if late:
    print("    stale access date:", late); ok = False
sys.exit(0 if ok else 1)
PY
check "catalog: 8 classes, 2+ entries each, 3+ anti-cases, access dates recorded" $?

! grep -q 'Summary\|summary:' "$bm"; check "catalog holds links, not summaries" $?

tools() { awk '/^tools:/{sub(/^tools: */,""); print; exit}' "$1"; }
t="$(tools "$p/agents/reference-reader.md")"
! printf '%s' "$t" | grep -Eq 'Write|Edit|Bash|NotebookEdit'; check "reference-reader has no Write, Edit or Bash" $?
printf '%s' "$t" | grep -q 'WebFetch'; check "reference-reader has WebFetch" $?
[ "$(tools "$p/agents/solution-challenger.md")" = "Read, Glob, Grep" ]; check "solution-challenger is read-only (Read, Glob, Grep)" $?
grep -q '^model: inherit$' "$p/agents/solution-challenger.md"; check "solution-challenger model inherit" $?

missing=0
for s in "Context and why now" "Goals, non-goals and anti-goals" "Current state" "Constraints and preferences" \
         "Candidates" "Discarded" "Discriminating questions" "Pre-mortem and blind spots" \
         "Independent challenge" "Discussion" "Open questions" "Workspace defaults"; do
  grep -q "^## $s" "$p/skills/discovery/assets/framing.md" || { echo "    missing section: $s"; missing=1; }
done
check "framing template has every section of the gate" $missing

[ -f "$p/skills/discovery/NOTICE.md" ] && grep -q 'MIT' "$p/skills/discovery/NOTICE.md" && grep -q 'Jesse Vincent' "$p/skills/discovery/NOTICE.md"
check "NOTICE credits the brainstorming skill (MIT, Jesse Vincent)" $?

# The plugin must work installed alone: no skill, agent or script cites the superpowers plugin.
! grep -rli 'superpowers' "$p/skills" "$p/agents" "$p/scripts" "$p/hooks" --include='*.md' --include='*.py' --include='*.json' \
  | grep -v 'skills/discovery/NOTICE.md' | grep -q .; check "only NOTICE.md mentions superpowers" $?

for f in ground blind-spots; do [ -s "$p/skills/discovery/references/$f.md" ]; check "references/$f.md exists" $?; done
exit $fail
