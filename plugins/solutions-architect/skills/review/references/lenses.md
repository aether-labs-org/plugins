# Lenses - apply when the trigger matches

| Lens | Trigger | Extra questions |
|---|---|---|
| Serverless Applications | Lambda, API Gateway, Step Functions or EventBridge in the design | idempotency, DLQs, reserved concurrency, cold-start budget, timeouts shorter upstream than downstream |
| SaaS | more than one tenant shares the system | tenant isolation model, noisy-neighbour controls, per-tenant cost attribution, onboarding automation |
| Generative AI | Bedrock or another model endpoint | guardrails, prompt/response logging vs personal data, model availability per region, token budget and cost per request |
| Data Analytics | data lake, ETL or BI components | data classification per layer, lineage, access through Lake Formation, cost of scans |
| Container Build | ECS or EKS | image provenance and scanning, immutable tags, task sizing from load tests, graceful shutdown |

Each finding cites the lens, the question, the artifact that answers it (or its absence) and a
recommendation.
