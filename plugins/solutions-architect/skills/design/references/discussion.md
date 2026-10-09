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
   build). An option killed by a knock-out (`references/trade-offs.md`) is shown as rejected,
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
- The answer brings a new constraint or option → update the options and run the round again.

## 5. When the user asked not to be asked

Briefs that say "do not ask me anything", or runs without a user, still get the analysis:
accept the recommendation, and write in the ADR `Discussion` section
`Not held - <reason>` followed by the questions you would have asked. The `review` lists every
such ADR as a risk.

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
