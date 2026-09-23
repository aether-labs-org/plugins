# Method checks

| # | Check | Pass when | Evidence |
|---|---|---|---|
| 1 | NFR coverage | `validate_manifest.py --strict-trace` passes | manifest |
| 2 | Alternatives | every accepted ADR lists 2+ options with scored criteria citing NFR ids | `decisions/` |
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
