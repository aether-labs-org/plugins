---
type: llm
focus: { source: file, path: architecture/diagrams/topology.drawio }
weight: 3
---
The diagram has a container with sa_kind="k8s-cluster" holding containers with
sa_kind="k8s-namespace"; the order API uses a Kubernetes icon (shape=mxgraph.kubernetes.icon2
with a prIcon); Kafka and Datadog are objects with sa_icon="apachekafka" and sa_icon="datadog"
whose style holds an embedded image=data:image/svg+xml, value (no http image URL); Datadog sits
outside the AWS account container. PASS only if all hold.
