---
title: Terraform State Locking
summary: Prevent two concurrent runs from corrupting the same Terraform state.
type: nota
status: seed
origin: agent
created: 2026-08-17
source:
tags: [terraform, aws]
---
With the S3 backend, a lock table in DynamoDB makes a second apply wait or fail while the first one runs, so two people applying at the same time cannot corrupt the state file. A stale lock after a crashed run is removed with force-unlock, after checking nobody is applying.
