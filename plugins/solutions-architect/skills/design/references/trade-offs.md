# Trade-off analysis

1. **Criteria come from requirements.** Each criterion names the NFR or constraint it serves
   (`NFR-002 availability 99.95%`). Add `cost per <business unit>` and `operational effort`
   to every decision.
2. **Weights** add up to 100 and are agreed with the user when they are not obvious.
3. **Score** each option 1-5 per criterion with a one-line reason; a score without a reason is
   removed.
4. **Knock-outs first.** An option that violates a constraint (`CON-*`), is unavailable in a
   required region, or cannot meet an NFR measure is rejected before scoring.
5. **Consequences** list what becomes easier and what becomes harder, including lock-in and
   the skills the team will need.
6. **Reversibility.** Say how expensive it would be to change the decision in 12 months; prefer
   the cheaper-to-reverse option when scores are close (within 10%).
7. **A contrary option.** Every decision includes at least one option that is not the obvious
   one (defer, simpler or more managed, different paradigm); scoring it is how the obvious
   choice earns its place.
8. **Sensitivity.** Move each weight by ±10 points: if the winner changes, say which weight
   flips it and put that weight to the user in the discussion round.
9. **Revisit triggers.** Write the measurable events that reopen the decision (load above
   N req/s, cost per order above X, a service reaching a region) - they go in the ADR.
