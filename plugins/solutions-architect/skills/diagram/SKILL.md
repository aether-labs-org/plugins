---
name: diagram
description: >
  Draws the four AWS views of a solutions-architect workspace - topology, network (VPC, AZ,
  subnets), data flow with trust boundaries, DR - as draw.io files with AWS4 icons, validates
  them against the manifest and exports PNG/SVG. Use for architecture diagrams tied to
  architecture/manifest.json; for generic diagrams use the drawio skill instead.
allowed-tools: Bash(python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate_drawio.py *), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/export_drawio.sh *)
---

# Diagram

Four views, each a native `.drawio` file written as **uncompressed XML**, each validated by a
script before anyone sees it. The diagram shows accepted decisions only: every AWS component on
it carries the `component_id` of a manifest component.

## Procedure

1. Read `manifest.components`, the accepted ADRs and `references/views.md` (what each view must
   show) and `references/aws/aws4-shapes.md` (the XML patterns to copy).
2. Write `architecture/diagrams/<view>.drawio` for `topology`, `network`, `dataflow-security`
   and `dr`. Skip `dr` only when the requirements record that no DR is needed, and say so.
   - Every AWS component is an `<object label="..." component_id="<manifest id>">` wrapping its
     `mxCell`.
   - Every container is an `<object ... sa_kind="account|region|vpc|az|subnet-public|subnet-private|trust-boundary">`;
     VPCs and subnets also carry `cidr="..."`; DR regions carry `role="primary|secondary"`.
   - Nest by `parent`: subnet inside AZ inside VPC inside region. Positions can be approximate.
3. Validate each view:

   ```bash
   python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate_drawio.py architecture/diagrams/<view>.drawio \
     --view <view> --allowlist ${CLAUDE_PLUGIN_ROOT}/providers/aws/aws4-allowlist.txt \
     --manifest architecture/manifest.json
   ```

   Fix every problem it lists and run it again until line 1 reads `pass`. Never edit the
   allowlist to make a shape pass - pick an existing shape.
4. Write the C4 context and container views as Mermaid in `architecture/diagrams/context.mmd`
   and `container.mmd` (`references/c4-mermaid.md`); they render in pull requests.
5. Export for people who do not use draw.io:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/export_drawio.sh architecture/diagrams/<view>.drawio svg
   ```

   `skip` means draw.io Desktop is not installed: say so and deliver the `.drawio` files. If the
   `drawio` skill from the jgraph plugin is available, you may use it for ELK layout of the XML;
   the validator still has the last word.
6. Add the view names to each component's `diagrams` list in the manifest.

## Exit gate

`validate_drawio.py` passes for every required view with `--manifest`.
