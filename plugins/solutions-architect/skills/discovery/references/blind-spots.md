# Blind-spot lenses

Run the pre-mortem first: "It is twelve months from now and this solution failed. Why?" Write
the three most likely reasons per candidate. Then invert: "What would we have to believe for the
candidate we discarded first to be the right one?" Then pass every candidate through these
lenses. A lens that finds nothing is skipped; a lens that finds something becomes a line in the
framing under "Pre-mortem and blind spots" with the candidate it hits and what is missing.

| Lens | Ask | A gap looks like |
|---|---|---|
| Team and Conway | Who builds, runs and is paged for each part? Does the structure of the solution match the structure of the team? | More deployable parts than people on call; a skill the candidate needs that nobody has |
| Data | Where does the data live and who owns it? What is the gravity (size, who reads it)? How does it move from where it is today? | A shared database nobody mentioned; a migration with no rollback; reports reading production tables |
| Failure and blast radius | What fails together? What does one bad deploy, one bad tenant or one dead dependency take down? | One shared component on every request path; retries that amplify |
| Quotas and limits | Which service quota, rate limit or per-account ceiling does the peak reach? | A limit that is lower than the forecast peak; a limit raised by a ticket that takes weeks |
| Change and exit cost | What does it cost to change this decision in 12 months, or to leave the service? | Proprietary data formats; an integration style that hard-wires callers |
| Cost curve and steps | How does cost grow with load? Where are the step changes (minimum capacity, per-request tiers, data transfer)? | A fixed floor that dominates at low volume; a per-request price that explodes at the peak |
| Identity and trust boundaries | Who may call what? Where does data cross a trust boundary or an account? | Service-to-service calls with no identity; a partner integration inside the trusted zone |
| LGPD and residency | Which personal data is involved, where does it live and flow, who is the operator, what is the retention? | A managed service or a backup in a region the data may not leave |
| Migration and coexistence | How do old and new run side by side? What is the cutover, and how is it undone? | A big-bang weekend; two writers for the same data |
| Operation | Who sees a failure first, with which signal? How is it deployed, rolled back, restored? | No metric for the NFR that matters; a restore never rehearsed |

Questions that come out of a lens are either answered with evidence you can name (`Source:
inferred`), asked to the user, or recorded as an open question. A lens is never closed with "the
team will handle it".
