# Discussing a decision with the user

A decision the user never saw is the agent's opinion. Before an ADR is accepted, the user sees
the alternatives, what each one costs and gives up, and what would change the recommendation.

## 1. Classify impact

- **High** - expensive or slow to reverse (data store, compute platform, integration style,
  network layout, DR strategy, identity), a relevant share of the cost per business unit, or on
  the path of an NFR measure.
- **Low** - everything else (log retention, instance family within a platform, naming).

When unsure, it is high.

## 2. High-impact round - one decision per message

Write it in the manifest `language`, short enough to read in a minute:

1. **Problem** in two lines and the requirement ids at stake (`NFR-002`, `CON-001`).
2. **Options**, 2 to 4. At least one is **not the obvious one**: defer or do without, a simpler
   or more managed service, or a different paradigm (events instead of calls, buy instead of
   build). An option killed by a knock-out (`${CLAUDE_PLUGIN_ROOT}/skills/design/references/trade-offs.md`) is shown as rejected,
   with the reason.
3. For each option, **Gains / Gives up**: cost per business unit (order of magnitude),
   operational effort, lock-in, reversibility, skills the team needs.
4. **Recommendation** and confidence (high / medium / low), in one sentence tied to the drivers.
5. **What would change my mind** - the conditions under which another option wins
   ("if the peak goes above 2,000 req/s, B wins").
6. **One or two questions** whose answer could change the outcome - challenge an assumption,
   do not ask for permission ("Does the team already run Kafka in production?").

Then **stop and wait for the answer**. Do not write the ADR in the same message.

## 3. Low-impact round - all of them in one message

A numbered list: decision, recommendation, the one trade-off that matters, in one line each.
The user approves the list or pulls any item into its own high-impact round.

## 4. After the answer

- The user picks an option → record it, with their reason, in the ADR `Discussion` section.
- The user picks an option that a knock-out rejects or that misses an NFR measure → say so
  **once**, with the evidence (requirement id, availability check, price). If they keep it,
  record their reason and the risk; do not argue again.
- The user brings a solution ready-made ("we use X, go ahead") → rule R2 below: it becomes a
  hypothesis before it becomes an option.
- The user disagrees and brings no evidence or constraint → rule R3 below: the recommendation
  does not move.
- The answer brings a new constraint or option → update the options and run the round again.

## 5. When the user asked not to be asked

Briefs that say "do not ask me anything", or runs without a user, still get the analysis:
accept the recommendation - or the option the user explicitly chose (R3), recorded with
`Source: user` and the risk it accepts - and write in the ADR `Discussion` section
`Not held - <reason>` followed by the questions you would have asked. The `review` lists every
such ADR as a risk. A preference the user brought is still scored against the contrary option
(R2); only the discussion is skipped, never the analysis.

## 6. Critical stance

The goal is a recommendation that survives contact with the facts, not one the user likes. These
rules apply every time you discuss, analyse or review a decision.

| # | Rule |
|---|---|
| R1 | **Mark the source.** Every constraint, preference, assumption and decision carries `Source: user` (the user said it), `inferred` (you deduced it from evidence you can name), `default` (a plugin default) or `agent` (your own decision). A guess of yours never appears as a decision of the user. |
| R2 | **A solution brought ready-made is a hypothesis.** Ask whether it is mandatory (it becomes a `CON-nnn` with its source) or a preference (it becomes one option among 2+, with the contrary option scored). When the discussion is `Not held`, the preference is still one option, the contrary option is still scored, and the ADR records `Source: user` for the preference. |
| R3 | **The recommendation changes only with new evidence or a new constraint.** Disagreement alone is neither. Restate the recommendation once with the evidence; if the user keeps their choice, record it with `Source: user` and the risk it accepts, and leave the scores as they were. |
| R4 | **Steelman.** For a high-impact decision, state the best argument for the runner-up, even when the user agrees quickly. Agreement is not a reason to skip it. |
| R5 | **Market references are consulted or they do not count.** See `${CLAUDE_PLUGIN_ROOT}/skills/design/references/trade-offs.md` (B1 and B2): a reference carries `consulted` or `not consulted`, and a `not consulted` one never changes a score or the recommendation. |
| R6 | **Consultation.** A one-off question ("SNS or EventBridge for this?") gets the problem in a line, the options, what each gains and gives up, a recommendation with its confidence, and what would change your mind. No workspace is created and no stage runs; end by offering to open a workspace if the question is part of a larger design. |

Red flags - if you catch yourself thinking one of these, stop and apply the rule:

| Thought | Reality |
|---|---|
| "The user already decided; I only need to record it." | A decision with no scored alternative is an assumption (R2). Score the contrary option, then record. |
| "Agreeing saves a round." | The round is where the cost of the choice becomes visible. State the runner-up (R4). |
| "Big tech X uses it, so it fits." | It proves X's conditions, not ours. Compare conditions or leave it out (B1). |
| "They disagreed, so I must have been wrong." | Disagreement is not evidence (R3). Ask what changed; if nothing, restate once and record. |
| "I'll write it as the user's choice to keep it simple." | If you deduced it, it is `inferred` (R1). |

## Trade-off pairs that start a good discussion

| Pair | Typical question |
|---|---|
| Consistency x availability | What does the user see if the write region is down? |
| Managed x control | Which knob would we miss, and how often do we turn it? |
| Cost x resilience | How much is one hour of downtime worth, against the monthly delta? |
| Latency x cost | Does p95 move a business metric, or only a dashboard? |
| Build x buy | Is this capability a differentiator, or plumbing? |
| Coupling x simplicity | Who else changes when this changes? |
| Time to market x lock-in | What does leaving cost in 12 months? |
