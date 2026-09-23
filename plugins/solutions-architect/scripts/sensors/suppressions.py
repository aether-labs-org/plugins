#!/usr/bin/env python3
"""Print the check ids checkov may skip globally: only CKV_TF_1 with the D22 justification.

Every other suppression is inline in the resource (#checkov:skip=<ID>:<reason>) and mirrored in
the manifest for traceability; a global --skip-check would switch the rule off for every resource.
"""
import json
import sys

m = json.load(open(sys.argv[1], encoding="utf-8"))
ok = any(s.get("check") == "CKV_TF_1" and str(s.get("justification", "")).startswith("D22:")
         for s in m.get("suppressions", []))
print("CKV_TF_1" if ok else "")
