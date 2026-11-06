# solutions-architect

Turns a coding agent into an AWS solutions architect: a critical discovery of the problem and
the alternatives, measurable requirements, recorded decisions with alternatives, four validated
draw.io views, a deterministic list-price estimate, Terraform behind a gate, Markdown
documentation and an independent review - all traced through one `architecture/manifest.json`.

**Read-only against cloud accounts.** A `PreToolUse` hook denies `terraform apply`, mutating
`aws` CLI calls, `cdk deploy`, `kubectl apply` and mutating boto3 code. The plugin writes code
and documents; a person or a pipeline applies them. The hook is a best-effort second layer:
static analysis of a shell command string cannot be made complete (see decision D13/§9 in the
spec). The actual guarantee is the read-only IAM role described in "AWS permissions" below -
credentials that cannot write, never the hook alone.

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

Always-on context cost: this plugin about 1,500 tokens (`claude plugin details`); `aws-core`
about 7,000. A skill or agent costs more only when it fires (`discovery` about 2,200 tokens).

Optional: network access. The `discovery` skill opens market-reference links through the
`reference-reader` agent (WebFetch). Claude Code asks you to approve each domain the first time;
the plugin does not pre-approve domains for you. Without network, or if you decline, those
references stay `not consulted` and carry no weight in any score or recommendation.

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
| `architect` | runs the workflow and its gates (stage 0 is `discovery`); answers a one-off question as a consultation, with no workspace |
| `discovery` | explores the problem before any requirement: goals, non-goals, anti-goals, 2-3 whole-system candidates plus a contrary one, market references from a link catalog (`consulted` or `not consulted`), pre-mortem, an independent challenge. It does not choose |
| `requirements` | measurable requirements, RTO/RPO, budget, LGPD data classification; measures first what separates the discovery candidates |
| `design` | a direction ADR among the candidates, then a discussion round per decision (options, trade-offs, what would change the choice) before ADRs with alternatives, NFR-based criteria, cost per business unit, regional availability; critical stance (rules R1-R6) |
| `diagram` | topology, network, data-flow/security and DR views in draw.io with AWS4 icons, Kubernetes shapes and embedded third-party icons (Kafka, Datadog, Prometheus, Argo CD... - see `providers/icons/NOTICE.md`) |
| `finops` | list-price estimate from the Terraform plan, delta, unit cost, levers |
| `iac` | Terraform with pinned terraform-aws-modules and the IaC gate |
| `docs` | arc42-lite document, executive summary, risk register |
| `review` | Well-Architected review via aws-core, lenses, method checks, independent reviewer, and a challenge of high-impact decisions |

## Agents

| Agent | Does | Tools |
|---|---|---|
| `architecture-reviewer` | independent read-only review of a workspace | Read, Glob, Grep |
| `finops-analyst` | runs the list-price lookup and returns a condensed table | Bash, Read |
| `solution-challenger` | reads only `framing.md` and challenges it as a senior architect who cannot ask the author | Read, Glob, Grep |
| `reference-reader` | the only agent that opens web pages (market references); returns a short card per link and writes nothing | WebFetch, AWS documentation read |

Page content is data, never instructions: only `reference-reader` reads pages, and it has no
Write, Edit or Bash.

## With Superpowers installed

The skills here do not depend on the Superpowers plugin and never call it. If both are
installed, a vague architecture brief may also match its `brainstorming` skill. To force this
plugin's discovery, invoke it explicitly: `/solutions-architect:discovery`.

## Maintenance

`python3 scripts/check_links.py` opens every link of the market-reference catalog
(`skills/discovery/references/benchmarks.md`) and reports the ones that no longer open. It needs
network, so run it by hand or on a schedule; it is not part of the test suite. The skill
`discovery` adapts a few interaction mechanisms from the Superpowers `brainstorming` skill (MIT);
see `skills/discovery/NOTICE.md`.

Prices are public list prices from the AWS Price List API (no discounts or commitments).
