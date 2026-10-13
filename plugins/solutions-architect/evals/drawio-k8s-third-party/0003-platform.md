# ADR-0003: Order API on EKS, events on Kafka (Strimzi), monitoring on Datadog

- Status: accepted
- Addresses: NFR-001, NFR-002
- Impact: high
- Supersedes: ADR-0001

## Options considered
| Option | Regional availability (sa-east-1, us-east-1) | Knock-out? |
|---|---|---|
| EKS + Kafka via Strimzi + Datadog | available in both | no |
| ECS on Fargate + Amazon MSK + CloudWatch | available in both | no |

## Discussion
The team already runs Kubernetes and Kafka elsewhere and has a Datadog contract; the user chose
the first option.

## Decision
The order API runs as a Deployment in namespace `orders` of an EKS cluster in sa-east-1 (two
AZs). Order events go to a Kafka cluster operated by Strimzi in namespace `kafka` of the same
cluster. Metrics, logs and traces are shipped to Datadog (SaaS) by the Datadog agent DaemonSet;
no personal data is sent.

## Revisit when
Kafka operations take more than one engineer-day per week - then Amazon MSK wins.
