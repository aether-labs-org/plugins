---
name: init
description: >
  Creates a local-first Second Brain vault in the current directory: wiki/, _inbox/, _raw/, a
  generated _index.md, an append-only _log.md and the vault CLAUDE.md. Idempotent; never
  overwrites an existing CLAUDE.md. Run it once per vault.
disable-model-invocation: true
argument-hint: "[language]"
allowed-tools: Bash(sb init *) Bash(sb lint *) Bash(git init *)
---

# Initialise a Second Brain vault

The vault is the directory where `claude` runs. Do **not** create files by hand: `sb init` does
the mechanical work and writes the marker `.second-brain.json` last.

## Procedure

1. If `.second-brain.json` already exists here, run `sb lint`, report the result, and stop. Do not
   change anything.
2. Ask the user, in **one** message, at most these three questions (skip any already answered by
   `$ARGUMENTS`):
   - note language (a BCP-47 tag such as `pt-BR` or `en`; default `en`);
   - run `git init`? (skip if `.git` exists; it is needed for auto-commit and is the safety net);
   - initial areas under `wiki/Areas/` (comma-separated, may be empty).
3. Run `sb init --language <lang> --areas "<a,b>" [--git]`.
4. Run `sb lint` and confirm it reports nothing.
5. Tell the user, briefly:
   - put original sources in `_raw/` (the agent cannot write there);
   - `CLAUDE.md` holds the rules and is edited by the human, not by the agent;
   - next steps: `/second-brain:capture`, then `/second-brain:ingest`;
   - changes are committed locally when the session ends and the vault has a `.git`
     (plugin setting `auto_commit`, on by default; it never pushes).

Never ask more than three questions. Never store personal data in the plugin; everything lives in
the vault.
