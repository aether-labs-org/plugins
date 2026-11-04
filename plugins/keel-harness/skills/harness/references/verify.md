# Verification and hand-off

Run these after the last write. Report every result as measured; if something was not run, say "not run" and why.

1. `sh .agents/bin/kh validate`: silent and exit 0. Each issue is one line `keel.yml: <path>: <message>`; fix the file, not the
   message.
2. `sh .agents/bin/kh check`: read every `warn <id>: <message>`. Expected right after setup: `githooks-inactive` until
   `kh setup` runs, and `script-unavailable` for tools that are not installed. Anything else is a gap to explain or close. Add
   `--strict` only if a clean result is the goal.
3. `sh .agents/bin/kh gate fast --all`: the fast gate over every tracked file, not just the changes. This is where a pattern that
   matches nothing, a report that is never found, or a tool that does not run shows up. Read the verdict line
   (`gate: fast - PASSED (P of N, S skipped) | ceiling ..., spent ...`) and every skipped script: a skip names the missing tool.
4. If the user accepts the cost: `sh .agents/bin/kh gate slow --all`. A script that times out or errors is a finding of its own.
5. Run `sh .agents/bin/kh run <script>` once for each new script whose parser you configured, and compare the findings with the
   tool's own output: an errorformat that parses nothing looks like a clean run.

If a gate is over its ceiling (`over ceiling` in the verdict), say so; do not raise the ceiling to make it disappear (that is a
loosening that needs an ADR).

## Hand-off

The skill never commits. Tell the human, in this order:

1. Review the diff and commit what you want. (Commit only what another person needs.)
2. Run `sh .agents/bin/kh setup` once per clone: it fetches the pinned `kh`, activates the native git hooks and runs `kh check`.
3. Open a new session in the agent of your choice; guides load at session start.
4. When `kh check` says `review-due`, or the rules look stale, run this skill again in update mode.

State the declared limits in one short paragraph: protection is friction with evidence, not a security boundary; the effect of
the guides on agent success was not measured; the Copilot and Devin cross-reads are assumed from their documentation.
