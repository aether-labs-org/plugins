---
title: Kubernetes Pod Disruption Budgets
summary: Limit how many pods of a workload voluntary evictions may take down at once.
type: nota
status: draft
origin: human
created: 2026-09-24
source:
tags:
  - kubernetes
aliases:
  - PDB
---
A PodDisruptionBudget sets minAvailable or maxUnavailable for a set of pods. Node drains and cluster upgrades respect it, which protects availability during voluntary disruptions. It does nothing for crashes or node failures. Relevant for [[Migração para Kubernetes]].
