---
title: Payment Gateway Integration
summary: Integrate the card payment provider into the checkout service.
type: projeto
status: draft
origin: agent
created: 2026-09-05
source:
tags: [pagamentos]
---
Create charges server-side with [[Idempotency Keys]], handle webhooks with signature checks and store the provider reference with each order. Test the timeout path: a retried request must never create a second charge. Sandbox first, then a one percent rollout.
