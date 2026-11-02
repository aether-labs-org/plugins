---
title: Hexagonal Architecture
summary: Keep the domain at the centre and talk to the world through ports and adapters.
type: conceito
status: evergreen
origin: human
created: 2026-07-10
source:
reviewed: 2026-09-22
tags:
  - arquitetura
  - padroes
aliases:
  - ports and adapters
  - clean boundaries
---
The application core defines ports, interfaces it needs; adapters implement them for databases, queues and HTTP. Tests swap the adapters for fakes, so business rules are tested without infrastructure. Dependencies always point inwards.
