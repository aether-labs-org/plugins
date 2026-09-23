# Serverless - AWS options

Read the aws-core skill `aws-serverless` before choosing settings.

| Need | Default | Alternatives |
|---|---|---|
| HTTP API | API Gateway HTTP API + Lambda | REST API when usage plans, API keys or request validation are needed |
| Async work | SQS + Lambda | EventBridge Pipes; Step Functions for multi-step workflows |
| Orchestration | Step Functions (Standard for long, Express for high-volume short) | - |
| Scheduling | EventBridge Scheduler | - |

Decide per function: memory (it sets CPU and price), timeout, reserved concurrency (protects
downstream systems), dead-letter queue, idempotency key. Put requests per month and GB-seconds
in the usage assumptions; they drive the estimate.
