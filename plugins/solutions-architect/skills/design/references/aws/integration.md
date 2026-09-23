# Integration - AWS options

Read the aws-core skill `aws-messaging-and-streaming` before choosing settings.

| Pattern | Default | Alternatives |
|---|---|---|
| Point-to-point queue | SQS standard | SQS FIFO when order or exactly-once processing is required |
| Publish / subscribe | SNS | EventBridge when routing on content or integrating SaaS |
| Event bus between domains | EventBridge | - |
| Streaming, ordered, replayable | Kinesis Data Streams | MSK when Kafka compatibility is required |
| Legacy protocols (AMQP, MQTT, JMS) | Amazon MQ | - |

Every consumer is idempotent and every queue has a dead-letter queue with an alarm; say both in
the ADR.
