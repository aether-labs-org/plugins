# Quality-attribute scenario

Write every NFR in six parts so it can be tested:

| Part | Question | Example |
|---|---|---|
| Source | Who or what triggers it? | Customers on mobile |
| Stimulus | What happens? | submit 1,000 orders per second |
| Artifact | Which part of the system? | order API and database |
| Environment | Under which conditions? | campaign peak, one AZ unavailable |
| Response | What must the system do? | accept and persist every order |
| Measure | How do we know? | p95 < 500 ms, 0 lost orders |

One-line form for `requirements.md` and `manifest.requirements[].measure`:
`<source> <stimulus> on <artifact> during <environment> -> <response>, <measure>`.
