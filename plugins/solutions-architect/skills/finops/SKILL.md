---
name: finops
description: >
  Estimates what planned infrastructure costs per month - AWS list price from a Terraform plan
  (plan.json) through a deterministic Price List lookup - and makes cost a design criterion: cost
  per business unit, range, delta per change, FinOps levers. Use for any "how much will this
  cost" question about AWS resources or Terraform, or to compare design options by cost.
allowed-tools: Bash(python3 ${CLAUDE_PLUGIN_ROOT}/providers/aws/scripts/price_lookup.py *), Bash(python3 ${CLAUDE_PLUGIN_ROOT}/scripts/estimate.py *)
---

# FinOps

Prices come from the AWS Price List API through a curated map - **never from memory, and never
from a filter you improvised**: in the Phase 0 spike, 6 of 15 "natural" filters silently returned
the wrong product or tier. Every figure is **public list price** (decision D6): no discounts,
Savings Plans or Reserved Instances are applied; those appear only as recommended levers.

Delegate the lookup work to the `finops-analyst` subagent when it is available, passing it the
commands of section B with every path resolved to an absolute path; it keeps the raw pricing
output out of this conversation.

## A. Comparing options during design (`finops-compare`)

For each option in an ADR, write the resources it needs as a small plan-like list and price it
with the same lookup (step B) or, for a quick comparison, with the `aws-pricing` MCP
`get_pricing` tool - quoting the filter you used next to each number. Put the monthly total and
the cost per business unit (`references/unit-economics.md`) in the ADR's cost table.

## B. Estimating the planned infrastructure (`finops-estimate`)

1. Get the plan JSON (the `iac` skill produces it; the hook requires `-lock=false`):

   ```bash
   terraform -chdir=infra plan -lock=false -input=false -out=tf.plan
   terraform -chdir=infra show -json tf.plan > infra/plan.json
   ```

2. Make sure `manifest.components[].terraform` maps every resource address (or module prefix)
   to a component, and that `manifest.assumptions.usage` has the usage metrics the price map
   needs for usage-based lines (`references/aws/price-discovery.md` lists them). Ask the user
   for missing volumes; do not invent them.
3. Price the planned state and the current state:

   ```bash
   python3 ${CLAUDE_PLUGIN_ROOT}/providers/aws/scripts/price_lookup.py --plan infra/plan.json \
     --manifest architecture/manifest.json --map ${CLAUDE_PLUGIN_ROOT}/providers/aws/price-map.json \
     --cache architecture/finops/pricing-cache --mode record --out architecture/finops/lines.json
   python3 ${CLAUDE_PLUGIN_ROOT}/providers/aws/scripts/price_lookup.py --plan infra/plan.json \
     --manifest architecture/manifest.json --map ${CLAUDE_PLUGIN_ROOT}/providers/aws/price-map.json \
     --cache architecture/finops/pricing-cache --mode offline --side before --out architecture/finops/lines-before.json
   ```

   `--mode record` calls `aws pricing get-products` (read-only, needs `pricing:GetProducts`) and
   keeps the responses so the estimate can be reproduced offline. Without credentials use
   `--mode offline` with an existing cache.
4. Render the estimate in the manifest language:

   ```bash
   python3 ${CLAUDE_PLUGIN_ROOT}/scripts/estimate.py --manifest architecture/manifest.json \
     --after architecture/finops/lines.json --before architecture/finops/lines-before.json \
     --out architecture/finops/estimate.md
   ```

5. Read every `not-estimated` and `not-mapped` line. For each: supply the missing assumption,
   or add a price-map entry following `references/aws/price-discovery.md`, or leave it listed as
   not estimated. **Never write a number for it by hand.**
6. Append a "Levers" section to `estimate.md` from `references/levers.md`: only the levers that
   apply to the resources present, each with the condition under which it pays off.
7. Compare the total with the budget in the requirements. Over budget: say by how much and which
   ADR would have to change.

## Exit gate

`price_lookup.py` ran on the real plan; every unpriced line is listed without a value; the total
is within budget or the overrun is recorded in an ADR.
