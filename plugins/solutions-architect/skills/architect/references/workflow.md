# Workflow - stages, artifacts and exit gates

Paths are relative to the workspace (`architecture/` by default). A gate is `pass` only when
every condition in its row holds.

| # | Stage | Skill | Artifact | Exit gate |
|---|---|---|---|---|
| 1 | `requirements` | requirements | `requirements.md`, manifest `requirements[]` | Every NFR has a measure or `TBD by <owner>`; RTO/RPO, region(s), monthly budget and data classification recorded |
| 2 | `design` | design | `decisions/NNNN-*.md`, manifest `decisions[]`, `components[]` | Every structural decision has 2+ options and criteria citing NFR ids and cost per business unit; every accepted ADR records its Discussion (user's answer or `Not held - <reason>`) and Revisit when triggers; every chosen service checked with `aws___get_regional_availability` for every workspace region; `validate_manifest.py` passes |
| 3 | `diagram` | diagram | `diagrams/{topology,network,dataflow-security,dr}.drawio`, `diagrams/*.mmd` | `validate_drawio.py` passes for all four views with `--manifest`; `dr` may be skipped only when requirements say no DR |
| 4 | `finops-compare` | finops | cost rows inside each ADR | Every ADR with a cost impact compares options by monthly list price and cost per business unit, with assumptions written down |
| 5 | `iac` | iac | `<iac_path>/`, `reports/iac-gate.json` | `iac_gate.sh` exit 0 (every sensor `pass`); every suppression justified in the manifest |
| 6 | `finops-estimate` | finops | `finops/estimate.md` | `price_lookup.py` ran on `terraform show -json`; every `not-estimated` or `not-mapped` line is listed, never given a value; total within budget or the overrun recorded in an ADR |
| 7 | `docs` | docs | `README.md`, `executive-summary.md`, `risks.md` | Every relative link resolves; written in the manifest `language` |
| 8 | `review` | review | `reviews/YYYY-MM-DD-review.md` | `validate_manifest.py --strict-trace` passes; the independent reviewer reports no blocker |

After `review` passes, set `stage` to `done`.

A change to an accepted design re-enters at `design` with a new ADR that `supersedes` the old
one; then only the affected views, the IaC gate, the estimate delta and the affected review
sections run again.
