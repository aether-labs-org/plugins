---
title: API Rate Limiting Project
summary: Add per-client rate limits to the public API.
type: projeto
status: draft
origin: human
created: 2026-07-20
source:
tags: [api]
---
Token bucket per API key, stored in a shared cache. Return 429 with a Retry-After header. Start in log-only mode, compare against real traffic, then enforce. Clients should use [[Exponential Backoff with Jitter]].
