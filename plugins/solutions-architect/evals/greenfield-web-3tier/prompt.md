---
description: Full greenfield run from a brief to validated views; no questions allowed.
tags: [workflow, greenfield]
runs: 2
max_turns: 120
timeout_seconds: 1800
allowed_tools: [Read, Glob, Grep, Skill, Agent, TodoWrite]
---

Design the AWS architecture for our order-taking platform. Brief: customers place orders from a
mobile app and a website; about 300,000 orders a month, peaks of 200 requests per second;
checkout must be available 99.9% of the month; the order API must answer in under 300 ms at
p95; orders and customer profiles are personal data that must stay in Brazil (LGPD); monthly
budget is USD 3,000; primary region sa-east-1, us-east-1 may hold a disaster-recovery copy with
RTO 4 h and RPO 1 h. Artifacts in Portuguese (pt-BR), Terraform directory `infra`.

Take the workspace through requirements, design and diagrams. Do not ask me anything: where
something is missing, record it as `TBD by product owner`. Do not write Terraform yet. There is
no network access in this environment.
