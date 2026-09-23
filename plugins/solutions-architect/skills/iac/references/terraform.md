# Terraform layout

```
infra/
├── versions.tf        # required_version and required_providers, exact versions
├── providers.tf       # provider "aws" with region and default_tags
├── main.tf            # modules and resources, grouped by component (comment with component id)
├── variables.tf       # inputs with types and descriptions; no secrets
├── outputs.tf
├── .tflint.hcl        # from assets/tflint.hcl
└── .terraform.lock.hcl  # committed
```

`versions.tf`:

```hcl
terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.66.0"
    }
  }
}
```

`providers.tf`:

```hcl
provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      Owner       = var.owner
      CostCenter  = var.cost_center
    }
  }
}
```

Rules:
- One component per block group, headed by `# component: <manifest id>`.
- State lives in a remote backend the user owns (S3 with native locking); this plugin never
  creates it and never runs `apply`, `import` or `state` subcommands.
- Secrets come from Secrets Manager (`manage_master_user_password = true` for RDS), never from
  variables or `.tfvars` files.
- OpenTofu works the same way; the sensors accept `terraform` only in v0.1.
