---
description: Full discovery from a complete brief with no questions allowed; framing.md meets the gate, the challenger runs, the manifest validates.
tags: [harness, discovery]
runs: 3
max_turns: 80
timeout_seconds: 1500
allowed_tools: [Read, Glob, Grep, Skill, Agent, TodoWrite, Write, Edit, Bash]
---

Our order system is one Java application on two on-premises servers with a 400 GB PostgreSQL 12
database. Black Friday 2025 caused three outages of 20 to 40 minutes, and the data centre
contract ends in 14 months. We want Black Friday 2026 without a customer-visible outage and to
leave the data centre. Not in scope: rewriting the pricing engine or building a new mobile app.
The team is 6 developers and 1 operations person, strong in Java and PostgreSQL, with no
Kubernetes experience, so the team must not operate Kubernetes. Customer personal data stays in
Brazil. The payment gateway contract stays as it is. Budget is in the order of USD 3,000 per
month. Nightly batch jobs read the orders table directly.

Run the discovery stage only and write the framing. Do not ask me anything: where something is
missing, record it as an open question. I have no time for a discussion of the candidates, so
treat it as not held. Do not write requirements or ADRs. There is no network access in this
environment.
