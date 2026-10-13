#!/usr/bin/env python3
"""Validate a solutions-architect draw.io view.

Usage: validate_drawio.py <file.drawio> --view <topology|network|dataflow-security|dr>
                          --allowlist <aws4-allowlist.txt> [--allowlist <kubernetes-allowlist.txt>]
                          [--icons <catalog.json>] [--manifest <manifest.json>]
Line 1 follows the sensor contract. Exit 0 pass, 1 fail, 2 usage error.
"""
import argparse
import base64
import ipaddress
import json
import re
import sys
import urllib.parse
import xml.etree.ElementTree as ET
import zlib

AWS4 = re.compile(r"(?:shape|resIcon|grIcon)=(mxgraph\.aws4\.[A-Za-z0-9_]+)")
K8S = re.compile(r"shape=mxgraph\.kubernetes\.icon2?(?:;|$)")
PR_ICON = re.compile(r"(?:^|;)prIcon=([A-Za-z0-9_]+)")
IMAGE = re.compile(r"(?:^|;)image=([^;]*)")
EDGE_LABEL = re.compile(r"^\s*\d+[.)]?\s+\S")
CONTAINMENT = {"subnet-public": "az", "subnet-private": "az", "az": "vpc", "vpc": "region"}


def load_cells(path):
    root = ET.parse(path).getroot()
    diagram = root if root.tag == "mxGraphModel" else root.find("diagram")
    if diagram is None:
        raise ValueError("no <diagram> element")
    model = diagram if diagram.tag == "mxGraphModel" else diagram.find("mxGraphModel")
    if model is None and (diagram.text or "").strip():
        raw = zlib.decompress(base64.b64decode(diagram.text.strip()), -15)
        model = ET.fromstring(urllib.parse.unquote(raw.decode("utf-8")))
    if model is None:
        raise ValueError("no <mxGraphModel> element")
    cells = {}
    for el in model.find("root"):
        if el.tag in ("object", "UserObject"):
            inner = el.find("mxCell")
            attrs = dict(el.attrib)
            label = attrs.get("label", "")
        else:
            inner, attrs, label = el, {}, el.get("value", "")
        if inner is None:
            continue
        cid = el.get("id")
        cells[cid] = {"id": cid, "attrs": attrs, "label": re.sub(r"<[^>]+>", " ", label or "").strip(),
                      "style": inner.get("style", "") or "", "parent": inner.get("parent"),
                      "vertex": inner.get("vertex") == "1", "edge": inner.get("edge") == "1"}
    return cells


def ancestors(cells, cid):
    seen, cur = [], cells.get(cid, {}).get("parent")
    while cur and cur in cells and cur not in seen:
        seen.append(cur)
        cur = cells[cur]["parent"]
    return seen


