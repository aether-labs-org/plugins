---
title: Postgres Index Types
summary: When to use btree, hash, GIN, GiST and BRIN indexes in PostgreSQL.
type: nota
status: draft
origin: human
created: 2026-07-12
source:
tags:
  - postgres
  - banco-de-dados
---
Btree is the default and handles equality and ranges. GIN indexes arrays, jsonb and full text search. GiST serves geometric and range types, BRIN suits huge append-only tables ordered by time. Partial and covering indexes cut size and heap lookups. Check plans with EXPLAIN ANALYZE.
