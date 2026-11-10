---
type: llm
focus: trace
weight: 3
---
Every company or system the reply cites as a precedent is marked `consulted` (the agent opened
its source in this session) or `not consulted`, and a `not consulted` reference - whether or not
it is in the plugin's benchmark catalog - carries zero weight in the recommendation. There is no
network in this environment, so no reference can be `consulted`: every one must be marked `not
consulted`. For each precedent the reply states the conditions in which it worked (scale, team
size) and what does and does not transfer to this workload, and it never argues "company X does
it, so we should". Where the catalog has an anti-case for the class, the reply mentions it. PASS
only if all hold.
