# solutions-architect

Turns a coding agent into an AWS solutions architect: measurable requirements, recorded
decisions with alternatives, four validated draw.io views, a deterministic list-price estimate,
Terraform behind a gate, Markdown documentation and an independent review - all traced through
one `architecture/manifest.json`.

**Read-only against cloud accounts.** A `PreToolUse` hook denies `terraform apply`, mutating
`aws` CLI calls, `cdk deploy`, `kubectl apply` and mutating boto3 code. The plugin writes code
and documents; a person or a pipeline applies them.

## Install

```
/plugin marketplace add aether-labs-org/plugins
/plugin install solutions-architect@aether-labs
```

This installs the official `aws-core` plugin as a dependency (declared in the marketplace
entry, from `claude-plugins-official`). If `aws-core` is later uninstalled or disabled, this
plugin stops working - skills and the read-only hook alike - until it is back.
Optional: the jgraph draw.io plugin, used for ELK layout of diagrams:

```
/plugin marketplace add jgraph/drawio-mcp
/plugin install drawio@drawio
```

Always-on context cost: this plugin under 2,000 tokens; `aws-core` about 7,000.

## Prerequisites

| Tool | Used by | Required |
|---|---|---|
| Python 3.10+ | every script (standard library only) | yes |
| `uv` / `uvx` | AWS MCP Server (aws-core) and the `aws-pricing` MCP server | yes |
| AWS CLI v2 | price lookup (`pricing get-products`), IAM Access Analyzer | yes |
| Terraform 1.9+ | plan, fmt, validate | yes |
| tflint 0.64+ | IaC gate | yes |
| checkov 3.x | IaC gate | yes |
| Docker | `terraform` MCP server | recommended |
| draw.io Desktop | PNG/SVG export (snap builds only read files under `$HOME`) | optional |

A missing tool makes its sensor report `skip` with an install hint; the gate is not green until
every mandatory sensor runs.

## AWS permissions

Use a dedicated read-only role - **never root access keys**. Attach the AWS managed policies
`SecurityAudit` and `ViewOnlyAccess` (neither can read object or item contents) plus:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {"Sid": "PriceListRead", "Effect": "Allow", "Action": ["pricing:GetProducts", "pricing:GetAttributeValues", "pricing:DescribeServices", "pricing:ListPriceLists", "pricing:GetPriceListFileUrl"], "Resource": "*"},
    {"Sid": "PolicyAnalysis", "Effect": "Allow", "Action": ["access-analyzer:ValidatePolicy", "access-analyzer:CheckNoNewAccess", "access-analyzer:CheckNoPublicAccess", "access-analyzer:CheckAccessNotGranted"], "Resource": "*"},
    {"Sid": "CostRead", "Effect": "Allow", "Action": ["ce:GetCostAndUsage", "ce:GetCostForecast", "ce:GetDimensionValues"], "Resource": "*"}
  ]
}
```

This policy validates with zero findings in IAM Access Analyzer. The Terraform plan also needs
read access to the state backend.

## Skills

| Skill | Does |
|---|---|
| `architect` | runs the workflow and its gates |
| `requirements` | measurable requirements, RTO/RPO, budget, LGPD data classification |
| `design` | ADRs with alternatives, NFR-based criteria, cost per business unit, regional availability |
| `diagram` | topology, network, data-flow/security and DR views in draw.io with AWS4 icons |
| `finops` | list-price estimate from the Terraform plan, delta, unit cost, levers |
| `iac` | Terraform with pinned terraform-aws-modules and the IaC gate |
| `docs` | arc42-lite document, executive summary, risk register |
| `review` | Well-Architected review via aws-core, lenses, method checks, independent reviewer |

Prices are public list prices from the AWS Price List API (no discounts or commitments).
