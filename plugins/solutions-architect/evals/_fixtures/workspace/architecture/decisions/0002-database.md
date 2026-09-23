# ADR-0002: Aurora PostgreSQL Multi-AZ with cross-region snapshot copy

- Status: accepted
- Addresses: NFR-003

## Options considered
| Option | Regional availability (sa-east-1, us-east-1) | Knock-out? |
|---|---|---|
| Aurora PostgreSQL | available in both | no |
| RDS PostgreSQL Multi-AZ | available in both | no |

## Decision
Aurora PostgreSQL in sa-east-1 (writer + reader in two AZs, private subnets 10.0.1.0/24 and
10.0.2.0/24 of VPC 10.0.0.0/16). Backups every 5 minutes (PITR); snapshots copied to us-east-1
every 15 minutes as the DR copy (warm data, cold compute): RPO 15 min, RTO 1 h.
