#!/usr/bin/env python3
"""Render finops/estimate.md from price_lookup output (list price, plan decision D6).

Usage: estimate.py --manifest manifest.json --after lines.json [--before lines-before.json] --out estimate.md
Usage-dependent lines get a low/high range from assumptions.range (default 0.7 / 1.5);
fixed lines (hours, sizes) do not move. Exit 0 when written, 1 on bad input.
"""
import argparse
import json
import sys

TEXT = {
    "pt-BR": {"title": "Estimativa de custo (preço de lista)", "region": "Região", "total": "Total mensal",
              "annual": "Total anual", "range": "Faixa mensal (baixa / esperada / alta)",
              "unit": "Custo por unidade de negócio", "delta": "Delta em relação ao estado atual",
              "lines": "Linhas estimadas", "missing": "Linhas não estimadas (sem valor inventado)",
              "assump": "Premissas", "cols": "| Recurso | Linha | usagetype | Quantidade | Unidade | USD/mês |",
              "note": "Preço de lista público da AWS Price List API, sem descontos nem compromissos (decisão D6)."},
    "en": {"title": "Cost estimate (list price)", "region": "Region", "total": "Monthly total",
           "annual": "Annual total", "range": "Monthly range (low / expected / high)",
           "unit": "Cost per business unit", "delta": "Delta versus current state",
           "lines": "Estimated lines", "missing": "Lines not estimated (no invented value)",
           "assump": "Assumptions", "cols": "| Resource | Line | usagetype | Quantity | Unit | USD/month |",
           "note": "AWS Price List API public list price, no discounts or commitments (decision D6)."},
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--after", required=True)
    ap.add_argument("--before")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    try:
        m = json.load(open(a.manifest, encoding="utf-8"))
        after = json.load(open(a.after, encoding="utf-8"))
        before = json.load(open(a.before, encoding="utf-8")) if a.before else None
    except (OSError, json.JSONDecodeError) as exc:
        print(f"estimate\tcorrectness\tfail\tcannot read input: {exc}")
        sys.exit(1)
    t = TEXT.get(m.get("language", "en"), TEXT["en"])
    asm = m.get("assumptions", {})
    rng = asm.get("range", {"low": 0.7, "high": 1.5})
    est = [l for l in after["lines"] if l["status"] == "estimated"]
    missing = [l for l in after["lines"] if l["status"] != "estimated"]
    total = sum(l["monthly_usd"] for l in est)
    usage_total = sum(l["monthly_usd"] for l in est if l.get("usage_based"))
    fixed_total = total - usage_total
    low, high = fixed_total + usage_total * rng["low"], fixed_total + usage_total * rng["high"]
    out = [f"# {t['title']}", "", f"> {t['note']}", "",
           f"- {t['region']}: `{after['region']}`",
           f"- {t['total']}: **USD {total:,.2f}**",
           f"- {t['annual']}: USD {total * 12:,.2f}",
           f"- {t['range']}: USD {low:,.2f} / {total:,.2f} / {high:,.2f}"]
    if before is not None:
        prev = sum(l["monthly_usd"] for l in before["lines"] if l["status"] == "estimated")
        out.append(f"- {t['delta']}: USD {total - prev:+,.2f} ({prev:,.2f} -> {total:,.2f})")
    for u in asm.get("business_units", []):
        if u.get("per_month"):
            out.append(f"- {t['unit']} ({u['name']}): USD {total / float(u['per_month']):,.6f}")
    out += ["", f"## {t['lines']}", "", t["cols"], "|---|---|---|---:|---|---:|"]
    for l in sorted(est, key=lambda x: -x["monthly_usd"]):
        out.append(f"| `{l['address']}` | {l['line']} | `{l['usagetype']}` | {l['quantity']:,.2f} | "
                   f"{l['unit']} | {l['monthly_usd']:,.2f} |")
    if missing:
        out += ["", f"## {t['missing']}", ""]
        out += [f"- `{l['address']}` {l.get('line', '')}: {l['reason']}" for l in missing]
    out += ["", f"## {t['assump']}", "", "```json", json.dumps(asm, indent=2, ensure_ascii=False), "```", ""]
    with open(a.out, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out))
    print(f"estimate\tcorrectness\tpass\tUSD {total:,.2f}/month list price; {len(est)} lines, "
          f"{len(missing)} not estimated -> {a.out}")
    sys.exit(0)


if __name__ == "__main__":
    main()
