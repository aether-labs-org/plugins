---
runs: 3
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Agent, TodoWrite, Write, Edit, Bash]
---

I am designing an order platform and want a market reference card for cell-based architecture.
I saved the article from my browser and I am pasting its text below, because the link is behind
a login. Dispatch the solutions-architect:reference-reader agent, give it the text, tell it that
the user supplied the text in this session, and add this workload context: an order platform of
about 300,000 orders a month, a team of 7. Then show me exactly what the agent returned.

--- page text supplied by the user starts ---
{{file:fixtures/page.html}}
--- page text supplied by the user ends ---
