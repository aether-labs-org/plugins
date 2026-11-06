# Method checks

| # | Check | Pass when | Evidence |
|---|---|---|---|
| 1 | NFR coverage | `validate_manifest.py --strict-trace` passes | manifest |
| 2 | Alternatives and discussion | every accepted ADR lists 2+ options with scored criteria citing NFR ids, a Trade-offs table, a Discussion section and Revisit when triggers; each ADR whose Discussion reads `Not held` is listed as a risk | `decisions/` |
| 3 | Regional availability | every ADR states availability for every workspace region | `decisions/` |
| 4 | DR matches RTO/RPO | the DR strategy's recovery time and data loss meet the recorded RTO/RPO | `dr.drawio`, DR ADR, requirements |
| 5 | Stateful components | every database, cache with persistence, and bucket with unrecreatable data has backup or versioning and a retention decision | ADRs, `infra/` |
| 6 | Multi-AZ | every component on an availability NFR path runs in 2+ AZs | `network.drawio`, `infra/` |
| 7 | Dependency failure | every call to another component or external system has a timeout, retry with backoff, and a fallback or circuit breaker decision | ADRs, data-flow view |
| 8 | Personal data | where it lives, encryption with KMS, residency region, retention and deletion are decided (LGPD) | data-flow view, ADRs |
| 9 | IaC gate | `reports/iac-gate.json` status `pass`; suppressions justified | report, manifest |
| 10 | Cost | estimate within budget, unpriced lines listed, unit cost reported | `finops/estimate.md` |
| 11 | Observability | every NFR with a measure has a metric and an alarm decided | ADRs, `infra/` |
| 12 | Skipped gates | every `skipped` gate is listed as a risk | manifest, `risks.md` |
| 13 | Anti-goals | no accepted ADR violates an anti-goal of `framing.md`; a violation is a blocker unless an ADR records the user's override with `Source: user`, quotes the text of the anti-goal it overrides and states the risk accepted (a bare `Source: user` on the choice is not an override). Not applicable without a `framing.md` | `framing.md`, `decisions/` |
| 14 | Market references | every market reference in an ADR or in `framing.md` is marked `consulted` or `not consulted`; none marked `not consulted` (or unmarked) changes a score or a recommendation | `decisions/`, `framing.md` |
| 15 | Direction ADR | in a design made after v0.3 with `gates.discovery` `pass`, `decisions/0001-direction.md` exists, is accepted and chooses among the candidates of `framing.md`, including the contrary one. Not applicable when `gates.discovery` is `skipped` | `decisions/`, `framing.md` |
| 16 | Critical stance | a preference the user brought ready-made appears as one option beside a scored contrary option, and its ADR records `Source: user`; no ADR shows a recommendation changed without new evidence | `decisions/` |
