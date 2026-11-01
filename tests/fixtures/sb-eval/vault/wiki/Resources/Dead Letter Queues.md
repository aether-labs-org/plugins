---
title: Dead Letter Queues
summary: Park messages that keep failing so they stop blocking the queue.
type: conceito
status: draft
origin: human
created: 2026-09-26
source:
tags:
  - mensageria
aliases:
  - DLQ
---
After a configured number of failed deliveries a message moves to a dead letter queue. Poison messages no longer block consumers, and someone can inspect, fix and redrive them. Alarm on queue depth; a growing dead letter queue means a bug or a bad deploy.
