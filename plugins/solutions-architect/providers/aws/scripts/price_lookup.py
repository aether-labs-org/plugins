#!/usr/bin/env python3
"""Deterministic list-price lookup for a Terraform plan (plan decision D21).

Usage: price_lookup.py --plan plan.json --manifest manifest.json --map price-map.json
                       --cache DIR [--mode offline|live|record] [--region REGION] --out lines.json
Reads `terraform show -json` output, prices each resource from the curated map via the AWS
Price List API (`aws pricing get-products`, read-only) or from recorded responses, and writes
one JSON line item per priced dimension. It never picks a product on its own: 0 matches, or
several matches with different prices, make the line "not-estimated".
Line 1 follows the sensor contract. Exit 0 when it ran, 1 on bad input.
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys


def render(value, after):
    if isinstance(value, dict):
        raw = after.get(value["from"])
        key = str(raw).lower() if isinstance(raw, bool) else str(raw)
        if key not in value["map"]:
            raise KeyError(f"{value['from']}={raw} is not in the price map")
        return render(value["map"][key], after)

    def sub(m):
        v = after.get(m.group(1))
        if v is None or v == "":
            raise KeyError(f"attribute {m.group(1)} is unknown in the plan")
        return str(v)
    return re.sub(r"\{([a-z_]+)\}", sub, value)


def matches_when(when, after):
    for k, allowed in (when or {}).items():
        v = after.get(k)
        vals = v if isinstance(v, list) else [v]
        if not any(str(x) in allowed for x in vals):
            return False
    return True


def cache_path(cache, service, filters):
    key = json.dumps({"service": service, "filters": sorted(filters.items())}, sort_keys=True)
    return os.path.join(cache, hashlib.sha256(key.encode()).hexdigest()[:16] + ".json")


def fetch(service, filters, cache, mode):
    path = cache_path(cache, service, filters)
    if mode == "offline":
        if not os.path.isfile(path):
            return None
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)["price_list"]
    flt = [{"Type": "TERM_MATCH", "Field": k, "Value": v} for k, v in sorted(filters.items())]
    out = subprocess.run(["aws", "pricing", "get-products", "--region", "us-east-1",
                          "--service-code", service, "--filters", json.dumps(flt), "--output", "json"],
                         capture_output=True, text=True, check=True).stdout
    price_list = json.loads(out)["PriceList"]
    if mode == "record":
        os.makedirs(cache, exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            json.dump({"service_code": service, "filters": filters, "price_list": price_list}, fh, indent=1)
    return price_list


def slim_record(cache, service, filters, hits):
    """Keep only matched products, reduced to the fields price_line reads (test fixtures)."""
    path = cache_path(cache, service, filters)
    kept = {}
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as fh:
            for p in json.load(fh)["price_list"]:
                kept[p["product"]["sku"]] = p
    for p in hits:
        kept[p["product"]["sku"]] = {
            "product": {"sku": p["product"]["sku"],
                        "attributes": {"usagetype": p["product"]["attributes"]["usagetype"]}},
            "terms": {"OnDemand": p["terms"]["OnDemand"]}}
    os.makedirs(cache, exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump({"service_code": service, "filters": filters,
                   "price_list": [kept[k] for k in sorted(kept)]}, fh, indent=1, sort_keys=True)


def dimensions(product):
    dims = []
    for term in product.get("terms", {}).get("OnDemand", {}).values():
        for d in term["priceDimensions"].values():
            end = d.get("endRange", "Inf")
            dims.append((float(d.get("beginRange", 0)), float("inf") if end == "Inf" else float(end),
                         float(d["pricePerUnit"]["USD"]), d["unit"]))
    return sorted(dims)


def graduated(dims, qty):
    total = 0.0
    for begin, end, price, _ in dims:
        if qty > begin:
            total += (min(qty, end) - begin) * price
    return total


def component_for(address, components):
    for c in components:
        for t in c.get("terraform", []):
            if address == t or address.startswith(t + ".") or address.startswith(t + "["):
                return c["id"]
    return None


def quantity(spec, after, usage, hours):
    q = 1.0
    if "attr" in spec:
        q = float(after.get(spec["attr"]) or 0) * spec.get("scale", 1)
    if "usage" in spec:
        if spec["usage"] not in usage:
            raise KeyError(f"missing assumption {spec['usage']}")
        q *= float(usage[spec["usage"]])
    if "times_usage" in spec:
        if spec["times_usage"] not in usage:
            raise KeyError(f"missing assumption {spec['times_usage']}")
        q *= float(usage[spec["times_usage"]])
    if "times_attr" in spec:
        q *= float(after.get(spec["times_attr"]) or 1)
    if spec.get("hours") or spec.get("times_hours"):
        q *= hours
    return q


def price_line(res, entry, line, ctx):
    after = res["change"][ctx["side"]] or {}
    item = {"address": res["address"], "type": res["type"], "component_id": ctx["component"],
            "line": line["name"], "service_code": entry["service_code"]}
    try:
        filters = {"regionCode": ctx["region"]}
        if entry.get("location_filter"):
            filters = {"fromLocation": ctx["map"]["cloudfront_locations"][ctx["region"]]}
        for k, v in {**entry.get("filters", {}), **line.get("filters", {})}.items():
            filters[k] = render(v, after)
        if "usagetype_raw" in line:
            ut_re = re.compile(line["usagetype_raw"])
        else:
            ut_re = re.compile(ctx["map"]["region_prefix_regex"] + render(line["usagetype"], after) + "$")
        item["filters"] = filters
        item["usagetype_pattern"] = ut_re.pattern
        qty = quantity(line["quantity"], after, ctx["usage"], ctx["hours"])
        item["quantity"] = qty
    except KeyError as exc:
        return {**item, "status": "not-estimated", "reason": str(exc).strip("'\"")}
    mode = "live" if ctx["mode"] == "record-slim" else ctx["mode"]
    price_list = fetch(entry["service_code"], filters, ctx["cache"], mode)
    if price_list is None:
        return {**item, "status": "not-estimated", "reason": "no recorded price response (run with --mode record)"}
    products = [json.loads(p) if isinstance(p, str) else p for p in price_list]
    hits = [p for p in products if ut_re.search(p["product"]["attributes"].get("usagetype", ""))]
    if ctx["mode"] == "record-slim":
        slim_record(ctx["cache"], entry["service_code"], filters, hits)
    if not hits:
        return {**item, "status": "not-estimated", "reason": "0 products matched the usagetype"}
    signatures = {tuple(dimensions(p)) for p in hits}
    if len(signatures) > 1:
        uts = sorted(p["product"]["attributes"]["usagetype"] for p in hits)
        return {**item, "status": "not-estimated", "reason": f"{len(hits)} products with different prices: {uts}"}
    hit = sorted(hits, key=lambda p: p["product"]["sku"])[0]
    dims = dimensions(hit)
    spec = line["quantity"]
    item["usage_based"] = "usage" in spec or "times_usage" in spec
    item.update({"status": "estimated", "usagetype": hit["product"]["attributes"]["usagetype"],
                 "sku": hit["product"]["sku"], "unit": dims[0][3],
                 "tiers": [[b, (None if e == float("inf") else e), p] for b, e, p, _ in dims],
                 "monthly_usd": round(graduated(dims, qty), 4)})
    if len(hits) > 1:
        item["note"] = f"{len(hits)} products matched with identical prices; took sku {hit['product']['sku']}"
    return item


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan", required=True)
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--map", required=True)
    ap.add_argument("--cache", required=True)
    ap.add_argument("--mode", default="offline", choices=["offline", "live", "record", "record-slim"])
    ap.add_argument("--region")
    ap.add_argument("--side", default="after", choices=["after", "before"],
                    help="price the planned state (after) or the current state (before) for a delta")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    try:
        plan = json.load(open(a.plan, encoding="utf-8"))
        manifest = json.load(open(a.manifest, encoding="utf-8"))
        pmap = json.load(open(a.map, encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"price-lookup\tcorrectness\tfail\tcannot read input: {exc}")
        sys.exit(1)
    region = a.region or manifest["regions"][0]
    assumptions = manifest.get("assumptions", {})
    hours = float(assumptions.get("hours_per_month", 730))
    lines = []
    for res in plan.get("resource_changes", []):
        actions = res["change"]["actions"]
        if res.get("mode") != "managed":
            continue
        if a.side == "after" and actions == ["delete"]:
            continue
        if a.side == "before" and actions == ["create"]:
            continue
        if res["type"] in pmap["no_cost_types"]:
            continue
        entry = pmap["resources"].get(res["type"])
        comp = component_for(res["address"], manifest.get("components", []))
        after = res["change"][a.side] or {}
        if entry is None or not matches_when(entry.get("when"), after):
            lines.append({"address": res["address"], "type": res["type"], "component_id": comp,
                          "status": "not-mapped", "reason": "resource type or configuration is not in the price map"})
            continue
        ctx = {"side": a.side, "region": region, "map": pmap, "cache": a.cache, "mode": a.mode, "hours": hours,
               "component": comp, "usage": assumptions.get("usage", {}).get(comp or "", {})}
        for line in entry["lines"]:
            if matches_when(line.get("when"), after):
                lines.append(price_line(res, entry, line, ctx))
    with open(a.out, "w", encoding="utf-8") as fh:
        json.dump({"region": region, "side": a.side, "hours_per_month": hours, "lines": lines}, fh, indent=1)
    est = [l for l in lines if l["status"] == "estimated"]
    total = sum(l["monthly_usd"] for l in est)
    print(f"price-lookup\tcorrectness\tpass\t{len(est)}/{len(lines)} lines estimated in {region}; "
          f"list price {total:.2f} USD/month")
    for l in lines:
        if l["status"] != "estimated":
            print(f"  {l['status']}: {l['address']} {l.get('line', '')} - {l['reason']}")
    sys.exit(0)


if __name__ == "__main__":
    main()
