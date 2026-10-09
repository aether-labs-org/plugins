---
name: review
description: >
  Reviews an AWS architecture workspace: delegates the Well-Architected pillar review to
  aws-core's aws-well-architected-review, adds lenses, method checks (NFR coverage, DR vs
  RTO/RPO, backups, timeouts) and an independent reviewer pass. Qualitative. Use before sharing
  or approving an architecture, or when asked for a Well-Architected review of a workspace.
allowed-tools: Bash(python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate_manifest.py *)
---

# Review

Qualitative review (decision D10), done by **someone other than the author**: the pillar review
comes from the official aws-core skill and the method review from a fresh-context subagent.

## Procedure

1. **Traceability.** Run:

   ```bash
   python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate_manifest.py architecture/manifest.json --strict-trace
   ```

   Every NFR must be addressed by an accepted ADR. A failure here is a blocker.
2. **Pillars.** Invoke the aws-core skill `aws-well-architected-review` on the workspace
   (requirements, ADRs, diagrams, `infra/`). If that skill is not available, write "Well-Architected
   pillar review not run: aws-core is not installed" at the top of the report - do not improvise
   a pillar review from memory.
3. **Lenses.** Apply the lenses in `references/lenses.md` whose trigger matches the workload.
4. **Method checks.** Go through `references/method-checks.md`; each check is pass, fail or
   not applicable, with the artifact that proves it.
5. **Independent pass.** Dispatch the `architecture-reviewer` subagent with the workspace path.
   It answers with blockers, risks and suggestions. If subagents are unavailable, do a second
   pass yourself reading only the artifacts, not this conversation.
6. **Challenge the decisions.** For each accepted ADR with `Impact: high` (or, without that
   field, one that is hard to reverse, a large share of the cost, or on an NFR path), using the
   reviewer's answer and `${CLAUDE_PLUGIN_ROOT}/skills/design/references/discussion.md`:
   - the strongest alternative not chosen - one from the ADR or a new one;
   - what changed since the decision (requirements, load, prices, services now available in
     the region) and whether a Revisit when trigger has fired;
   - the assumptions that look fragile;
   - a verdict: `keep`, `revisit` or `supersede`.

   Put this list to the user in one message and ask which decisions, if any, they want to
   reopen. Each one they reopen becomes an action for the `design` stage (a new ADR that
   `supersedes` the old one). When the user asked not to be asked, record the verdicts and
   reopen nothing.
7. Write `architecture/reviews/<YYYY-MM-DD>-review.md` in the manifest language: summary,
   blockers, pillar findings (from aws-core), lens findings, method checks table, reviewer
   findings, challenged decisions (with verdict and the user's answer), and actions - each
   action names the stage to revisit (`design`, `iac`, ...).

## Exit gate

`--strict-trace` passes and the independent reviewer reports no blocker.
