---
type: llm
focus: { source: file, path: architecture/diagrams/network.drawio }
weight: 2
---
The draw.io XML shows VPC 10.0.0.0/16 with at least two availability zones, each with a public
and a private subnet; the ALB sits in public subnets, the ECS tasks and the Aurora cluster in
private subnets, and there is NAT egress. PASS only if all hold.
