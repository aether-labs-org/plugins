#!/usr/bin/env python3
"""tags - heuristic-free correctness sensor: every taggable planned resource carries the required tags.

Usage: tags.py <plan.json> <manifest.json>
Required keys come from manifest.tagging.required (default Project, Environment, Owner, CostCenter).
Line 1 follows the sensor contract. Exit 0 pass / 1 fail.
"""
import json
import sys

DEFAULT = ["Project", "Environment", "Owner", "CostCenter"]


def main():
    plan = json.load(open(sys.argv[1], encoding="utf-8"))
    manifest = json.load(open(sys.argv[2], encoding="utf-8"))
    required = manifest.get("tagging", {}).get("required", DEFAULT)
    missing, checked = [], 0
    for r in plan.get("resource_changes", []):
        after = r["change"].get("after") or {}
        if r.get("mode") != "managed" or r["change"]["actions"] == ["delete"]:
            continue
        if "tags_all" not in after and "tags" not in after:
            continue
        checked += 1
        tags = after.get("tags_all") or after.get("tags") or {}
        gaps = [k for k in required if k not in tags]
        if gaps:
            missing.append(f"{r['address']}: missing {', '.join(gaps)}")
    if missing:
        print(f"tags\tcorrectness\tfail\t{len(missing)} of {checked} taggable resources lack required tags")
        for line in missing[:8]:
            print(f"  {line}")
        print("  guidance: set the required keys once in the provider default_tags block; tag a")
        print("  resource individually only when its value differs (for example Owner).")
        sys.exit(1)
    print(f"tags\tcorrectness\tpass\t{checked} taggable resources carry {', '.join(required)}")
    sys.exit(0)


if __name__ == "__main__":
    main()
