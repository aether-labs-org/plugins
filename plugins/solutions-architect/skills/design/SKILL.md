---
name: design
description: >
  Makes and records AWS architecture decisions: two or more options per structural decision,
  criteria tied to NFR ids and to cost per business unit, regional availability checked, one
  MADR file per decision. Use when choosing services, databases, networking, compute,
  integration, data or AI patterns for a solution, or when revisiting a past decision.
allowed-tools: Bash(python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate_manifest.py *)
---

# Design

Every structural choice becomes an Architecture Decision Record with alternatives. **A choice
without a rejected alternative is an assumption, not a decision.**

## Procedure

1. Read `architecture/requirements.md` and `manifest.requirements`. If the requirements gate is
   not `pass`, say which fields are missing and stop.
2. List the structural decisions the solution needs - usually compute platform, entry point,
   data stores, integration style, network layout, identity, DR strategy, and any AI component.
   For each domain read the matching file in `references/aws/` (compute, networking, storage,
   databases, containers, serverless, integration, data, ai) and the aws-core skill it names.
3. For each decision, following `references/trade-offs.md`:
   - write 2 to 4 options;
   - score them against criteria that **cite NFR ids** and include **cost per business unit**
     (ask the `finops` skill for list prices when the options differ in cost);
   - confirm every service of every option is offered in every workspace region with
     `aws___get_regional_availability` - an option unavailable in a required region is rejected,
     and the ADR says so;
   - check current service facts with `aws___search_documentation` instead of memory.
4. Write one file per decision: `architecture/decisions/NNNN-<slug>.md` from `assets/madr.md`,
   in the manifest `language`.
5. Update the manifest: add the decision (`status: accepted` once the user agrees,
   `addresses`: the requirement ids it satisfies) and one `components[]` entry per deployable
   component (`id` kebab-case, `service`, `decision`, `diagrams` it appears in; `terraform`
   stays empty until the `iac` stage).
6. Validate:

   ```bash
   python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate_manifest.py architecture/manifest.json
   ```

   Its warning lists NFRs no accepted ADR covers yet - resolve each one or record why it needs
   no decision.

## Changing a decision

Never edit an accepted ADR's decision. Write a new ADR with `supersedes: ADR-nnnn`, set the old
one to `superseded`, and tell the `architect` which later stages must run again.

## Exit gate

Every structural decision has 2+ options and criteria citing NFR ids and cost per business
unit; every chosen service was checked for regional availability; the manifest validates.
