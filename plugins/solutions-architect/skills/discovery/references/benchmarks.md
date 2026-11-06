# Market reference catalog

An index of links to open, nothing more. It holds no summaries and no reference cards: the
`reference-reader` agent opens the links you choose and returns the card for this workload (see
`SKILL.md` step 5). Every entry was opened on the access date shown. Nothing here is a criterion
by itself - read the rules in `${CLAUDE_PLUGIN_ROOT}/skills/design/references/trade-offs.md`
(B1, B2) before weighing a reference.

Rules for using it:

- Pick the few links the case needs from the "Open when" column; do not open the whole catalog.
- A source published more than five years before the day you use it is flagged: check that the
  strategy still holds. Undated pages are flagged the same way.
- The two SRE book entries show 2017, the copyright year printed on the pages; the printed edition
  is from 2016.
- Only a link opened in this session counts (`consulted`). Otherwise the reference is
  `not consulted` and carries no weight.
- A link outside this catalog is used only with the user's agreement in the session.
- `anti-case` marks a source about someone who dropped or avoided the pattern; use it when the
  candidate is a high-adoption-cost pattern (microservices, event sourcing, multi-region
  active-active, service mesh, cells).
- Check that the links still open with `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/check_links.py`
  (needs network; run it by hand or on a schedule, not in the test suite).

Columns: Title | Kind | Company | Published | Accessed | Link | Open when.

## Failure isolation and resilience

| Title | Kind | Company | Published | Accessed | Link | Open when |
|---|---|---|---|---|---|---|
| Reducing the Scope of Impact with Cell-Based Architecture | pattern | Amazon Web Services | 2023-09-20 | 2026-11-06 | https://docs.aws.amazon.com/wellarchitected/latest/reducing-scope-of-impact-with-cell-based-architecture/reducing-scope-of-impact-with-cell-based-architecture.html | a candidate partitions customers or tenants to limit the blast radius of a failure |
| Workload isolation using shuffle-sharding | pattern | Amazon Web Services | 2019-12-05 | 2026-11-06 | https://builder.aws.com/content/3F06NpJ8YeoIGP8VHTw4n81pFn8/workload-isolation-using-shuffle-sharding | one noisy or poisonous client must not take down every other client of a shared service |
| Static stability using Availability Zones | pattern | Amazon Web Services | 2019-12-05 | 2026-11-06 | https://builder.aws.com/content/3K9SiqiJ369TGkkGzqPM95BuYWI/static-stability-using-availability-zones | recovery must not depend on a control plane that may itself be impaired |
| Timeouts, retries, and backoff with jitter | pattern | Amazon Web Services | 2019-12-05 | 2026-11-06 | https://builder.aws.com/content/3EumjoZascWd1oZiEgL8ORlv3qE/timeouts-retries-and-backoff-with-jitter | a candidate has synchronous calls between components and retries could amplify an outage |
| Slack's Migration to a Cellular Architecture | strategy | Slack | 2023-08-22 | 2026-11-06 | https://slack.engineering/slacks-migration-to-a-cellular-architecture/ | a cell-based candidate needs a real migration story and its costs |

## Decomposition and coupling

| Title | Kind | Company | Published | Accessed | Link | Open when |
|---|---|---|---|---|---|---|
| Deconstructing the Monolith: Designing Software that Maximizes Developer Productivity | strategy | Shopify | 2019-02-21 | 2026-11-06 | https://shopify.engineering/deconstructing-monolith-designing-software-maximizes-developer-productivity | a modular monolith is a candidate, or the team is small relative to the number of services proposed |
| Introducing Domain-Oriented Microservice Architecture | strategy | Uber | 2020-07-23 | 2026-11-06 | https://www.uber.com/en-US/blog/microservice-architecture/ | a candidate has many services and the question is how to group and constrain their dependencies |
| Goodbye Microservices: From 100s of problem children to 1 superstar | anti-case | Segment (Twilio) | 2018-07-10 | 2026-11-06 | https://www.twilio.com/en-us/blog/developers/best-practices/goodbye-microservices | a microservices candidate exists and the team or the domain boundaries are not yet mature |
| Introducing istiod: simplifying the control plane | anti-case | Istio project | 2020-03-19 | 2026-11-06 | https://istio.io/latest/blog/2020/istiod/ | a candidate splits a system into many separately deployed parts that always change and scale together |

## Data and consistency

