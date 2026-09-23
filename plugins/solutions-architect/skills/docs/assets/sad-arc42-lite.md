# <Solution name> - Solution Architecture

| | |
|---|---|
| Status | <stage and gate summary from the manifest> |
| Region(s) | |
| Last updated | YYYY-MM-DD |

## 1. Goals and requirements
Link: [requirements](requirements.md). Top quality goals (NFR ids and measures):

## 2. Constraints
CON ids and what each rules out.

## 3. Context
![Context](diagrams/context.mmd) - who uses the system and what it depends on.

## 4. Solution strategy
Three to five sentences: the key decisions and why, each with its ADR link.

## 5. Building blocks
![Topology](diagrams/topology.drawio.svg) - one line per component (manifest id, service, ADR).

## 6. Runtime view
![Data flow and security](diagrams/dataflow-security.drawio.svg) - the numbered flows.

## 7. Deployment and network
![Network](diagrams/network.drawio.svg) - accounts, VPC, subnets, egress; IaC in `<iac_path>/`.

## 8. Cross-cutting concepts
Security and LGPD, observability, resilience and DR (![DR](diagrams/dr.drawio.svg)), tagging.

## 9. Decisions
| ADR | Title | Status |
|---|---|---|

## 10. Quality and cost
Link: [estimate](finops/estimate.md). Monthly list price, cost per business unit, IaC gate result.

## 11. Risks and technical debt
Link: [risks](risks.md).

## 12. Glossary
