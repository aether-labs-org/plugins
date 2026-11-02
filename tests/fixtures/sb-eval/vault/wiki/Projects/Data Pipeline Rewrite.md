---
title: Data Pipeline Rewrite
summary: Replace the nightly batch jobs with an incremental streaming pipeline.
type: projeto
status: draft
origin: mixed
created: 2026-08-25
source:
tags:
  - dados
---
The old pipeline reloads full tables every night. The new one reads change events from the database log, deduplicates them and writes partitioned files. Failed batches go to a [[Dead Letter Queues]] for replay. Cutover planned in two phases.
