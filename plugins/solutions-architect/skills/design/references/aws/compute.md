# Compute - AWS options

Read the aws-core skill `aws-compute` (EC2) and `aws-containers` / `aws-serverless` for the
other platforms before recommending settings.

| Option | Choose when | Avoid when |
|---|---|---|
| ECS on Fargate | long-running HTTP services and workers; small platform team | GPU, privileged containers, per-second billing matters more than simplicity |
| Lambda | event-driven or spiky work, each invocation < 15 min | steady high throughput (cost), long connections, heavy cold-start sensitivity |
| EC2 + Auto Scaling | licensing tied to hosts, special hardware, full OS control | the team cannot patch and harden images |
| EKS | the organisation already runs Kubernetes or needs its ecosystem | a single service with no Kubernetes skills in the team |
| App Runner | a single container web app with minimal configuration | VPC-heavy designs needing fine network control |

Defaults: Graviton (arm64) unless a dependency forbids it; at least two AZs for anything with an
availability NFR; scale on a metric tied to the NFR (request count, queue depth), not on CPU
alone. Anti-patterns: one large instance for "simplicity"; mixing batch and latency-sensitive
work on the same scaling policy.
