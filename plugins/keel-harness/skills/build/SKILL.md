---
name: build
description: >
  Installs an AI-agent harness in a repository: one-command bootstrap, an AGENTS.md index of
  at most 100 lines with pointer files, a fast gate of computational sensors (types, lint,
  affected tests, secret scanning) behind a single Makefile target, sensor wrappers that emit
  pass signal, guidance, scope, class and cost, and the PostToolUse hook that runs the gate.
  Infers from the repository and confirms before writing; installs one layer at a time and is
  resumable. Use when someone asks to set up or build a harness, configure their repository
  for AI agents, add agent guardrails or quality gates, or make a repo agent-friendly.
---

# Build

Writes nothing before the user confirms.
