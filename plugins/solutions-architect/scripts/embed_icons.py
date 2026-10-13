#!/usr/bin/env python3
"""Embed third-party icons into a draw.io view, in place.

Usage: embed_icons.py <file.drawio> --catalog <providers/icons/catalog.json>
Every <object sa_icon="<slug>"> gets style shape=image and image=data:image/svg+xml,<base64>
from providers/icons/svg/<slug>.svg, so the view opens and exports offline. Idempotent.
Line 1 follows the sensor contract. Exit 0 pass, 1 fail.
"""
import argparse
import base64
import difflib
import json
import pathlib
import sys
import xml.etree.ElementTree as ET

SID = "drawio-icons\tcorrectness"


def restyle(style, data_uri):
    parts = [p for p in style.split(";") if p and not p.startswith(("image=", "shape="))]
    return ";".join(["shape=image"] + parts + [f"image={data_uri}"]) + ";"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("file")
    ap.add_argument("--catalog", required=True)
    a = ap.parse_args()
    catalog_path = pathlib.Path(a.catalog)
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    try:
        tree = ET.parse(a.file)
    except (ET.ParseError, OSError) as exc:
        print(f"{SID}\tfail\t{a.file} is not a readable draw.io file: {exc}")
        sys.exit(1)
    if tree.getroot().find(".//mxGraphModel") is None and tree.getroot().tag != "mxGraphModel":
        print(f"{SID}\tfail\t{a.file} has no uncompressed <mxGraphModel>")
        print("  guidance: write the view as uncompressed draw.io XML (mxfile > diagram > mxGraphModel).")
        sys.exit(1)
    errs, done = [], 0
    for obj in tree.iter():
        slug = obj.get("sa_icon") if obj.tag in ("object", "UserObject") else None
        cell = obj.find("mxCell") if slug else None
        if cell is None:
            continue
        if slug not in catalog:
            near = ", ".join(difflib.get_close_matches(slug, catalog, n=3)) or "see catalog.json"
            errs.append(f"cell {obj.get('id')}: {slug} is not in the icon catalog (closest: {near})")
            continue
        svg = (catalog_path.parent / "svg" / f"{slug}.svg").read_bytes()
        uri = "data:image/svg+xml," + base64.b64encode(svg).decode("ascii")
        cell.set("style", restyle(cell.get("style", ""), uri))
        done += 1
    if errs:
        print(f"{SID}\tfail\t{len(errs)} unknown icon(s) in {a.file}")
        for e in errs:
            print(f"  {e}")
        print("  guidance: use a slug from providers/icons/catalog.json, or a generic shape with a label.")
        sys.exit(1)
    tree.write(a.file, encoding="unicode")
    print(f"{SID}\tpass\tembedded {done} icon(s) in {a.file}")
    sys.exit(0)


if __name__ == "__main__":
    main()
