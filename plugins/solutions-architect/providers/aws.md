# Provider map - AWS

The method skills stay provider-neutral; everything AWS-specific is reached through this file.
To support another provider, write the same tables for it - no method skill should change (H9).

## Delegation

| Need | AWS source |
|---|---|
| Current documentation, service limits, what's new | `aws___search_documentation`, `aws___read_documentation` (AWS MCP Server, via aws-core) |
| Is a service or feature available in a region? | `aws___get_regional_availability` |
| How to configure a service well | the aws-core skill in the table below |
| Well-Architected pillar review | aws-core skill `aws-well-architected-review` |
| List price | `providers/aws/scripts/price_lookup.py` with `providers/aws/price-map.json`; `aws-pricing` MCP only to discover a new usagetype |
| Diagram icons | `providers/aws/aws4-allowlist.txt`, `skills/diagram/references/aws/aws4-shapes.md` |
| IaC | Terraform `hashicorp/aws` provider + `terraform-aws-modules` (`skills/iac/references/modules.md`) |

## Logical component -> AWS service -> aws-core skill

| Logical component | AWS options (default first) | aws-core skill |
|---|---|---|
| Container runtime | ECS on Fargate, EKS, App Runner | `aws-containers` |
| Functions / event handlers | Lambda | `aws-serverless` |
| Virtual machines | EC2 (Graviton first) with Auto Scaling | `aws-compute` |
| HTTP entry point | ALB, API Gateway HTTP API, CloudFront | `aws-networking`, `aws-serverless` |
| Relational database | Aurora PostgreSQL, RDS PostgreSQL, Aurora DSQL | `aws-database` |
| Key-value / document | DynamoDB, DocumentDB | `aws-database` |
| Cache | ElastiCache (Valkey) | `aws-database` |
| Object / file / block storage | S3, EFS, EBS | `aws-storage` |
| Messaging and streaming | SQS, SNS, EventBridge, Kinesis, MSK | `aws-messaging-and-streaming` |
| Workflow | Step Functions | `aws-serverless` |
| Network | VPC, Transit Gateway, PrivateLink, Route 53 | `aws-networking` |
| Identity and access | IAM, IAM Identity Center | `aws-iam` |
| Secrets | Secrets Manager | `aws-secrets-manager` |
| Security posture | Security Hub, GuardDuty, Inspector | `aws-security` |
| Observability | CloudWatch, X-Ray, ADOT | `aws-observability` |
| Generative AI | Bedrock, Knowledge Bases, Guardrails | `amazon-bedrock`, `aws-ai-ml` |
| CI/CD | CodePipeline or GitHub Actions with OIDC | `aws-deployment` |
| Cost data | Cost Explorer, Budgets | `aws-billing-and-cost-management` |
