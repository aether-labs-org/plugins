---
title: Event Sourcing
summary: Store every state change as an immutable event and rebuild state by replay.
type: conceito
status: seed
origin: agent
created: 2026-09-23
source:
tags: [arquitetura]
aliases: [ES, event store]
---
Instead of overwriting rows, append events to an append-only event store. Current state is a fold over the events; snapshots keep replay fast. Gives a full audit trail but makes ad-hoc queries harder, which is why it is paired with [[CQRS]] read models.
