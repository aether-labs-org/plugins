# 0002. Remove the Obsidian companion gates

Status: accepted
Date: 2026-11-10

## Context and problem statement

second-brain v0.3 removes the Obsidian companion plugin
(`plugins/second-brain/obsidian/`): review becomes a label plus
the session commit. The only TypeScript in the repository goes
with it, and the scripts `typecheck` and `lint` in
`.agents/bmax.yml` ran only on that plugin.

## Considered options

### Remove the scripts with the plugin (recommended)

- Good: nothing checks a directory that no longer exists.
- Bad: a TypeScript plugin added later has no gate.

### Keep the scripts

- Bad: they fail on every commit that touches a .ts file.

## Decision outcome

Chosen: remove them. Confirmed by Igor on 2026-11-10. Loosened, by id or file:

- `.agents/bmax.yml#typecheck` (removed from gate `fast`)
- `.agents/bmax.yml#lint` (removed from gates `fast`, `commit`)
- `plugins/second-brain/obsidian/tsconfig.json`
- `plugins/second-brain/obsidian/eslint.config.mts`

The exclude list of `isolation-second-brain` and two lines of
`AGENTS.md` drop their mentions of the plugin. This replaces the
`fast` bullet of ADR 0001 about typecheck and lint.

## Consequences

- No TypeScript or npm in the repository.
- A future TypeScript plugin needs its own scripts and an ADR.

## Evidence

- `bmax guard`: 5 loosenings since 1189b5e.
- Source: docs/specs/2026-11-10-second-brain-v0.3-design.md (D38).
