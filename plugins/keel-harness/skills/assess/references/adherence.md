# Adherence diagnosis: did the agent follow the flow?

Spec section 5.4. The process evals grade trajectories on fixtures the owner runs; this is the same
question asked of a real session. It is a prompt-style procedure in the spirit of superpowers'
`plan-adherence` analyst (`skills/diagnosing-superpowers/prompts/plan-adherence.md`, spec evidence item
5): recover what was agreed, map it to what was executed, report what is skipped, out of order or
invented, with the line that shows it. It measures; it promises nothing.

**Opt-in.** `assess` offers this only when the user asks how well agents follow the harness, and runs it
only on a transcript the user points at. It never searches for transcripts on its own, and it reads the
transcript without changing it.

## Input

A session transcript file the user names (for Claude Code, a `.jsonl` file under
`~/.claude/projects/<project>/`). Read it with `grep -n` and `sed -n`, so every finding can cite its line
as `file:line`. If the user names no file, ask for one and stop.

## Procedure

1. **Which flow ran?** Find the skill the session invoked: a `Skill` tool call naming
   `keel-harness:build`, `keel-harness:rules` or `keel-harness:assess`, or a slash command. No flow in the
   transcript: report "no keel flow in this transcript" with the lines checked, and stop.
2. **Take the flow's phases** from the skill's `SKILL.md` (the `## Phases` and `## Done when` sections)
   and the commands of `${CLAUDE_PLUGIN_ROOT}/contracts/flow.md`.
3. **Mark each phase** in order of appearance and answer yes or no, citing the transcript line of the
   evidence (a tool call, a message to the user, a `keel` command):

| Phase or step | Yes when the transcript shows |
| --- | --- |
| `check pre` | `scripts/keel check pre <skill>` ran, before any other step |
| Discovery before proposal | files were read (`Read`, `ls`, `cat`, `grep`) before the proposal was shown |
| Proposal shown | a message to the user lists what would be written, before any write |
| User answered | a user message after the proposal that accepts, changes or rejects it (or the request itself said not to pause; the skill must then say so) |
| `keel plan` then `keel approve` | both ran after the user answered, with the proposal's hash |
| `keel apply` before the first write | `scripts/keel apply <skill>` exited 0 on a line earlier than the first `Write`, `Edit` or Bash write to a harness path |
| Writes inside the proposal | no file outside the proposal was written (compare the written paths with the proposal) |
| Gate run | `make gate-fast` or `scripts/gate.sh` ran after the last write |
| `keel verify` at the end | `scripts/keel verify <skill>` ran after the last write and its result is reported to the user |

4. **Order.** For every pair that must be ordered (`apply` before the first write; the gate and
   `verify` after the last write; the user's answer before `approve`) say whether the order held.
5. **Findings.** Group them: skipped step; out of order; invented work (a write or a command no phase
   covers); drift right after a compaction, resume or aborted turn (mark those events first, since they
   explain a lost step).

## Report

One table, a row per phase or step: `| Phase | Happened? | Transcript line |`, `yes` or `no` and the
`file:line`, then the findings in the groups above. If a step does not apply to this flow (`assess`
writes nothing, so it has no `apply`), mark it `n/a` with the reason. No score and no percentage for a
single session; a rate over time needs the same table for several sessions, and the user keeps them.
This procedure reports and proposes only: it changes no file, and the fix for a skipped step is the
user's to choose (a sharper `SKILL.md`, a hook, a process eval).
