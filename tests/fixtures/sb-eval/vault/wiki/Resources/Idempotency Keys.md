---
title: Idempotency Keys
summary: A client-supplied key that makes a retried request safe to repeat.
type: conceito
status: draft
origin: human
created: 2026-08-16
source:
tags:
  - api
  - resiliencia
---
The client sends a unique key with a write request; the server stores the key with the result and returns the same result for any duplicate. Essential for payment APIs where a timeout could otherwise charge a customer twice. Used in [[Payment Gateway Integration]].
