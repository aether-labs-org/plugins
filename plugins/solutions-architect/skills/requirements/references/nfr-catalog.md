# NFR catalog - attributes and how to measure them

| Attribute | Measure it as | Example |
|---|---|---|
| Latency | percentile + load | p95 < 300 ms for `POST /orders` at 200 rps |
| Throughput | sustained and peak rate | 200 rps sustained, 1,000 rps for 10 min at campaign peaks |
| Availability | monthly percentage + scope | 99.9% monthly for checkout (43 min of downtime) |
| Scalability | growth the design must absorb without redesign | 3x orders in 12 months |
| Resilience | failure it must survive, and how | loss of one AZ with no data loss and < 5 min degradation |
| Recovery | RTO / RPO | RTO 1 h, RPO 15 min for the orders database |
| Security | control + scope | all personal data encrypted at rest with customer-managed KMS keys |
| Privacy (LGPD) | residency, retention, rights | personal data stored only in sa-east-1; deleted 5 years after last order |
| Cost | ceiling + unit cost | < USD 3,000/month; < USD 0.01 per order |
| Operability | detection and recovery time | alert within 5 min of SLO burn; runbook for every alert |
| Sustainability | efficiency target | prefer Graviton; no idle environments outside business hours |
| Maintainability | change lead time | infrastructure change reviewed and applied through the pipeline within 1 day |
