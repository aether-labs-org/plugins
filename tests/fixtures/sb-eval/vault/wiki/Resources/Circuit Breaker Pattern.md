---
title: Circuit Breaker Pattern
summary: Stop calling a dependency that keeps failing, and probe it again later.
type: conceito
status: evergreen
origin: human
created: 2026-07-09
source:
reviewed: 2026-09-20
tags:
  - resiliencia
  - padroes
aliases:
  - circuit breaker
  - breaker
---
A circuit breaker wraps calls to a remote service and counts failures. Past a threshold it opens and fails fast instead of waiting on timeouts; after a cool-down it goes half-open and lets a few trial requests through. If they succeed it closes again. Combine with [[Exponential Backoff with Jitter]] and [[Dead Letter Queues]].
