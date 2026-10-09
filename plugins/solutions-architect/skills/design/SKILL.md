---
name: design
description: >
  Makes and records AWS architecture decisions: discusses two or more options and their
  trade-offs with the user before recording, criteria tied to NFR ids and cost per business
  unit, regional availability checked, one MADR file per decision. Use when choosing services,
  databases, networking, compute, integration, data or AI patterns, or revisiting a decision.
allowed-tools: Bash(python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate_manifest.py *)
---

# Design

Every structural choice becomes an Architecture Decision Record with alternatives. **A choice
without a rejected alternative is an assumption, not a decision** - and a decision the user
never discussed is the agent's opinion. Analyse, then discuss, then record.

## Procedure

1. Read `architecture/requirements.md` and `manifest.requirements`. If the requirements gate is
   not `pass`, say which fields are missing and stop.
2. List the structural decisions the solution needs - usually compute platform, entry point,
   data stores, integration style, network layout, identity, DR strategy, and any AI component.
   For each domain read the matching file in `references/aws/` (compute, networking, storage,
   databases, containers, serverless, integration, data, ai) and the aws-core skill it names.
3. For each decision, following `references/trade-offs.md`:
   - write 2 to 4 options, at least one of them not the obvious one;
   - score them against criteria that **cite NFR ids** and include **cost per business unit**
     (ask the `finops` skill for list prices when the options differ in cost);
   - confirm every service of every option is offered in every workspace region with
     `aws___get_regional_availability` - an option unavailable in a required region is rejected,
     and the ADR says so;
   - check current service facts with `aws___search_documentation` instead of memory;
   - note the trade-offs (gains / gives up), the sensitivity of the ranking and the revisit
     triggers.
4. **Discuss before recording**, following `references/discussion.md`: classify each decision
   as high or low impact; run one round per high-impact decision and a single round for all the
   low-impact ones; **stop and wait for the answer** after each round. When the user asked not
   to be asked, accept the recommendation and record `Not held - <reason>` with the questions
   you would have asked.
5. Write one file per decision: `architecture/decisions/NNNN-<slug>.md` from `assets/madr.md`,
   in the manifest `language`, including the Trade-offs, Discussion, Assumptions and Revisit
   when sections.
6. Update the manifest: add the decision (`status: accepted` once its discussion round closed,
   `addresses`: the requirement ids it satisfies) and one `components[]` entry per deployable
   component (`id` kebab-case, `service`, `decision`, `diagrams` it appears in; `terraform`
   stays empty until the `iac` stage).
7. Validate:

   ```bash
   python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate_manifest.py architecture/manifest.json
   ```

   Its warning lists NFRs no accepted ADR covers yet - resolve each one or record why it needs
   no decision.

## Changing a decision

Never edit an accepted ADR's decision. Run the discussion round for the change, then write a new
ADR with `supersedes: ADR-nnnn`, set the old one to `superseded`, and tell the `architect` which
later stages must run again.

## Exit gate

Every structural decision has 2+ options and criteria citing NFR ids and cost per business
unit; every accepted ADR records its Discussion (the user's answer or `Not held - <reason>`) and
its Revisit when triggers; every chosen service was checked for regional availability; the
manifest validates.
