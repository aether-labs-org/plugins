# ADR-0001: Amazon EKS for the order services

- Status: accepted
- Date: 2026-11-06
- Addresses: NFR-001, NFR-002
- Supersedes: -
- Impact: high

## Context and problem
The order API needs a compute platform that meets p95 < 300 ms at 200 rps and 99.9% availability.

## Options considered
| Option | Regional availability (sa-east-1, us-east-1) | Knock-out? |
|---|---|---|
| Amazon EKS | available in both | no |
| Amazon ECS on AWS Fargate | available in both | no |

## Scoring
| Criterion | Weight | EKS | ECS Fargate |
|---|---|---|---|
| NFR-001 latency | 40 | 4 - fine-grained autoscaling | 4 - comparable |
| NFR-002 availability | 40 | 5 - multi-AZ node groups | 5 - multi-AZ tasks |
| Cost per order | 20 | 3 - control plane fee | 4 - no cluster fee |
| **Weighted total** | 100 | 4.2 | 4.4 |

## Discussion
Not held - the brief allowed no questions.

## Decision
Chosen option: **Amazon EKS**, because it scores well on availability and offers portable workloads.

## Consequences
- Positive: portable workloads.
- Negative: someone must operate the cluster.

## Revisit when
The peak passes 2,000 req/s.
