# Workflow - stages, artifacts and exit gates

Paths are relative to the workspace (`architecture/` by default). A gate is `pass` only when
every condition in its row holds.

| # | Stage | Skill | Artifact | Exit gate |
|---|---|---|---|---|
| 0 | `discovery` | discovery | `framing.md` | `framing.md` has the intent and why now; goals, non-goals and anti-goals; current state; constraints classified must or prefer; a `Source` on every item; 2-3 candidates plus a contrary one, each with its applicable market references marked `consulted` or `not consulted` (or "no applicable reference in the catalog"); discarded options with reasons; discriminating questions; a pre-mortem; the independent challenger ran and its "for the user" pile is answered or an open question; the candidates discussion is recorded or reads `Not held - <reason>`; `validate_manifest.py` passes |
| 1 | `requirements` | requirements | `requirements.md`, manifest `requirements[]` | Every NFR has a measure or `TBD by <owner>`; RTO/RPO, region(s), monthly budget and data classification recorded |
| 2 | `design` | design | `decisions/NNNN-*.md`, manifest `decisions[]`, `components[]` | In a new design `decisions/0001-direction.md` is accepted and chooses among the discovery candidates (generated in `design` when discovery was skipped); every structural decision has 2+ options and criteria citing NFR ids and cost per business unit; every accepted ADR records its Discussion (user's answer or `Not held - <reason>`, with `Source` on what the user brought) and Revisit when triggers; every market reference is `consulted` or `not consulted` (the latter weigh nothing); every chosen service checked with `aws___get_regional_availability` for every workspace region; `validate_manifest.py` passes |
| 3 | `diagram` | diagram | `diagrams/{topology,network,dataflow-security,dr}.drawio`, `diagrams/*.mmd` | `validate_drawio.py` passes for all four views with `--manifest`; `dr` may be skipped only when requirements say no DR |
| 4 | `finops-compare` | finops | cost rows inside each ADR | Every ADR with a cost impact compares options by monthly list price and cost per business unit, with assumptions written down |
| 5 | `iac` | iac | `<iac_path>/`, `reports/iac-gate.json` | `iac_gate.sh` exit 0 (every sensor `pass`); every suppression justified in the manifest |
| 6 | `finops-estimate` | finops | `finops/estimate.md` | `price_lookup.py` ran on `terraform show -json`; every `not-estimated` or `not-mapped` line is listed, never given a value; total within budget or the overrun recorded in an ADR |
| 7 | `docs` | docs | `README.md`, `executive-summary.md`, `risks.md` | Every relative link resolves; written in the manifest `language` |
| 8 | `review` | review | `reviews/YYYY-MM-DD-review.md` | `validate_manifest.py --strict-trace` passes; the independent reviewer reports no blocker |

After `review` passes, set `stage` to `done`.

`discovery` diverges and never chooses; the first decision of `design` is the direction ADR (`decisions/0001-direction.md`)
between the discovery candidates. A workspace made before v0.3 has no `gates.discovery`: the
`architect` records it as `skipped` ("workspace created before v0.3") and continues, never going
back. `validate_manifest.py` requires `framing.md` next to the manifest whenever
`gates.discovery.status` is `pass`.

A change to an accepted design re-enters at `design` with a new ADR that `supersedes` the old
one; then only the affected views, the IaC gate, the estimate delta and the affected review
sections run again.