| Title | Kind | Company | Published | Accessed | Link | Open when |
|---|---|---|---|---|---|---|
| Designing robust and predictable APIs with idempotency | pattern | Stripe | 2017-02-22 | 2026-11-06 | https://stripe.com/blog/idempotency | an API creates orders, payments or other effects that a client may retry |
| How Figma's Databases Team Lived to Tell the Scale | strategy | Figma | 2024-03-14 | 2026-11-06 | https://www.figma.com/blog/how-figmas-databases-team-lived-to-tell-the-scale/ | a single relational database is nearing its limits and sharding is on the table |

## Integration and events

| Title | Kind | Company | Published | Accessed | Link | Open when |
|---|---|---|---|---|---|---|
| Transactional outbox pattern | pattern | Amazon Web Services | undated | 2026-11-06 | https://docs.aws.amazon.com/prescriptive-guidance/latest/cloud-design-patterns/transactional-outbox.html | a service writes to its database and must also publish an event without losing one of the two |
| Saga orchestration pattern | pattern | Amazon Web Services | undated | 2026-11-06 | https://docs.aws.amazon.com/prescriptive-guidance/latest/cloud-design-patterns/saga-orchestration.html | a business transaction spans services that each own their data |

## Scale

| Title | Kind | Company | Published | Accessed | Link | Open when |
|---|---|---|---|---|---|---|
| How Discord Stores Trillions of Messages | strategy | Discord | 2023-03-06 | 2026-11-06 | https://discord.com/blog/how-discord-stores-trillions-of-messages | a data store must absorb very high write volume with predictable latency |
| Using load shedding to avoid overload | pattern | Amazon Web Services | 2019-12-05 | 2026-11-06 | https://builder.aws.com/content/3Eun1EEyX6p2e3VYNyRLSJzLuMV/using-load-shedding-to-avoid-overload | the peak is far above the normal load and the system must degrade instead of collapsing |

## Operations and SRE

| Title | Kind | Company | Published | Accessed | Link | Open when |
|---|---|---|---|---|---|---|
| Service Level Objectives (SRE book, chapter 4) | strategy | Google | 2017 | 2026-11-06 | https://sre.google/sre-book/service-level-objectives/ | availability or latency targets are vague and need indicators, objectives and agreements |
| Embracing Risk (SRE book, chapter 3) | strategy | Google | 2017 | 2026-11-06 | https://sre.google/sre-book/embracing-risk/ | the cost of extra nines must be weighed against the pace of change (error budgets) |
| Principles of Chaos Engineering | strategy | Chaos Community | 2019-03 | 2026-11-06 | https://principlesofchaos.org/ | resilience is claimed but never exercised, and failure experiments are being considered |

## Cost and platform

| Title | Kind | Company | Published | Accessed | Link | Open when |
|---|---|---|---|---|---|---|
| Completing the Netflix Cloud Migration | strategy | Netflix | 2016-02-12 | 2026-11-06 | https://about.netflix.com/en/news/completing-the-netflix-cloud-migration | the question is whether to be in the cloud at all, or why a company with large, spiky load chose it (the page says cost was a secondary benefit) |
| Cost Optimization Pillar - Well-Architected Framework | strategy | Amazon Web Services | 2024-06-27 | 2026-11-06 | https://docs.aws.amazon.com/wellarchitected/latest/cost-optimization-pillar/welcome.html | cost is a goal and the question is how to practise cost management in the cloud (a vendor view, so weigh it as one) |
| Why we're leaving the cloud | anti-case | 37signals | 2022-10-19 | 2026-11-06 | https://world.hey.com/dhh/why-we-re-leaving-the-cloud-654b47e0 | steady, predictable load makes the cloud premium hard to justify |
| Our cloud-exit savings will now top ten million over five years | anti-case | 37signals | 2024-10-17 | 2026-11-06 | https://world.hey.com/dhh/our-cloud-exit-savings-will-now-top-ten-million-over-five-years-c7d9b5bd | the user wants numbers from someone who left the cloud, to compare conditions |

## Migration

| Title | Kind | Company | Published | Accessed | Link | Open when |
|---|---|---|---|---|---|---|
| Strangler fig pattern | pattern | Amazon Web Services | undated | 2026-11-06 | https://docs.aws.amazon.com/prescriptive-guidance/latest/cloud-design-patterns/strangler-fig.html | a legacy system must be replaced gradually behind a routing layer |
| Modernizing Legacy Applications with Event-Driven Architecture: The Leave-and-Layer Pattern | pattern | Amazon Web Services | 2025-11-06 | 2026-11-06 | https://aws.amazon.com/blogs/migration-and-modernization/modernizing-legacy-applications-with-event-driven-architecture-the-leave-and-layer-pattern/ | the legacy system cannot be changed, so new behaviour is built around it from its events |
