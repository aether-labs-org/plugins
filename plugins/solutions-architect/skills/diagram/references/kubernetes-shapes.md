# Kubernetes shapes - XML patterns

Use these when a component runs on Kubernetes (EKS or self-managed). The icons come from the
draw.io Kubernetes library; every `prIcon` used must be in
`providers/kubernetes/kubernetes-allowlist.txt` (validated as `mxgraph.kubernetes.<prIcon>`).

## Containers

A cluster is a container with `sa_kind="k8s-cluster"`; a namespace is a container with
`sa_kind="k8s-namespace"` and must sit inside a cluster (checked in every view). On EKS the
cluster is also the manifest component (`component_id` of the EKS cluster), placed inside the
region - or inside the private subnets' AZ in the network view.

```xml
<object id="eks" label="EKS cluster orders" sa_kind="k8s-cluster" component_id="orders-eks">
  <mxCell style="rounded=1;container=1;collapsible=0;fillColor=none;strokeColor=#326CE5;verticalAlign=top;align=left;spacingLeft=10;fontColor=#326CE5;" vertex="1" parent="region">
    <mxGeometry x="20" y="40" width="400" height="280" as="geometry"/>
  </mxCell>
</object>
<object id="ns-orders" label="namespace orders" sa_kind="k8s-namespace">
  <mxCell style="rounded=0;dashed=1;container=1;collapsible=0;fillColor=none;strokeColor=#326CE5;verticalAlign=top;align=left;spacingLeft=10;" vertex="1" parent="eks">
    <mxGeometry x="20" y="40" width="360" height="220" as="geometry"/>
  </mxCell>
</object>
```

## Icons

`shape=mxgraph.kubernetes.icon2;prIcon=<name>`; keep the fill and stroke below so every icon
looks the same:

```xml
<object id="api" label="orders-api" component_id="orders-api">
  <mxCell style="aspect=fixed;html=1;verticalLabelPosition=bottom;verticalAlign=top;fillColor=#2875E2;strokeColor=#ffffff;shape=mxgraph.kubernetes.icon2;prIcon=deploy" vertex="1" parent="ns-orders">
    <mxGeometry x="40" y="60" width="50" height="48" as="geometry"/>
  </mxCell>
</object>
```

| Object | `prIcon` |
|---|---|
| Deployment / StatefulSet / DaemonSet | `deploy` / `sts` / `ds` |
| Pod / ReplicaSet | `pod` / `rs` |
| Job / CronJob | `job` / `cronjob` |
| Service / Ingress / Endpoints | `svc` / `ing` / `ep` |
| HorizontalPodAutoscaler | `hpa` |
| ConfigMap / Secret | `cm` / `secret` |
| PersistentVolume / Claim / StorageClass | `pv` / `pvc` / `sc` |
| NetworkPolicy | `netpol` |
| ServiceAccount / Role / RoleBinding | `sa` / `role` / `rb` |
| CustomResourceDefinition | `crd` |
| Node / control plane | `node` / `control_plane` |
| Namespace (as an icon, not a container) | `ns` |

Draw workloads, not every object: one icon per Deployment or StatefulSet that is a manifest
component, plus the Service, Ingress and HPA that matter for an NFR. Operators and platform
add-ons (Argo CD, Istio, Strimzi...) use the third-party icons in `third-party-icons.md`.
