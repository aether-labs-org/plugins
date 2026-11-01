---
title: CQRS
summary: Separate the model that handles writes from the models that serve reads.
type: conceito
status: draft
origin: human
created: 2026-06-03
source:
tags:
  - arquitetura
aliases:
  - Command Query Responsibility Segregation
---
Commands change state through one model; queries read from denormalised views kept up to date by events. It adds eventual consistency and operational cost, so only use it where read and write loads really differ. Often built on [[Event Sourcing]].
