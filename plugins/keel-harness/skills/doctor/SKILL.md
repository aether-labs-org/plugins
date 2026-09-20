---
name: doctor
description: >
  Checks whether an installed harness has drifted from the repository it guards: AGENTS.md
  over 100 lines, commands cited there that no longer exist, sensors declared in the Makefile
  whose tool is missing or fails to run, and a model_baseline that has fallen behind. Reports
  and proposes; writes nothing. Use when someone asks whether their harness is out of date,
  stale or still valid, or wants a harness health check.
---

# Doctor

Reports and proposes, never writes.
