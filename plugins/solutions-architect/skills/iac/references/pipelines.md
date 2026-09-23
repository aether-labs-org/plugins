# CI/CD for the Terraform

Recommend this; the plugin never creates pipelines in the user's account.

- **Authentication:** GitHub Actions OIDC (or CodePipeline with a service role). No long-lived
  access keys anywhere.
- **Pull request:** `terraform fmt -check`, `init`, `validate`, `tflint`, `checkov`,
  `plan -lock=false`, and the list-price delta (`price_lookup.py --side before/after`) posted
  as a comment.
- **Main branch:** `plan` with a lock, a required human approval, then `apply` of that saved
  plan by the pipeline role - the only identity allowed to change the account.
- **Roles:** the plan role is read-only (`ReadOnlyAccess` on state and resources); the apply
  role is separate and trusted only by the main-branch workflow.
