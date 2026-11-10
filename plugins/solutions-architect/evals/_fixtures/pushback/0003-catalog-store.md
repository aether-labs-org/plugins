# ADR-0003: Data store for the product catalog

- Status: proposed
- Date: 2026-11-06
- Addresses: NFR-001, NFR-003
- Supersedes: -
- Impact: high

## Context and problem
The catalog is read on every order (about 200 reads per second at peak, single-key lookups) and
changes a few hundred times a day. NFR-001 asks for p95 < 300 ms on POST /orders; NFR-003 asks for
RTO 1 h and RPO 15 min.

## Decision drivers
| Criterion | Serves | Weight |
|---|---|---|
| Read latency | NFR-001 | 40 |
| Recovery | NFR-003 | 30 |
| Cost per order | budget | 20 |
| Operational effort | team | 10 |

## Options considered
| Option | Regional availability (sa-east-1, us-east-1) | Knock-out? |
|---|---|---|
| Amazon DynamoDB | available in both | no |
| Amazon Aurora PostgreSQL | available in both | no |

## Trade-offs
| Option | Gains | Gives up |
|---|---|---|
| DynamoDB | single-digit ms reads, no instance to size, PITR to the second | ad-hoc queries, joins |
| Aurora | SQL and joins, one engine for catalog and orders | instance sizing, higher floor cost |

## Scoring
| Criterion | Weight | DynamoDB | Aurora |
|---|---|---|---|
| Read latency (NFR-001) | 40 | 5 - single-key reads under 10 ms | 4 - needs a reader and a cache for the peak |
| Recovery (NFR-003) | 30 | 4 - PITR, global tables optional | 4 - PITR, cross-region snapshot |
| Cost per order | 20 | 4 - on-demand, about USD 0.0004 | 3 - writer and reader floor |
| Operational effort | 10 | 4 - nothing to patch | 3 - engine upgrades |
| **Weighted total** | 100 | 4.5 | 3.7 |

## Discussion
Not yet held.

## Decision
Recommended option: **Amazon DynamoDB**, because it leads on the latency and cost drivers.

## Consequences
- Positive: no capacity planning.
- Negative: reporting queries need an export.
- Reversibility: medium, a re-platforming of the catalog access layer.

## Assumptions
Catalog access stays key-based.

## Revisit when
Reporting needs ad-hoc joins over the catalog.
