#!/usr/bin/env bash
# draw.io view validator and exporter (plan Task 4).
set -uo pipefail
fail=0
check() { if [ "$2" -eq 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fail=1; fi; }
root="$(cd "$(dirname "$0")/.." && pwd)"
plugin="$root/plugins/solutions-architect"
v="$plugin/scripts/validate_drawio.py"
allow="$plugin/providers/aws/aws4-allowlist.txt"
fx="$root/tests/fixtures/sa/diagram"
man="$root/tests/fixtures/sa/manifest/valid/manifest.json"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

[ "$(grep -c '^mxgraph\.aws4\.[A-Za-z0-9_]*$' "$allow")" -ge 400 ]; check "allowlist has 400+ aws4 shapes" $?
for view in topology network dataflow-security dr; do
  python3 "$v" "$fx/$view.drawio" --view "$view" --allowlist "$allow" --manifest "$man" >/dev/null
  check "valid $view view passes" $?
done

sed -e 's#parent="az-a"><mxGeometry x="20" y="200"#parent="vpc"><mxGeometry x="20" y="200"#' \
    -e 's#cidr="10.0.1.0/24"#cidr="10.1.1.0/24"#' \
    -e 's#application_load_balancer#made_up_shape#' \
    -e 's#component_id="web-alb"#component_id="ghost"#' "$fx/network.drawio" > "$tmp/network.drawio"
out="$(python3 "$v" "$tmp/network.drawio" --view network --allowlist "$allow" --manifest "$man")"; rc=$?
[ "$rc" -eq 1 ]; check "broken network view fails" $?
printf '%s\n' "$out" | grep -q 'made_up_shape is not in the AWS4 allowlist'; check "unknown shape reported" $?
printf '%s\n' "$out" | grep -q 'component_id ghost is not in the manifest'; check "orphan component reported" $?
printf '%s\n' "$out" | grep -q 'priv-a (subnet-private) is not inside a az'; check "containment reported" $?
printf '%s\n' "$out" | grep -q 'outside its VPC'; check "CIDR outside VPC reported" $?

sed 's#value="2 PostgreSQL over TLS"#value="PostgreSQL"#' "$fx/dataflow-security.drawio" > "$tmp/df.drawio"
out="$(python3 "$v" "$tmp/df.drawio" --view dataflow-security --allowlist "$allow")"
printf '%s
' "$out" | grep -q "label must start with its step number"
check "unnumbered flow reported" $?

sed 's#role="secondary"#role="standby"#' "$fx/dr.drawio" > "$tmp/dr.drawio"
out="$(python3 "$v" "$tmp/dr.drawio" --view dr --allowlist "$allow")"
printf '%s
' "$out" | grep -q "role=secondary"
check "dr view without secondary reported" $?

sed 's#component_id="orders-db"##' "$fx/topology.drawio" > "$tmp/top.drawio"
out="$(python3 "$v" "$tmp/top.drawio" --view topology --allowlist "$allow" --manifest "$man")"
printf '%s
' "$out" | grep -q "orders-db is missing from the topology view"
check "manifest component missing from topology reported" $?

printf 'not xml' > "$tmp/bad.drawio"
out="$(python3 "$v" "$tmp/bad.drawio" --view topology --allowlist "$allow")"
printf '%s\n' "$out" | head -1 | grep -q $'\tfail\t'
check "unreadable file fails cleanly" $?

out="$(PATH=/usr/bin:/bin bash "$plugin/scripts/export_drawio.sh" "$fx/topology.drawio" svg)"; rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q $'^drawio-export\tcorrectness\tskip\t'
check "export skips without draw.io Desktop" $?
exit $fail
