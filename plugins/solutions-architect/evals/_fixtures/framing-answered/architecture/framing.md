# Framing - Order platform modernization

## Context and why now

The company runs its order system as one Java application on two on-premises servers. Black Friday
2025 produced three outages of 20 to 40 minutes each, and the data centre contract ends in 14
months. `Source: user`

## Success

Black Friday 2026 passes without a customer-visible outage, and the on-premises contract is not
renewed. `Source: user`

## Goals, non-goals and anti-goals

| Kind | Item | Source |
|---|---|---|
| Goal | Checkout stays up under the Black Friday peak | user |
| Goal | Leave the data centre before the contract ends | user |
| Non-goal | Rewriting the pricing engine | user |
| Non-goal | A new mobile app | user |
| Anti-goal | The team must not operate Kubernetes | user |
| Anti-goal | No second big-bang cutover weekend | inferred |

## Current state

One Java application, one PostgreSQL 12 database (about 400 GB), nightly batch jobs that read the
orders table directly, a payment gateway integrated by REST. Team: 6 developers, 1 operations
person, no Kubernetes experience, solid Java and PostgreSQL skills. `Source: user`

## Constraints and preferences

| Item | Kind | Source |
|---|---|---|
| Personal data of customers stays in Brazil | must | user |
| The payment gateway contract stays as is | must | user |
| Prefer managed services over self-operated ones | prefer | inferred |
| Budget in the order of USD 3,000 per month | prefer | user |

## Candidates

| Id | Approach | Relative cost | Reversibility |
|---|---|---|---|
| A | Modular monolith on ECS Fargate with Aurora PostgreSQL, strangler migration of the batch jobs | 1x | high |
| B | Event-driven services on EKS with Kafka | about 3x | low |
| C | Buy a SaaS order-management product and integrate it (contrary option) | 1.5x to 2x | medium |

Market references: A - Strangler fig pattern (AWS Prescriptive Guidance), `not consulted`.
B - no applicable reference in the catalog. C - no applicable reference in the catalog.

## Discarded

- Lift and shift of the two servers to EC2: keeps the single point of failure that caused the outages.

## Discriminating questions

1. DQ-1: if the peak passes about 2,000 requests per second, B overtakes A. What is the Black Friday
   peak today and the forecast for 2026?
2. DQ-2: if the batch jobs cannot be moved behind an API within the deadline, A needs a shared
   database for a while. How many batch jobs read the orders table directly?
3. DQ-3: if licence cost per order is above USD 0.10, C loses. What does the vendor quote?

## Pre-mortem and blind spots

- Twelve months on: the single Aurora writer became the new bottleneck on the peak day.
- Conway: one operations person cannot run on-call for B.
- Data gravity: 400 GB of PostgreSQL 12 must be migrated with minimal downtime.

## Independent challenge

Run on 2026-11-06. Triage: 2 answered in this document, 1 minor decided by the agent
(`Source: agent`), 1 for the user, answered in the discussion.

## Discussion

The user chose A as the leading hypothesis, not a decision. B stays as a candidate until DQ-1 is
answered.

## Open questions

1. Peak requests per second today and forecast (DQ-1).
2. Number of batch jobs that read the orders table (DQ-2).
3. Primary region and secondary region for disaster recovery.
