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

# Kubernetes shapes and embedded third-party icons.
emb="$plugin/scripts/embed_icons.py"
kallow="$plugin/providers/kubernetes/kubernetes-allowlist.txt"
cat_json="$plugin/providers/icons/catalog.json"
kman="$fx/k8s/manifest.json"
vk() { python3 "$v" "$1" --view topology --allowlist "$allow" --allowlist "$kallow" --icons "$cat_json" --manifest "$kman"; }
[ "$(grep -c '^mxgraph\.kubernetes\.[a-z_0-9]*$' "$kallow")" -ge 30 ]; check "kubernetes allowlist has 30+ icons" $?

cp "$fx/k8s/topology.drawio" "$tmp/k8s.drawio"
out="$(vk "$tmp/k8s.drawio")"; rc=$?
[ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q 'kafka: sa_icon apachekafka is not embedded - run embed_icons.py'
check "icon not embedded reported" $?

out="$(python3 "$emb" "$tmp/k8s.drawio" --catalog "$cat_json")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s\n' "$out" | head -1 | grep -q $'^drawio-icons\tcorrectness\tpass\t'
check "embed_icons passes" $?
grep -q 'image=data:image/svg+xml,' "$tmp/k8s.drawio"; check "embed_icons writes a data URI" $?
vk "$tmp/k8s.drawio" >/dev/null; check "embedded k8s + third-party view passes" $?
cp "$tmp/k8s.drawio" "$tmp/k8s-once.drawio"
python3 "$emb" "$tmp/k8s.drawio" --catalog "$cat_json" >/dev/null
cmp -s "$tmp/k8s.drawio" "$tmp/k8s-once.drawio"; check "embed_icons is idempotent" $?

sed 's#sa_icon="datadog"#sa_icon="made_up_icon"#' "$fx/k8s/topology.drawio" > "$tmp/badicon.drawio"
out="$(python3 "$emb" "$tmp/badicon.drawio" --catalog "$cat_json")"; rc=$?
[ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q 'made_up_icon is not in the icon catalog'
check "embed_icons rejects an unknown slug" $?
out="$(vk "$tmp/badicon.drawio")"
printf '%s\n' "$out" | grep -q 'sa_icon made_up_icon is not in the icon catalog'
check "validator rejects an unknown slug" $?

sed 's#shape=image;aspect=fixed#shape=image;image=https://example.com/kafka.svg;aspect=fixed#' "$tmp/k8s-once.drawio" > "$tmp/ext.drawio"
out="$(vk "$tmp/ext.drawio")"
printf '%s\n' "$out" | grep -q 'external image'
check "external image URL reported" $?

sed 's#prIcon=svc#prIcon=made_up#' "$tmp/k8s-once.drawio" > "$tmp/badk8s.drawio"
out="$(vk "$tmp/badk8s.drawio")"
printf '%s\n' "$out" | grep -q 'shape mxgraph.kubernetes.made_up is not in the Kubernetes allowlist'
check "unknown kubernetes icon reported" $?

sed 's#vertex="1" parent="eks"#vertex="1" parent="region"#' "$tmp/k8s-once.drawio" > "$tmp/ns.drawio"
out="$(vk "$tmp/ns.drawio")"
printf '%s\n' "$out" | grep -q 'ns (k8s-namespace) is not inside a k8s-cluster'
check "namespace outside a cluster reported" $?

out="$(PATH=/usr/bin:/bin bash "$plugin/scripts/export_drawio.sh" "$fx/topology.drawio" svg)"; rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q $'^drawio-export\tcorrectness\tskip\t'
check "export skips without draw.io Desktop" $?
exit $fail
