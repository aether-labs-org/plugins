# Framing - <solution name>

<!-- Write in the manifest `language`. The markers stay in English: `Source: user | inferred |
     default | agent`, `consulted` / `not consulted`, `Not held - <reason>`. Every item carries
     a Source. This file diverges on purpose: it lists candidates and does not choose one. -->

## Context and why now
<!-- The business problem, who has it and what changed. `Source:` -->

## Success
<!-- What the sponsor would say if it worked, in business terms. `Source:` -->

## Goals, non-goals and anti-goals
| Kind (goal / non-goal / anti-goal) | Item | Source |
|---|---|---|

## Current state
<!-- Systems, data and size, contracts, team and skills, where it hurts. `Source:` -->

## Constraints and preferences
| Item | Kind (must / prefer) | Source |
|---|---|---|

## Workspace defaults
<!-- What the workspace was created with before anyone was asked, all `Source: default` until the
     user says otherwise. The region is provisional: the requirements batch confirms it. -->
| Setting | Value | Source |
|---|---|---|
| Artifact language | <the conversation language> | default |
| Terraform directory | infra | default |
| Primary region | sa-east-1 (provisional) | default |

## Candidates
<!-- 2 or 3 whole-system approaches plus one contrary option (buy, do nothing, extend what
     exists, something simpler). The contrary option is mandatory. -->
| Id | Approach | Relative cost | Reversibility |
|---|---|---|---|
| A | | | |
| B | | | |
| C (contrary) | | | |

### Candidate A - <name>
- Sketch: see `diagrams/candidate-a.mmd` (Mermaid C4 containers) or an inline block.
- Patterns it instantiates:
- Market references: <name - `consulted` | `not consulted`> or "no applicable reference in the catalog".
  For each: conditions it worked under, what transfers, anti-case if any.
- Shines when:
- Breaks when:
- Relative cost (a range or a ratio between candidates, `Source: inferred`, no currency):
- Reversibility:

## Discarded
<!-- One line each, with the reason. A candidate leaves only on a knock-out with evidence, or
     by the user's choice with the reason recorded. -->

## Discriminating questions
<!-- For each pair of candidates, the measurable condition that flips the preference. Most
     important first; the requirements stage measures these first. -->
1. DQ-1: if <measure> is above <N>, <candidate> wins. Ask: <question>.

## Pre-mortem and blind spots
<!-- Twelve months on, it failed: why? Then the lenses of blind-spots.md that found something. -->

## Independent challenge
<!-- The challenger's points and the triage: already answered (and where) / minor, decided by the
     agent (`Source: agent`) / for the user (one round, most important first). -->

## Discussion
<!-- What the user cut, added or elected as the leading hypothesis (a hypothesis, not a
     decision). Or: `Not held - <reason>` with the questions that would have been asked. -->

## Open questions
1.
