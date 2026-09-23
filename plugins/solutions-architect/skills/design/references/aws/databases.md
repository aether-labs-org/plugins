# Databases - AWS options

Read the aws-core skill `aws-database`; it routes to one reference per engine.

| Access pattern | Default | Alternatives and when |
|---|---|---|
| Relational, OLTP | Aurora PostgreSQL | RDS PostgreSQL when cost matters more than failover time; Aurora DSQL for active-active multi-region |
| Key-value at any scale | DynamoDB on-demand | provisioned capacity once traffic is steady and known |
| Document | DynamoDB | DocumentDB when MongoDB compatibility is required |
| Cache / session | ElastiCache (Valkey) | DAX for DynamoDB-only read caching |
| Graph | Neptune | - |
| Time series | Timestream | - |
| Analytics | Athena on S3 / Redshift | see `data.md` |

Always decide: Multi-AZ (availability NFR), backup retention (RPO), encryption with KMS
(personal data), and how the schema evolves. Multi-AZ doubles instance cost - put it in the
ADR's cost comparison.
