# The four views

Provider-neutral contract; the AWS shapes that realise it are in `aws/aws4-shapes.md`.

| View | Must show | Validator rules |
|---|---|---|
| `topology` | accounts, regions, every deployable component, the main connections | every manifest component that lists `topology` appears, by `component_id` |
| `network` | virtual network with CIDR, zones, public and private subnets, internet and NAT egress, private endpoints, inter-network links | containment subnet in zone in network in region; subnet CIDRs inside the network CIDR and not overlapping; at least one `vpc` container |
| `dataflow-security` | numbered flows with protocol and encryption, trust boundaries, where personal data lives | every edge label starts with its step number (`1 HTTPS`); at least one `trust-boundary` container |
| `dr` | primary and secondary regions, replication and its interval, failover direction, RTO/RPO labels | exactly one region `role=primary`, at least one `role=secondary` |

All views: labels on every vertex, only shapes from the allowlists, `component_id` values that
exist in the manifest, every `sa_icon` embedded and in the icon catalog, no image URLs, every
`k8s-namespace` inside a `k8s-cluster`.

When the design has Kubernetes or third-party products (`kubernetes-shapes.md`,
`third-party-icons.md`):

- `topology` shows cluster → namespace → the workloads that are manifest components, and the
  third-party products (Kafka, Datadog, Argo CD...) where they run - a SaaS outside the account.
- `network` places the cluster's nodes in the private subnets; a SaaS reached over the internet
  shows its egress path (NAT or PrivateLink).
- `dataflow-security` numbers flows to and from Kafka topics ("3 Kafka TLS - order-created")
  and every flow to a SaaS, which crosses a `trust-boundary` and says what data leaves.
- `dr` says how each stateful third-party product is replicated (MirrorMaker, snapshots) or
  that it is rebuilt.
