# AGENTS.md - ledger
TypeScript service. Last updated: 2026-10-29.

## Commands
| Purpose | Command | Pass signal |
| --- | --- | --- |
| Fast gate | `make gate-fast` | `gate: fast - PASSED` |
| Slow gate | `make gate-slow` | `gate: slow - PASSED` |

## Rules
- Source under `src/` does not call `console.log` (use the logger) → docs/conventions.md#no-console
- Source files stay under 300 lines → docs/conventions.md#file-size
