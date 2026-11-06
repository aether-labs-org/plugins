---
name: requirements
description: >
  Elicits and records measurable requirements for an AWS solution: functional needs, NFRs as
  quality-attribute scenarios, constraints, RTO/RPO, budget, data classification and residency
  (LGPD). Writes requirements.md and the manifest entries. Use after discovery, or when NFRs are
  vague ("highly available", "fast", "cheap").
allowed-tools: Bash(python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate_manifest.py *)
---

# Requirements

Architecture starts from measurable requirements. **An NFR without a number is not a
requirement yet** - it is a question for the user.

## Procedure

1. Read what the user already gave you (brief, repository, previous documents) and, when it
   exists, `architecture/framing.md` from the `discovery` stage: its goals, anti-goals,
   constraints (with their `Source`), current state and discriminating questions. Extract every
   requirement you can before asking anything, and **do not ask again** what the framing already
   answers; quote it back as known instead.
2. Ask, in **one** message, only for what is missing from this list. When a framing exists, put
   first the measures its discriminating questions name (they decide between the candidates),
   then the rest in the order of how much each could change the design. Always include the
   primary region and, if DR matters, the recovery region - the workspace was created with a
   placeholder region (`Source: default`) that this answer replaces:
   - main user journeys and expected load (requests/s, users, data volume, growth per year);
   - latency, throughput and availability targets (turn adjectives into numbers);
   - RTO and RPO for the whole system and for any component with stricter needs;
   - monthly budget ceiling and the business unit cost is measured in (order, user, GB);
   - data classification: does it hold **personal data** (LGPD)? sensitive personal data?
     where must it stay (region / country)? retention period?
   - compliance frameworks that apply (CIS AWS Foundations is the default baseline);
   - hard constraints: region, existing accounts, mandated services, team skills, deadlines.
3. Write `architecture/requirements.md` from `assets/requirements.md`, in the manifest
   `language`. Express every NFR as a quality-attribute scenario
   (`references/qa-scenarios.md`); pick attributes from `references/nfr-catalog.md`. Fill the
   `Source` column on every row (`user`, `inferred`, `default` or `agent`): a measure you
   estimated is `inferred`, never `user`.
4. Mirror every item into `manifest.requirements[]` with ids `REQ-nnn` (functional),
   `NFR-nnn` (quality) and `CON-nnn` (constraint). Put the measure in `measure`; when the user
   cannot give one yet, write `TBD by <owner>` and list it as an open question.
5. Record `business_units` and any known usage volumes in `manifest.assumptions`.
6. Validate:

   ```bash
   python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate_manifest.py architecture/manifest.json
   ```

## Exit gate

Every NFR has a measure or `TBD by <owner>`; RTO/RPO, region(s), monthly budget and data
classification are recorded. Report open questions as a numbered list - never invent a number
to close one.
