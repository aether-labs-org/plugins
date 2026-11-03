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


def recall_gate(root, qrels, index=None):
    """What the recall hook would do for each qrels query (spec 4.3): a positive counts when its
    query has enough terms and the hook injects any of its relevant notes; a negative is noisy
    when the hook injects anything."""
    from . import recall
    from .search import SearchIndex, tokenize

    index = index or SearchIndex(root)
    pos = {"n": 0, "injected": 0, "missed": []}
    neg = {"n": 0, "injected": 0, "noisy": []}
    for row in qrels:
        relevant = set(row["relevant"])
        if relevant and len(tokenize(row["query"])) < recall.MIN_TOKENS:
            continue                            # the hook never fires on such a prompt
        names = {r["name"] for r in recall.select(root, row["query"], index)}
        if relevant:
            pos["n"] += 1
            if names & relevant:
                pos["injected"] += 1
            else:
                pos["missed"].append(row["id"])
        else:
            neg["n"] += 1
            if names:
                neg["injected"] += 1
                neg["noisy"].append(row["id"])
    return {"positives": pos, "negatives": neg}


def render_table(result, ks=(5, 10)):
    cols = ["recall@%d" % k for k in ks] + ["mrr"]
    lines = ["%-10s %4s  %s" % ("type", "n", "  ".join("%9s" % c for c in cols))]
    rows = list(result["by_type"].items()) + [("overall", result["overall"])]
    for name, stats in rows:
        lines.append("%-10s %4d  %s" % (name, stats["n"], "  ".join("%9.3f" % stats[c] for c in cols)))
    neg = result["negatives"]
    if neg["n"]:
        lines.append("negatives  %4d  max top score %.4f" % (neg["n"], neg["max_top_score"]))
    gate = result.get("recall_gate")
    if gate:
        lines.append("recall gate  positives injected %d/%d"
                     % (gate["positives"]["injected"], gate["positives"]["n"]))
        lines.append("recall gate  negatives with injection %d/%d"
                     % (gate["negatives"]["injected"], gate["negatives"]["n"]))
    return "\n".join(lines)
