# ADR-0001: Order API on ECS Fargate behind an ALB

- Status: accepted
- Addresses: NFR-001

## Options considered
| Option | Regional availability (sa-east-1, us-east-1) | Knock-out? |
|---|---|---|
| ECS on Fargate + ALB | available in both | no |
| Lambda + API Gateway HTTP API | available in both | no |

## Decision
ECS on Fargate in two AZs of sa-east-1 behind an internet-facing ALB in public subnets; tasks in
private subnets; one NAT Gateway per AZ.
