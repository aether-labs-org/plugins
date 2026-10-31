"""Deterministic retrieval metrics for `sb eval` (spec 4.5): Recall@k and MRR over graded qrels."""
import json

MRR_CUTOFF = 10


def load_qrels(path):
    """JSONL rows `{"id", "type", "query", "relevant": {"<Note name>": 1|2}}`; blank lines skipped."""
    rows = []
    with open(str(path), encoding="utf-8") as handle:
        for number, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            try:
                row = json.loads(line)
                rows.append({"id": str(row["id"]), "type": str(row["type"]),
                             "query": str(row["query"]), "relevant": dict(row.get("relevant") or {})})
            except (ValueError, KeyError, TypeError) as exc:
                raise ValueError("%s:%d: bad qrels row (%s)" % (path, number, exc))
    return rows


def _mean(values):
    return sum(values) / len(values) if values else 0.0


def _summary(rows, ks):
    out = {"n": len(rows), "mrr": _mean([r["mrr"] for r in rows])}
    for k in ks:
        out["recall@%d" % k] = _mean([r["recall"][k] for r in rows])
    return out


def evaluate(index, qrels, ks=(5, 10)):
    depth = max(max(ks), MRR_CUTOFF)
    positives, negatives = [], []
    for row in qrels:
        results = index.search(row["query"], limit=depth)
        names = [r["name"] for r in results]
        relevant = set(row["relevant"])
        if not relevant:
            negatives.append(results[0]["score"] if results else 0.0)
            continue
        rank = next((i for i, name in enumerate(names[:MRR_CUTOFF], start=1) if name in relevant), 0)
        positives.append({
            "type": row["type"], "id": row["id"],
            "recall": {k: len(relevant.intersection(names[:k])) / len(relevant) for k in ks},
            "mrr": 1.0 / rank if rank else 0.0})
    by_type = {}
    for t in sorted({p["type"] for p in positives}):
        by_type[t] = _summary([p for p in positives if p["type"] == t], ks)
    return {"overall": _summary(positives, ks), "by_type": by_type,
            "negatives": {"n": len(negatives), "max_top_score": max(negatives) if negatives else 0.0,
                          "scores": negatives}}


def render_table(result, ks=(5, 10)):
    cols = ["recall@%d" % k for k in ks] + ["mrr"]
    lines = ["%-10s %4s  %s" % ("type", "n", "  ".join("%9s" % c for c in cols))]
    rows = list(result["by_type"].items()) + [("overall", result["overall"])]
    for name, stats in rows:
        lines.append("%-10s %4d  %s" % (name, stats["n"], "  ".join("%9.3f" % stats[c] for c in cols)))
    neg = result["negatives"]
    if neg["n"]:
        lines.append("negatives  %4d  max top score %.4f" % (neg["n"], neg["max_top_score"]))
    return "\n".join(lines)
