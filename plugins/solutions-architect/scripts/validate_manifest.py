#!/usr/bin/env python3
"""Validate an architecture workspace manifest (schema 1).

Usage: validate_manifest.py <manifest.json> [--strict-trace]
Line 1 follows the sensor contract: id<TAB>class<TAB>status<TAB>summary.
Exit 0 pass, 1 fail.
"""
import json
import os
import re
import sys

STAGES = ["requirements", "design", "diagram", "finops-compare", "iac",
          "finops-estimate", "docs", "review", "done"]
GATE_STATUS = {"pending", "pass", "fail", "skipped"}
REQ_ID = re.compile(r"^(REQ|NFR|CON)-\d{3}$")
ADR_ID = re.compile(r"^ADR-\d{4}$")
COMPONENT_ID = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
ADR_STATUS = {"proposed", "accepted", "superseded", "rejected"}
VIEWS = {"topology", "network", "dataflow-security", "dr"}
D22_PREFIX = "D22:"


def validate(m, base):
    errors, warnings = [], []
    if m.get("schema") != 1:
        errors.append("schema must be 1")
    if m.get("provider") != "aws":
        errors.append("provider must be 'aws' (the only provider in v0.1)")
    if not re.fullmatch(r"[a-z]{2}(-[A-Z]{2})?", str(m.get("language", ""))):
        errors.append("language must look like 'pt-BR' or 'en'")
    regions = m.get("regions")
    if not isinstance(regions, list) or not regions:
        errors.append("regions must be a non-empty list")
    if m.get("stage") not in STAGES:
        errors.append(f"stage must be one of {', '.join(STAGES)}")
    for g, v in (m.get("gates") or {}).items():
        if g not in STAGES:
            errors.append(f"gates.{g}: unknown stage")
        elif not isinstance(v, dict) or v.get("status") not in GATE_STATUS:
            errors.append(f"gates.{g}.status must be one of {sorted(GATE_STATUS)}")

    req_ids = set()
    for r in m.get("requirements", []):
        rid = r.get("id", "")
        if not REQ_ID.match(rid):
            errors.append(f"requirement id '{rid}' must match REQ-/NFR-/CON-nnn")
        if rid in req_ids:
            errors.append(f"duplicate requirement id {rid}")
        req_ids.add(rid)
        if rid.startswith("NFR-") and not str(r.get("measure", "")).strip():
            errors.append(f"{rid} has no measure; write one or 'TBD by <owner>'")

    adr_ids, covered = set(), set()
    for d in m.get("decisions", []):
        did = d.get("id", "")
        if not ADR_ID.match(did):
            errors.append(f"decision id '{did}' must match ADR-nnnn")
        if did in adr_ids:
            errors.append(f"duplicate decision id {did}")
        adr_ids.add(did)
        if d.get("status") not in ADR_STATUS:
            errors.append(f"{did}.status must be one of {sorted(ADR_STATUS)}")
        f = d.get("file", "")
        if not f or not os.path.isfile(os.path.join(base, f)):
            errors.append(f"{did}.file '{f}' does not exist")
        for rid in d.get("addresses", []):
            if rid not in req_ids:
                errors.append(f"{did} addresses unknown requirement {rid}")
            elif d.get("status") == "accepted":
                covered.add(rid)
    for d in m.get("decisions", []):
        sup = d.get("supersedes")
        if sup and sup not in adr_ids:
            errors.append(f"{d.get('id')} supersedes unknown decision {sup}")

    comp_ids = set()
    for c in m.get("components", []):
        cid = c.get("id", "")
        if not COMPONENT_ID.match(cid):
            errors.append(f"component id '{cid}' must be kebab-case")
        if cid in comp_ids:
            errors.append(f"duplicate component id {cid}")
        comp_ids.add(cid)
        if c.get("decision") not in adr_ids:
            errors.append(f"component {cid} references unknown decision {c.get('decision')}")
        for v in c.get("diagrams", []):
            if v not in VIEWS:
                errors.append(f"component {cid} lists unknown view {v}")

    for i, s in enumerate(m.get("suppressions", [])):
        just = str(s.get("justification", "")).strip()
        if len(just) < 20:
            errors.append(f"suppressions[{i}] ({s.get('check')}) needs a justification of 20+ characters")
        if s.get("check") == "CKV_TF_1" and not just.startswith(D22_PREFIX):
            errors.append(f"suppressions[{i}]: CKV_TF_1 may only be suppressed with the D22 justification")

    usage = (m.get("assumptions") or {}).get("usage", {})
    for cid in usage:
        if cid not in comp_ids:
            errors.append(f"assumptions.usage.{cid}: unknown component")

    uncovered = sorted(r for r in req_ids if r.startswith("NFR-") and r not in covered)
    if uncovered:
        warnings.append("NFRs without an accepted ADR: " + ", ".join(uncovered))
    return errors, warnings, uncovered


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    strict = "--strict-trace" in sys.argv
    if len(args) != 1:
        print("usage: validate_manifest.py <manifest.json> [--strict-trace]", file=sys.stderr)
        sys.exit(2)
    path = args[0]
    try:
        with open(path, encoding="utf-8") as fh:
            m = json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        print(f"manifest\tcorrectness\tfail\tcannot read {path}: {exc}")
        sys.exit(1)
    errors, warnings, uncovered = validate(m, os.path.dirname(os.path.abspath(path)))
    if strict and uncovered:
        errors.append("strict trace: " + warnings[0])
    if errors:
        print(f"manifest\tcorrectness\tfail\t{len(errors)} error(s) in {path}")
        for e in errors[:15]:
            print(f"  {e}")
        print("  guidance: fix the manifest entries above; every id an artifact cites must exist here.")
        sys.exit(1)
    print(f"manifest\tcorrectness\tpass\t0 errors; {len(m.get('requirements', []))} requirements, "
          f"{len(m.get('decisions', []))} decisions, {len(m.get('components', []))} components")
    for w in warnings:
        print(f"  warning: {w}")
    sys.exit(0)


if __name__ == "__main__":
    main()
