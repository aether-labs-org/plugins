---
name: init
description: >
  Creates a Second Brain vault in the current directory: asks a few questions, proposes a folder
  structure for the user's case and, once approved, creates it with sb init (folders with
  _about.md, project settings, Web Clipper template, views). Never overwrites files.
disable-model-invocation: true
argument-hint: "[language]"
allowed-tools: Read Bash(sb init *) Bash(sb lint *) Bash(sb tree *) Bash(git init *) Bash(ls *)
---

# Initialise a Second Brain vault

The vault is the directory where `claude` runs and its own git repository. Create nothing by
hand: `sb init` does it and writes `.agents/second-brain/config.json` last.

1. Check what is here. `.agents/second-brain/config.json` exists: the vault exists; run `sb lint`,
   report and stop. `.second-brain.json` exists: a schema 2 vault is not operated; point to
   "Migrating from 0.2" in the second-brain README and stop. Inside another git repository:
   stop; a vault is its own repository.
2. Ask, in one message, at most four questions (skip what `$ARGUMENTS` answers): what the vault
   is for; alone or shared (and the git remote); the note language (BCP-47, default `en`); any
   folder habit or existing material (`ls` it if the user points at some).
3. Propose three to six top-level folders, each with a name, a one-line description and
   conventions, all in the vault language. `examples.md` holds three structures (personal PARA,
   individual work, project or team) to adapt, not to copy. Show the proposal and ask the user to
   approve or edit it.
4. Only after approval, run `sb init --language <tag> --folders - [--git] [--remote <url>]` and
   pass the folders on stdin as JSON: `[{"path": "...", "description": "...", "conventions":
   "..."}]`. A path has at most two levels, no `_` or `.` prefix and no `..`. `--remote` needs
   `--git`, sets `sync: pull` and adds origin.
5. Run `sb lint` and print the `hint:` lines `sb init` gave (the Obsidian attachment folder).
6. Tell the user, briefly: install the plugin with `--scope project` and commit
   `.claude/settings.json`; put originals worth versioning in `_raw/`; import
   `_meta/web-clipper-template.json` into the Obsidian Web Clipper; `_views/unreviewed.base` and
   `notes.base` list notes; each session is committed to git; with a remote the vault is pulled at
   session start and pushed by hand; `ingest` may propose new folders later; next steps are
   `/second-brain:capture` and `/second-brain:ingest`.

Never ask more than four questions.
