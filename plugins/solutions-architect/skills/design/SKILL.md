---
name: design
description: >
  Makes and records AWS architecture decisions: first a direction ADR choosing among whole-system
  candidates, then component decisions. Discusses two or more options and trade-offs with the user
  before recording; criteria tied to NFR ids and cost per business unit; one MADR file per
  decision. Use for choosing services, databases, networking, compute or integration, or for
  revisiting a decision.
allowed-tools: Bash(python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate_manifest.py *)
---

# Design

Every structural choice becomes an Architecture Decision Record with alternatives. **A choice
without a rejected alternative is an assumption, not a decision** - and a decision the user
never discussed is the agent's opinion. Analyse, then discuss, then record.

Be critical, not agreeable: apply rules R1 to R6 and the red flags in `references/discussion.md`
section 6 on every decision. A solution the user brings ready-made is a hypothesis (R2); the
recommendation moves for new evidence or a new constraint, not for disagreement (R3); a market
reference counts only if it was consulted (`references/trade-offs.md`, B1 and B2). A one-off
question with no workspace is a consultation (R6): answer it that way and stop.

## Procedure

1. Read `architecture/requirements.md` and `manifest.requirements`, and `architecture/framing.md`
   when it exists. If the requirements gate is not `pass`, say which fields are missing and stop.
2. **Direction first.** In a new design, the first decision is the **direction ADR**
   (`decisions/0001-direction.md`): which whole-system approach to take.
   - Its options are the candidates of `framing.md`, including the contrary one, with the
     discriminating questions as their measurable conditions. The `requirements` stage has
     measured them by now.
   - If there is no framing (`gates.discovery` is `skipped`, or the user started at `design`),
     generate 2 or 3 whole-system candidates plus a contrary one yourself, with a Mermaid C4
     sketch each (`${CLAUDE_PLUGIN_ROOT}/skills/diagram/references/c4-mermaid.md`).
   - An anti-goal is a knock-out: a candidate that violates one is rejected, and the ADR says so.
   - Score the candidates against criteria that cite NFR ids; give the best argument for the
     runner-up (R4); discuss it as a high-impact round before accepting it.
   - A workspace from v0.2 that already has accepted ADRs keeps them; add no retroactive
     direction ADR unless the user asks.
3. List the structural decisions the chosen direction needs - usually compute platform, entry
   point, data stores, integration style, network layout, identity, DR strategy, and any AI
   component. For each domain read the matching file in `references/aws/` (compute, networking,
   storage, databases, containers, serverless, integration, data, ai) and the aws-core skill it
   names.
4. For each decision, following `references/trade-offs.md`:
   - write 2 to 4 options, at least one of them not the obvious one;
   - score them against criteria that **cite NFR ids** and include **cost per business unit**
     (ask the `finops` skill for list prices when the options differ in cost);
   - confirm every service of every option is offered in every workspace region with
     `aws___get_regional_availability` - an option unavailable in a required region is rejected,
     and the ADR says so;
   - check current service facts with `aws___search_documentation` instead of memory;
   - note the trade-offs (gains / gives up), the sensitivity of the ranking and the revisit
     triggers.
5. **Discuss before recording**, following `references/discussion.md`: classify each decision
   as high or low impact; run one round per high-impact decision and a single round for all the
   low-impact ones; **stop and wait for the answer** after each round. When the user asked not
   to be asked, accept the recommendation - or the option the user explicitly chose (R3),
   recorded with `Source: user` and the risk it accepts - and record `Not held - <reason>` with
   the questions you would have asked. The preference they brought is still one scored option,
   with the contrary option scored beside it.
6. Write one file per decision: `architecture/decisions/NNNN-<slug>.md` from `assets/madr.md`,
   in the manifest `language`, including the Market references, Trade-offs, Discussion,
   Assumptions and Revisit when sections.
7. Update the manifest: add the decision (`status: accepted` once its discussion round closed,
   `addresses`: the requirement ids it satisfies) and one `components[]` entry per deployable
   component (`id` kebab-case, `service`, `decision`, `diagrams` it appears in; `terraform`
   stays empty until the `iac` stage).
8. Validate:

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

In a new design, `decisions/0001-direction.md` exists, is accepted, and chooses among the candidates. Every
structural decision has 2+ options and criteria citing NFR ids and cost per business unit; every
accepted ADR records its Discussion (the user's answer or `Not held - <reason>`, with `Source`
on what the user brought) and its Revisit when triggers; every market reference in an ADR is
marked `consulted` or `not consulted` and the latter carry no weight; every chosen service was
checked for regional availability; the manifest validates.
