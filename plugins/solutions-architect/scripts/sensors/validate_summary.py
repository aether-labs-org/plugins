#!/usr/bin/env python3
"""Reduce `terraform validate -json` (stdin) to '<errors>\t<warnings>' plus up to 8 error lines."""
import json
import sys

d = json.load(sys.stdin)
errs = [x for x in d.get("diagnostics", []) if x.get("severity") == "error"]
print(f"{len(errs)}\t{d.get('warning_count', 0)}")
for x in errs[:8]:
    r = x.get("range") or {}
    line = (r.get("start") or {}).get("line", "?")
    print(f"{r.get('filename', '?')}:{line} {x.get('summary', '')}")
