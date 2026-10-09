---
name: diagram
description: >
  Draws the four views of a solutions-architect workspace - topology, network (VPC, AZ,
  subnets), data flow with trust boundaries, DR - as draw.io files with AWS4, Kubernetes and
  third-party icons (Kafka, Datadog, Prometheus...), validates them against the manifest and
  exports PNG/SVG. Use for diagrams tied to architecture/manifest.json; else the drawio skill.
allowed-tools: Bash(python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate_drawio.py *), Bash(python3 ${CLAUDE_PLUGIN_ROOT}/scripts/embed_icons.py *), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/export_drawio.sh *)
---

# Diagram

Four views, each a native `.drawio` file written as **uncompressed XML**, each validated by a
script before anyone sees it. The diagram shows accepted decisions only: every component on it
(AWS service, Kubernetes workload or third-party product) carries the `component_id` of a
manifest component.

## Procedure

1. Read `manifest.components`, the accepted ADRs and `references/views.md` (what each view must
   show) and `references/aws/aws4-shapes.md` (the XML patterns to copy). When a component runs
   on Kubernetes, also read `references/kubernetes-shapes.md`; when it is a product without an
   AWS icon (Kafka, Datadog, Prometheus, Argo CD, Vault...), read `references/third-party-icons.md`.
2. Write `architecture/diagrams/<view>.drawio` for `topology`, `network`, `dataflow-security`
   and `dr`. Skip `dr` only when the requirements record that no DR is needed, and say so.
   - Every component is an `<object label="..." component_id="<manifest id>">` wrapping its
     `mxCell`.
   - Every container is an `<object ... sa_kind="account|region|vpc|az|subnet-public|subnet-private|trust-boundary|k8s-cluster|k8s-namespace">`;
     VPCs and subnets also carry `cidr="..."`; DR regions carry `role="primary|secondary"`.
   - Nest by `parent`: subnet inside AZ inside VPC inside region; namespace inside cluster.
     Positions can be approximate.
   - A third-party icon is an `<object ... sa_icon="<slug>">` with `shape=image` and no image
     data - the next step embeds it.
3. Embed the third-party icons (skip when the view has no `sa_icon`):

   ```bash
   python3 ${CLAUDE_PLUGIN_ROOT}/scripts/embed_icons.py architecture/diagrams/<view>.drawio \
     --catalog ${CLAUDE_PLUGIN_ROOT}/providers/icons/catalog.json
   ```

4. Validate each view:

   ```bash
   python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate_drawio.py architecture/diagrams/<view>.drawio \
     --view <view> --allowlist ${CLAUDE_PLUGIN_ROOT}/providers/aws/aws4-allowlist.txt \
     --allowlist ${CLAUDE_PLUGIN_ROOT}/providers/kubernetes/kubernetes-allowlist.txt \
     --icons ${CLAUDE_PLUGIN_ROOT}/providers/icons/catalog.json --manifest architecture/manifest.json
   ```

   Fix every problem it lists and run it again until line 1 reads `pass`. Never edit an
   allowlist or the icon catalog to make a shape pass - pick an existing shape. After editing a
   view with `sa_icon` cells, run step 3 again before validating.
5. Write the C4 context and container views as Mermaid in `architecture/diagrams/context.mmd`
   and `container.mmd` (`references/c4-mermaid.md`); they render in pull requests.
6. Export for people who do not use draw.io:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/export_drawio.sh architecture/diagrams/<view>.drawio svg
   ```

   `skip` means draw.io Desktop is not installed: say so and deliver the `.drawio` files. If the
   `drawio` skill from the jgraph plugin is available, you may use it for ELK layout of the XML;
   the validator still has the last word.
7. Add the view names to each component's `diagrams` list in the manifest.

## Exit gate

`validate_drawio.py` passes for every required view with `--manifest`.
