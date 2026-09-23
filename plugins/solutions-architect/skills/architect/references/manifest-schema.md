# manifest.json - schema 1

The manifest is the only state shared between skills. `scripts/validate_manifest.py` enforces
every rule below.

| Field | Type | Rule |
|---|---|---|
| `schema` | int | `1` |
| `provider` | string | `aws` (the only provider in v0.1) |
| `language` | string | artifact language, e.g. `pt-BR` or `en` |
| `docs_path` | string | workspace directory, default `architecture` |
| `iac_path` | string | Terraform directory, default `infra` |
| `regions` | string[] | first entry is the primary region |
| `stage` | string | `requirements`, `design`, `diagram`, `finops-compare`, `iac`, `finops-estimate`, `docs`, `review`, `done` |
| `gates.<stage>` | object | `{status: pending|pass|fail|skipped, at: YYYY-MM-DD, notes}` |
| `requirements[]` | object | `{id: REQ-nnn|NFR-nnn|CON-nnn, kind, text, measure}`; an NFR needs `measure` |
| `decisions[]` | object | `{id: ADR-nnnn, file, status: proposed|accepted|superseded|rejected, supersedes, addresses: [requirement ids]}`; `file` must exist |
| `components[]` | object | `{id: kebab-case, service, decision: ADR id, terraform: [addresses or module prefixes], diagrams: [views]}` |
| `assumptions` | object | `{currency, hours_per_month, range: {low, high}, business_units: [{name, per_month}], usage: {<component id>: {<metric>: number}}}` |
| `tagging.required` | string[] | tag keys every taggable resource must carry (default Project, Environment, Owner, CostCenter) |
| `suppressions[]` | object | `{check, resource, justification}`; justification 20+ characters; `CKV_TF_1` only with a justification starting `D22:` |
| `dependencies` | object | versions of `aws-core` and tools used, for reproducibility |

Usage metrics the price lookup reads, per component: `storage_gb`, `lcu`, `processed_gb`,
`requests`, `gb_seconds`, `write_request_units`, `read_request_units`, `data_out_gb`, `tasks`,
`ingest_gb`, `stored_gb`. A missing metric makes that line `not-estimated`; it is never guessed.
