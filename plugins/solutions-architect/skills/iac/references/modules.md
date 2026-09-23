# terraform-aws-modules - pinned versions (decision D18)

Pin the **exact** version; `.terraform.lock.hcl` pins the provider. checkov `CKV_TF_1` (commit
hash) is suppressed once, globally, with a manifest justification starting `D22:`.

| Need | Module source | Version |
|---|---|---|
| VPC, subnets, NAT, endpoints | `terraform-aws-modules/vpc/aws` | 6.7.3 |
| Security groups | `terraform-aws-modules/security-group/aws` | 6.0.0 |
| Application Load Balancer | `terraform-aws-modules/alb/aws` | 10.5.1 |
| ECS cluster and services | `terraform-aws-modules/ecs/aws` | 7.6.1 |
| EKS | `terraform-aws-modules/eks/aws` | 21.25.3 |
| Lambda | `terraform-aws-modules/lambda/aws` | 8.8.2 |
| API Gateway v2 | `terraform-aws-modules/apigateway-v2/aws` | 6.1.1 |
| RDS | `terraform-aws-modules/rds/aws` | 7.2.2 |
| Aurora | `terraform-aws-modules/rds-aurora/aws` | 10.4.1 |
| DynamoDB | `terraform-aws-modules/dynamodb-table/aws` | 5.5.2 |
| ElastiCache | `terraform-aws-modules/elasticache/aws` | 1.11.1 |
| S3 | `terraform-aws-modules/s3-bucket/aws` | 5.16.1 |
| CloudFront | `terraform-aws-modules/cloudfront/aws` | 6.7.1 |

Versions checked on 2026-09-22 against registry.terraform.io; the quarterly freshness check in
the repository reports newer releases. Upgrade by changing the version, re-running the gate and
recording the upgrade in the pull request.

The price map knows the resource types these modules create (for example
`module.vpc.aws_nat_gateway.this[0]` and `module.vpc.aws_eip.nat[0]`); map the module prefix to
the component in `manifest.components[].terraform`.
