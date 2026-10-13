# Kubernetes shapes

`kubernetes-allowlist.txt` lists the icons of the draw.io Kubernetes library
(`shape=mxgraph.kubernetes.icon2;prIcon=<name>`, and the older `mxgraph.kubernetes.icon`), one
per line as `mxgraph.kubernetes.<name>` - the form `validate_drawio.py` checks. It is generated
from the installed draw.io Desktop (31.7.0 here; on macOS use
`/Applications/draw.io.app/Contents/Resources/app.asar`):

```bash
grep -a -o 'mxgraph\.kubernetes\.icon2\?;[^"]\{0,80\}prIcon=[a-z_0-9]*' /snap/drawio/current/app/resources/app.asar \
  | sed 's/.*prIcon=/mxgraph.kubernetes./' | sort -u > kubernetes-allowlist.txt
```

Do not hand-edit it. XML patterns: `skills/diagram/references/kubernetes-shapes.md`.