def validate(cells, view, allow, manifest, icons=None):
    errs = []
    for c in cells.values():
        for name in AWS4.findall(c["style"]):
            if name not in allow:
                errs.append(f"cell {c['id']}: shape {name} is not in the AWS4 allowlist")
        if K8S.search(c["style"]):
            for icon in PR_ICON.findall(c["style"]):
                if f"mxgraph.kubernetes.{icon}" not in allow:
                    errs.append(f"cell {c['id']}: shape mxgraph.kubernetes.{icon} is not in the Kubernetes allowlist")
        image = (IMAGE.findall(c["style"]) or [""])[0]
        if image.startswith(("http://", "https://")):
            errs.append(f"cell {c['id']}: external image {image} - use sa_icon so the view opens offline")
        slug = c["attrs"].get("sa_icon")
        if slug:
            if icons is not None and slug not in icons:
                errs.append(f"cell {c['id']}: sa_icon {slug} is not in the icon catalog")
            elif not image.startswith("data:image/svg+xml,"):
                errs.append(f"cell {c['id']}: sa_icon {slug} is not embedded - run embed_icons.py")
        if c["vertex"] and not c["label"]:
            errs.append(f"cell {c['id']}: vertex has no label")
    kinds = {cid: c["attrs"].get("sa_kind") for cid, c in cells.items()}
    for cid, kind in kinds.items():
        if kind == "k8s-namespace" and "k8s-cluster" not in [kinds.get(a) for a in ancestors(cells, cid)]:
            errs.append(f"cell {cid} (k8s-namespace) is not inside a k8s-cluster")
    comp_ids = {c["attrs"]["component_id"] for c in cells.values() if c["attrs"].get("component_id")}
    if manifest is not None:
        known = {c["id"] for c in manifest.get("components", [])}
        for cid in sorted(comp_ids - known):
            errs.append(f"component_id {cid} is not in the manifest")
        if view == "topology":
            for cid in sorted(k for k in known if view in next(
                    (c.get("diagrams", []) for c in manifest["components"] if c["id"] == k), [])):
                if cid not in comp_ids:
                    errs.append(f"manifest component {cid} is missing from the topology view")
    if view == "network":
        for cid, kind in kinds.items():
            need = CONTAINMENT.get(kind)
            if need and need not in [kinds.get(a) for a in ancestors(cells, cid)]:
                errs.append(f"cell {cid} ({kind}) is not inside a {need}")
        nets = {}
        for cid, c in cells.items():
            if c["attrs"].get("cidr"):
                try:
                    nets[cid] = ipaddress.ip_network(c["attrs"]["cidr"], strict=True)
                except ValueError:
                    errs.append(f"cell {cid}: invalid cidr {c['attrs']['cidr']}")
        for cid, net in nets.items():
            if kinds.get(cid, "").startswith("subnet"):
                vpcs = [a for a in ancestors(cells, cid) if kinds.get(a) == "vpc" and a in nets]
                if vpcs and not net.subnet_of(nets[vpcs[0]]):
                    errs.append(f"subnet {cid} {net} is outside its VPC {nets[vpcs[0]]}")
        subnets = sorted((cid, n) for cid, n in nets.items() if kinds.get(cid, "").startswith("subnet"))
        for i, (a, na) in enumerate(subnets):
            for b, nb in subnets[i + 1:]:
                if na.overlaps(nb):
                    errs.append(f"subnets {a} {na} and {b} {nb} overlap")
        if not any(k == "vpc" for k in kinds.values()):
            errs.append("network view has no container with sa_kind=vpc")
    if view == "dataflow-security":
        edges = [c for c in cells.values() if c["edge"]]
        if not edges:
            errs.append("dataflow view has no flows")
        for e in edges:
            if not EDGE_LABEL.match(e["label"]):
                errs.append(f"flow {e['id']}: label must start with its step number, e.g. '1 HTTPS'")
        if "trust-boundary" not in kinds.values():
            errs.append("dataflow view has no container with sa_kind=trust-boundary")
    if view == "dr":
        roles = [c["attrs"].get("role") for c in cells.values() if kinds.get(c["id"]) == "region"]
        if roles.count("primary") != 1 or roles.count("secondary") < 1:
            errs.append("dr view needs one region with role=primary and at least one with role=secondary")
    return errs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("file")
    ap.add_argument("--view", required=True, choices=["topology", "network", "dataflow-security", "dr"])
    ap.add_argument("--allowlist", required=True, action="append")
    ap.add_argument("--icons")
    ap.add_argument("--manifest")
    a = ap.parse_args()
    sid = f"diagram-{a.view}"
    try:
        cells = load_cells(a.file)
    except (ET.ParseError, ValueError, OSError, zlib.error) as exc:
        print(f"{sid}\tcorrectness\tfail\t{a.file} is not a readable draw.io file: {exc}")
        print("  guidance: regenerate the view as uncompressed draw.io XML (mxfile > diagram > mxGraphModel).")
        sys.exit(1)
    allow = set()
    for path in a.allowlist:
        with open(path, encoding="utf-8") as fh:
            allow |= {ln.strip() for ln in fh if ln.strip()}
    icons = None
    if a.icons:
        with open(a.icons, encoding="utf-8") as fh:
            icons = json.load(fh)
    manifest = None
    if a.manifest:
        with open(a.manifest, encoding="utf-8") as fh:
            manifest = json.load(fh)
    errs = validate(cells, a.view, allow, manifest, icons)
    if errs:
        print(f"{sid}\tcorrectness\tfail\t{len(errs)} problem(s) in {a.file}")
        for e in errs[:15]:
            print(f"  {e}")
        print("  guidance: fix the cells listed above in the XML; containers carry sa_kind, components carry")
        print("  component_id, and both live on an <object> wrapper around the mxCell.")
        sys.exit(1)
    n = sum(1 for c in cells.values() if c["vertex"])
    print(f"{sid}\tcorrectness\tpass\t0 problems in {n} vertices ({a.file})")
    sys.exit(0)


if __name__ == "__main__":
    main()
