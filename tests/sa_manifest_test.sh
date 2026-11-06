#!/usr/bin/env bash
# Workspace manifest validator (plan Task 2).
set -uo pipefail
fail=0
check() { if [ "$2" -eq 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fail=1; fi; }
root="$(cd "$(dirname "$0")/.." && pwd)"
v="$root/plugins/solutions-architect/scripts/validate_manifest.py"
fx="$root/tests/fixtures/sa/manifest/valid"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

out="$(python3 "$v" "$fx/manifest.json")"; rc=$?
check "valid manifest passes" "$rc"
printf '%s\n' "$out" | head -1 | grep -q $'^manifest\tcorrectness\tpass\t'; check "line 1 follows the sensor contract" $?

cp -r "$fx/." "$tmp/"
python3 - "$tmp/manifest.json" <<'PY'
import json, sys
p = sys.argv[1]; m = json.load(open(p))
m["decisions"][0]["addresses"] = ["NFR-009"]
m["components"][0]["decision"] = "ADR-0002"
m["suppressions"][0]["justification"] = "pinned by version, trust me"
json.dump(m, open(p, "w"))
PY
out="$(python3 "$v" "$tmp/manifest.json")"; rc=$?
[ "$rc" -eq 1 ]; check "broken manifest fails" $?
printf '%s\n' "$out" | grep -q 'addresses unknown requirement NFR-009'; check "unknown requirement reported" $?
printf '%s\n' "$out" | grep -q 'references unknown decision ADR-0002'; check "unknown decision reported" $?
printf '%s\n' "$out" | grep -q 'CKV_TF_1 may only be suppressed with the D22 justification'; check "D22 rule enforced" $?
printf '%s\n' "$out" | grep -q '^  guidance: '; check "failure carries guidance" $?

cp -r "$fx/." "$tmp/"
python3 - "$tmp/manifest.json" <<'PY'
import json, sys
p = sys.argv[1]; m = json.load(open(p))
m["requirements"].append({"id": "NFR-002", "kind": "nfr", "text": "Availability", "measure": "99.9% monthly"})
json.dump(m, open(p, "w"))
PY
python3 "$v" "$tmp/manifest.json" | grep -q 'warning: NFRs without an accepted ADR: NFR-002'; check "uncovered NFR is a warning" $?
python3 "$v" "$tmp/manifest.json" --strict-trace >/dev/null; [ $? -eq 1 ]; check "--strict-trace fails on uncovered NFR" $?

# v0.3: stage 0 (discovery) and the framing.md check (D34).
dfx="$root/tests/fixtures/sa/manifest/discovery"
python3 "$v" "$dfx/manifest.json" >/dev/null; check "gates.discovery pass with framing.md validates" $?
python3 "$v" "$fx/manifest.json" >/dev/null; check "a v0.2 manifest without gates.discovery still validates" $?

rm -rf "$tmp" && mkdir "$tmp" && cp -r "$dfx/." "$tmp/" && rm "$tmp/framing.md"
out="$(python3 "$v" "$tmp/manifest.json")"; rc=$?
[ "$rc" -eq 1 ]; check "gates.discovery pass without framing.md fails" $?
printf '%s\n' "$out" | grep -q 'framing.md does not exist'; check "missing framing.md is reported" $?

python3 - "$tmp/manifest.json" <<'PY'
import json, sys
p = sys.argv[1]; m = json.load(open(p))
m["gates"]["discovery"] = {"status": "skipped", "at": "2026-11-06", "notes": "workspace created before v0.3"}
json.dump(m, open(p, "w"))
PY
python3 "$v" "$tmp/manifest.json" >/dev/null; check "gates.discovery skipped needs no framing.md" $?

python3 - "$tmp/manifest.json" <<'PY'
import json, sys
p = sys.argv[1]; m = json.load(open(p))
m["stage"] = "discovery"; m["gates"] = {}
json.dump(m, open(p, "w"))
PY
python3 "$v" "$tmp/manifest.json" >/dev/null; check "stage discovery is accepted" $?
exit $fail
