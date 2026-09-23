#!/usr/bin/env bash
# Deterministic list-price lookup and estimate rendering (plan Tasks 5-6, decisions D6/D21).
set -uo pipefail
fail=0
check() { if [ "$2" -eq 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fail=1; fi; }
root="$(cd "$(dirname "$0")/.." && pwd)"
plugin="$root/plugins/solutions-architect"
fx="$plugin/evals/_fixtures/finops"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

SA_PLUGIN_ROOT="$plugin" python3 "$root/tests/python/test_price_lookup.py" >"$tmp/unit.log" 2>&1
check "price_lookup unit tests (8 pitfalls from H4)" $?
[ "$fail" -eq 0 ] || sed 's/^/    /' "$tmp/unit.log"

out="$(python3 "$plugin/providers/aws/scripts/price_lookup.py" --plan "$fx/plan.json" --manifest "$fx/manifest.json" \
  --map "$plugin/providers/aws/price-map.json" --cache "$fx/pricing-cache" --mode offline --out "$tmp/after.json")"
check "offline lookup on the recorded fixture runs" $?
printf '%s\n' "$out" | head -1 | grep -q $'^price-lookup\tcorrectness\tpass\t14/14 lines estimated in sa-east-1'
check "all 14 fixture lines estimated from recorded responses" $?

python3 "$plugin/providers/aws/scripts/price_lookup.py" --plan "$fx/plan.json" --manifest "$fx/manifest.json" \
  --map "$plugin/providers/aws/price-map.json" --cache "$fx/pricing-cache" --mode offline --side before \
  --out "$tmp/before.json" >/dev/null
out="$(python3 "$plugin/scripts/estimate.py" --manifest "$fx/manifest.json" --after "$tmp/after.json" \
  --before "$tmp/before.json" --out "$tmp/estimate.md")"
check "estimate renders" $?
grep -q '^# Estimativa de custo (preço de lista)' "$tmp/estimate.md"; check "estimate uses the manifest language (pt-BR)" $?
grep -q 'Faixa mensal (baixa / esperada / alta)' "$tmp/estimate.md"; check "estimate has a low/expected/high range" $?
grep -q 'Delta em relação ao estado atual: USD +' "$tmp/estimate.md"; check "estimate shows the delta" $?
grep -q 'Custo por unidade de negócio (order)' "$tmp/estimate.md"; check "estimate shows cost per business unit" $?
grep -q 'SAE1-NatGateway-Hours' "$tmp/estimate.md"; check "every line shows its usagetype" $?
exit $fail
