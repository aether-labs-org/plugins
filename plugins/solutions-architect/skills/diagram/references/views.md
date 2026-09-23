# The four views

Provider-neutral contract; the AWS shapes that realise it are in `aws/aws4-shapes.md`.

| View | Must show | Validator rules |
|---|---|---|
| `topology` | accounts, regions, every deployable component, the main connections | every manifest component that lists `topology` appears, by `component_id` |
| `network` | virtual network with CIDR, zones, public and private subnets, internet and NAT egress, private endpoints, inter-network links | containment subnet in zone in network in region; subnet CIDRs inside the network CIDR and not overlapping; at least one `vpc` container |
| `dataflow-security` | numbered flows with protocol and encryption, trust boundaries, where personal data lives | every edge label starts with its step number (`1 HTTPS`); at least one `trust-boundary` container |
| `dr` | primary and secondary regions, replication and its interval, failover direction, RTO/RPO labels | exactly one region `role=primary`, at least one `role=secondary` |

All views: labels on every vertex, only shapes from the allowlist, `component_id` values that
exist in the manifest.
