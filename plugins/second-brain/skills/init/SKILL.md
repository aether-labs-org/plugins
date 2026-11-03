---
name: init
description: >
  Creates a Second Brain vault in the current directory from a profile (personal, work,
  project or squad): folders with _about.md, project settings, Web Clipper template, review
  view, index and log. Upgrades v0.1 vaults in place and runs sb doctor. Never overwrites files.
disable-model-invocation: true
argument-hint: "[profile] [language]"
allowed-tools: Bash(sb init *) Bash(sb lint *) Bash(sb doctor *) Bash(sb tree *) Bash(git init *)
---

# Initialise a Second Brain vault

The vault is the directory where `claude` runs, and it is its own git repository. Do **not**
create files by hand: `sb init` does the mechanical work and writes the marker
`.second-brain.json` last.

## Procedure

1. If `.second-brain.json` already exists here, the vault exists:
   - run `sb init --upgrade` (a dry run: it changes nothing) and show the user the planned actions
     and the files it keeps;
   - apply with `sb init --upgrade --yes` **only** after the user says yes (add `--profile squad`
     to move a v0.1 vault to squad mode, which untracks `_index.md` and `_log.md`);
   - then run `sb doctor` and `sb lint`, report both, and stop.
2. Ask the user, in **one** message, at most these three questions (skip any already answered by
   `$ARGUMENTS`):
   - profile, with one line each:
     - `personal`: Projects, Areas, Resources, Archive; just you;
     - `work`: adds Decisions and Meetings; just you, at work;
     - `project`: Context, Decisions, Meetings, References, Glossary, Archive; one project;
     - `squad`: as `project`, shared by 2-5 people through a git remote;
   - note language (a BCP-47 tag such as `pt-BR` or `en`; default `en`);
   - git remote URL (squad only; may be empty and added later).
3. If the directory is inside another git repository, stop: a vault must be its own repository.
   Run `sb init --profile <p> --language <lang> --git [--remote <url>]` (squad always needs
   `--git`; use `--areas "<a,b>"` only when the user names areas for `personal` or `work`).
4. Run `sb lint` (it should report nothing but possibly info lines) and `sb doctor`; show the
   `warn` and `fail` lines with their fixes.
5. Tell the user, briefly:
   - install the plugin with `--scope project` and commit `.claude/settings.json`, so everyone who
     opens the vault gets the plugin and its dependencies;
   - put original sources in `_raw/` (the agent cannot write there);
   - `CLAUDE.md` and each folder's `_about.md` are edited by the human, not by the agent;
   - for web pages, import `_meta/web-clipper-template.json` into the Obsidian Web Clipper;
     `_views/unreviewed.base` lists agent notes waiting for review;
   - next steps: `/second-brain:capture`, then `/second-brain:ingest`;
   - changes are committed locally when the session ends (plugin setting `auto_commit`); only
     `squad` vaults pull at the start and push at the end of a session.

Never ask more than three questions. Never store personal data in the plugin; everything lives in
the vault.
