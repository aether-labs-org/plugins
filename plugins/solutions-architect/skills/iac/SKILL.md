---
name: iac
description: >
  Generates Terraform for an AWS solution from its accepted decisions - terraform-aws-modules
  pinned to exact versions, required tags, secure defaults - and runs the IaC gate (fmt,
  validate, tflint, checkov, tags). Never applies. Use when turning an architecture into
  Terraform, or to check Terraform that an agent or a person wrote.
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/iac_gate.sh *)
---

# IaC

Terraform is written from **accepted** ADRs only, and it is finished when the gate is green -
not when it looks right. **This skill never runs `terraform apply`**; the hook denies it
(decision D13). The deliverable is code, a plan and a green gate; a human or a pipeline applies.

## Procedure

1. Read the accepted ADRs and `manifest.components`. If a component has no accepted ADR, stop
   and send the user back to the `design` skill.
2. Lay out `<iac_path>` (default `infra/`) as `references/terraform.md` describes: pinned
   `versions.tf`, a provider block with `default_tags` for every key in
   `manifest.tagging.required`, and `.tflint.hcl` copied from `assets/tflint.hcl`.
3. Use the modules and exact versions in `references/modules.md`; write raw resources only where
   no module fits, and say why in a comment. Check provider arguments with the `terraform` MCP
   (`hashicorp/terraform-mcp-server`) and service settings with the matching aws-core skill.
4. Apply secure defaults from the start: encryption at rest with KMS for personal data, no public
   buckets, deletion protection and backups on stateful resources, least-privilege IAM, logs on
   load balancers and databases. Each default you **cannot** apply needs an inline
   `#checkov:skip=<ID>:<reason>` in that resource **and** a manifest `suppressions[]` entry with
   the same reason, backed by an ADR.
5. Record the resource addresses of each component in `manifest.components[].terraform`
   (module prefixes such as `module.vpc` are fine).
6. Produce the plan JSON (read-only; `-lock=false` is required by the hook):

   ```bash
   terraform -chdir=infra init -input=false
   terraform -chdir=infra plan -lock=false -input=false -out=tf.plan
   terraform -chdir=infra show -json tf.plan > infra/plan.json
   ```

   For a greenfield workspace with no account access yet, `-refresh=false` avoids reading
   state that does not exist.
7. Run the gate and fix until it is green:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/iac_gate.sh infra architecture/manifest.json infra/plan.json
   ```

   Each sensor prints `id<TAB>class<TAB>status<TAB>summary`, detail lines and, on failure, a
   `guidance:` block - follow it. The gate writes `architecture/reports/iac-gate.json`. Exit 2
   (`incomplete`) means a mandatory tool is missing: tell the user which and how to install it;
   the gate is not green until it runs.
8. For CI, propose the workflow in `references/pipelines.md` (plan on pull request, apply only
   through the pipeline with approval).

## Suppressions

checkov OSS reports no severity, so every unsuppressed failure blocks. The only global skip is
`CKV_TF_1` (modules pinned by registry version instead of commit hash, decision D22), with the
manifest justification starting `D22:`. Everything else is fixed or suppressed inline with a
reason an ADR supports.

## Exit gate

`iac_gate.sh` exits 0 and every suppression is justified in the manifest.
