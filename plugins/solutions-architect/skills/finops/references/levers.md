# FinOps levers (recommendations only - not applied to the list price)

| Lever | Applies to | Pays off when |
|---|---|---|
| Compute Savings Plans (1 or 3 years) | EC2, Fargate, Lambda | steady baseline usage known for 3+ months |
| Reserved Instances / reserved nodes | RDS, Aurora, ElastiCache, OpenSearch | the instance class is stable for 1+ year |
| Graviton (arm64) | EC2, Fargate, Lambda, RDS, ElastiCache | dependencies support arm64; typically lower price per vCPU |
| Right-sizing | any provisioned capacity | utilisation stays below 40% at peak |
| Scheduling | non-production environments | environments idle outside business hours |
| Spot capacity | stateless, interruption-tolerant workers | work can be retried |
| Storage tiering | S3 (Intelligent-Tiering, lifecycle), EBS gp2 -> gp3 | access frequency drops with age |
| VPC gateway endpoints | S3 and DynamoDB traffic from private subnets | NAT data processing is a visible line |
| DynamoDB provisioned capacity | tables with steady, predictable traffic | on-demand cost exceeds provisioned at observed load |
| Log retention | CloudWatch Logs | stored GB grows without a retention policy |

Guardrails to generate as Terraform (never applied by this plugin): AWS Budgets with alerts at
80% and 100% of the monthly ceiling, and Cost Anomaly Detection monitors. Tag every resource
with the manifest `tagging.required` keys so cost can be allocated.
