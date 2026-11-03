---
title: Raft Consensus
summary: Understandable consensus: a replicated log driven by a single elected leader.
type: conceito
status: evergreen
origin: human
created: 2026-09-25
source:
reviewed: 2026-10-02
tags:
  - distribuidos
aliases:
  - raft
---
Nodes are followers, candidates or the leader. A follower that hears no heartbeat starts an election for a new term and needs a majority of votes. The leader appends entries to the log and commits them once a majority has replicated them. Used by etcd and Consul.
