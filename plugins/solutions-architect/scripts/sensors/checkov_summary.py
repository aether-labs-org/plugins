#!/usr/bin/env python3
"""Reduce checkov JSON (stdin) to '<failed>\t<passed>' plus up to 8 failure lines."""
import json
import sys

raw = sys.stdin.read().strip() or "[]"
data = json.loads(raw)
data = data if isinstance(data, list) else [data]
failed = [c for r in data for c in r.get("results", {}).get("failed_checks", [])]
passed = sum(r.get("summary", {}).get("passed", 0) for r in data)
print(f"{len(failed)}\t{passed}")
for c in failed[:8]:
    start = (c.get("file_line_range") or [0, 0])[0]
    path = c.get("file_path", "").lstrip("/")
    print(f"{c['check_id']} {c['resource']} ({path}:{start}) {c['check_name'][:70]}")
