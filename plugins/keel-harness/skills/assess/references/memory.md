# Auto-memory coherence in a health check

Spec D41 and evidence item 12. Claude Code's auto memory loads into every session next to `AGENTS.md`, so
an entry in it can say something the harness's rules contradict. `assess` reads the memory and reports
the contradictions. It never edits, creates or deletes a memory file: it proposes that the user does.

## What auto memory is (Claude Code memory docs, https://code.claude.com/docs/en/memory, read 2026-10-29)

- Claude writes notes for itself, in four kinds recorded as a `type` field in each file's frontmatter:
  `user`, `feedback`, `project` and `reference`.
- Location: `~/.claude/projects/<project>/memory/`. The `<project>` part is derived from the git
  repository, so all worktrees of one repository share a directory. The directory holds a `MEMORY.md`
  index (one line per memory) and one topic file per memory (`user_role.md`, `feedback_testing.md`, ...).
- It can live elsewhere: `autoMemoryDirectory` in any `settings.json` scope (user, project, local, policy)
  moves it, and `CLAUDE_CODE_PROJECT_DIR_NAME` renames `<project>`.
- It can be off: `autoMemoryEnabled: false` in settings, `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`, and by
  default in a self-hosted environment.
- The first 200 lines or 25 KB of `MEMORY.md`, whichever comes first, load into every session. Topic files
  load when Claude reads them. The files are machine-local plain Markdown.

The page does not say how `<project>` is spelled for a given path, so `assess` does not compute it.

## Steps

1. **Find the directory, never guess it.** In this order: `autoMemoryDirectory` in
   `.claude/settings.local.json`, `.claude/settings.json` and `~/.claude/settings.json` (read the file,
   take the value); else list `~/.claude/projects/*/memory/MEMORY.md` and keep the directories whose
   files mention this repository's name or path. If more than one qualifies, or none can be tied to this
   repository, say which you saw and ask the user which is theirs. If auto memory is off, the directory is
   missing or the user does not know, report "auto memory not read" with the reason and stop this step.
2. **Read it.** `cat` the `MEMORY.md` index and each topic file it lists. Note which lines sit past line
   200 of the index: Claude Code does not load those at session start.
3. **Collect what the harness says.** For each `.agents/rules/*.env`: the rule id, its numbers (`LIMIT`,
   `MIN`, `MAX`, `THRESHOLD`, ...) and its `DOC`; for `AGENTS.md`: each rule line and the commands
   table. These are the statements memory can contradict.
4. **Compare.** A contradiction is a statement in a memory entry about a rule's subject that differs from
   that rule's env-file numbers or its `AGENTS.md` line: "files may be up to 500 lines" against
   `LIMIT=400`; "run tests with npm" against a table that says `pnpm`; "skip the gate for docs-only
   changes" against "Before you finish". Entries about something no rule covers, and entries of type
   `user`, are not contradictions.
5. **Report.** One row per contradicting entry: the memory file and line, the entry quoted, the rule id
   or `AGENTS.md` line it conflicts with and the value there, and the proposal. This comparison is
   inferential: a model reading prose, not a script. Say so in the report, and phrase each row as "looks
   like a contradiction", never as a fact.
6. **Propose, never apply.** The proposal for each row is that the user edits or deletes that entry
   (`/memory` in Claude Code opens the folder), or, when the memory is right and the rule is stale, runs
   `/keel-harness:rules` to change the rule. Say nothing when nothing contradicts: coherent memory is a
   valid answer.
