---
title: Exponential Backoff with Jitter
summary: Space out retries with growing, randomised delays.
type: conceito
status: draft
origin: human
created: 2026-08-19
source:
tags: [resiliencia]
aliases: [retry backoff, backoff]
---
When a request fails, wait base times two to the power of the attempt, capped, and add random jitter so many clients do not retry in lockstep. Without it, retries can overwhelm a service that is already failing. Keep the number of retries small and pair them with a [[Circuit Breaker Pattern]].
