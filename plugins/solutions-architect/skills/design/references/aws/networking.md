# Networking - AWS options

Read the aws-core skill `aws-networking` before choosing settings.

| Decision | Default | Alternatives and when |
|---|---|---|
| VPC layout | one VPC per environment, /16, public + private subnets in 2-3 AZs | shared VPC via RAM for many small accounts |
| Egress | one NAT Gateway per AZ for production; one shared NAT for non-production | VPC endpoints (S3, DynamoDB gateway endpoints are free) to cut NAT data charges |
| Service access | gateway/interface VPC endpoints for AWS services used from private subnets | NAT only for internet egress |
| Multi-VPC / hybrid | Transit Gateway | VPC peering for 2-3 VPCs; Cloud WAN for global networks |
| Entry point | ALB for HTTP services, CloudFront in front for public content | API Gateway HTTP API for serverless APIs; NLB for TCP/UDP |
| DNS | Route 53 private and public hosted zones | - |

Plan CIDRs so they never overlap across environments or on-premises. Every public entry point
gets AWS WAF when it serves internet users. Each NAT Gateway also bills a public IPv4 address.
