---
title: Consistent Hashing
summary: Spread keys over nodes so that adding or removing a node moves few keys.
type: conceito
status: seed
origin: agent
created: 2026-08-18
source:
tags: [distribuidos]
aliases: [hash ring]
---
Nodes and keys are placed on a hash ring and each key belongs to the next node clockwise. Virtual nodes smooth out the load. When a node leaves, only its keys move to the neighbour. Used by caches and partitioned stores.
