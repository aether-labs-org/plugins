# Generative AI - AWS options

Read the aws-core skills `amazon-bedrock` and `aws-ai-ml`; the official `aws-agents` plugin
covers agents on Bedrock AgentCore.

| Need | Default | Alternatives |
|---|---|---|
| Foundation model access | Bedrock (on-demand) | provisioned throughput for steady high volume |
| Retrieval-augmented generation | Bedrock Knowledge Bases | OpenSearch Serverless or Aurora pgvector when you need custom retrieval |
| Safety | Bedrock Guardrails | - |
| Agents | Bedrock AgentCore | - |

Check model availability per region with `aws___get_regional_availability` - it differs by
model and often decides the region (LGPD residency may force cross-region inference to be
rejected). Cost is per input and output token: record tokens per request and requests per month
as usage assumptions; the price map does not cover Bedrock yet, so these lines are estimated via
discovery (`skills/finops/references/aws/price-discovery.md`).
