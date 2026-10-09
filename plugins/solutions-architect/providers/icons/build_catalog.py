#!/usr/bin/env python3
"""Maintenance: rebuild providers/icons/{catalog.json,svg/} from a pinned Simple Icons release.

Usage: build_catalog.py [--version 16.30.0]
Needs network access (cdn.jsdelivr.net). Never runs during a design session - the plugin
ships the generated files. Add a technology by adding its Simple Icons slug to ICONS.
"""
import argparse
import json
import pathlib
import urllib.request

ICONS = {
    "observability": ["datadog", "prometheus", "grafana", "opentelemetry", "elasticsearch",
                      "opensearch", "jaeger"],
    "streaming-data": ["apachekafka", "rabbitmq", "redis", "postgresql", "mongodb"],
    "platform-cicd": ["kubernetes", "helm", "argo", "istio", "envoyproxy", "terraform", "vault",
                      "githubactions", "keycloak", "nginx", "cloudflare", "kong"],
}
CDN = "https://cdn.jsdelivr.net/npm/simple-icons@{v}/{path}"
DARK = "232F3E"  # used instead of brand colours too light to read on a white canvas


def fetch(version, path):
    with urllib.request.urlopen(CDN.format(v=version, path=path), timeout=30) as resp:
        return resp.read().decode("utf-8")


def luminance(hex_colour):
    r, g, b = (int(hex_colour[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", default="16.30.0")
    a = ap.parse_args()
    here = pathlib.Path(__file__).resolve().parent
    data = json.loads(fetch(a.version, "data/simple-icons.json"))
    data = data if isinstance(data, list) else data["icons"]
    by_slug = {i["slug"]: i for i in data if i.get("slug")}
    (here / "svg").mkdir(exist_ok=True)
    catalog = {}
    for category, slugs in ICONS.items():
        for slug in slugs:
            meta = by_slug[slug]
            colour = meta["hex"] if luminance(meta["hex"]) < 0.75 else DARK
            svg = fetch(a.version, f"icons/{slug}.svg").replace("<svg ", f'<svg fill="#{colour}" ', 1)
            (here / "svg" / f"{slug}.svg").write_text(svg, encoding="utf-8")
            lic = meta.get("license") or {}
            catalog[slug] = {"title": meta["title"], "category": category, "hex": colour,
                             "source": f"simple-icons@{a.version}",
                             "license": lic.get("type", "unspecified (Simple Icons is CC0-1.0)"),
                             "guidelines": meta.get("guidelines", "")}
    (here / "catalog.json").write_text(json.dumps(catalog, indent=2, sort_keys=True) + "\n",
                                       encoding="utf-8")
    print(f"{len(catalog)} icons from simple-icons@{a.version}")


if __name__ == "__main__":
    main()
