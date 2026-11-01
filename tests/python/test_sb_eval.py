import io
import json
import shutil
import tempfile
import unittest

from sb_helpers import ROOT, make_vault, note
from sb import cli
from sb.evalrun import evaluate, load_qrels
from sb.search import SearchIndex

FIXTURE = ROOT / "tests" / "fixtures" / "sb-eval"


class MetricsTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def test_metrics_on_a_toy_index(self):
        root = make_vault(self.tmp.name, {
            "Resources/Alpha One.md": note("Alpha One", body="alpha alpha alpha"),
            "Resources/Alpha Two.md": note("Alpha Two", body="alpha"),
            "Resources/Beta.md": note("Beta", body="beta only")})
        qrels = [
            {"id": "a", "type": "lexical", "query": "alpha", "relevant": {"Alpha One": 2, "Alpha Two": 1}},
            {"id": "b", "type": "lexical", "query": "beta", "relevant": {"Beta": 2, "Missing Note": 1}},
            {"id": "c", "type": "implicit", "query": "alpha", "relevant": {"Alpha Two": 2}},
            {"id": "n", "type": "negative", "query": "nothing matches here", "relevant": {}}]
        names = [r["name"] for r in SearchIndex(root).search("alpha")]
        self.assertEqual(sorted(names), ["Alpha One", "Alpha Two"])
        rank_two = names.index("Alpha Two") + 1
        result = evaluate(SearchIndex(root), qrels)
        overall = result["overall"]
        self.assertEqual(overall["n"], 3)
        self.assertAlmostEqual(overall["recall@5"], (1.0 + 0.5 + 1.0) / 3)
        self.assertAlmostEqual(overall["recall@10"], (1.0 + 0.5 + 1.0) / 3)
        self.assertAlmostEqual(overall["mrr"], (1.0 + 1.0 + 1.0 / rank_two) / 3)
        self.assertEqual(result["by_type"]["lexical"]["n"], 2)
        self.assertEqual(result["negatives"]["n"], 1)
        self.assertEqual(result["negatives"]["max_top_score"], 0.0)

    def test_recall_at_5_is_cut_at_five(self):
        notes = {"Resources/N%d.md" % i: note("N%d" % i, body="common") for i in range(8)}
        root = make_vault(self.tmp.name, notes)
        qrels = [{"id": "x", "type": "t", "query": "common", "relevant": {"N%d" % i: 1 for i in range(8)}}]
        overall = evaluate(SearchIndex(root), qrels)["overall"]
        self.assertAlmostEqual(overall["recall@5"], 5 / 8)
        self.assertAlmostEqual(overall["recall@10"], 1.0)

    def test_load_qrels_skips_blank_lines_and_rejects_garbage(self):
        path = self.tmp.name + "/q.jsonl"
        with open(path, "w", encoding="utf-8") as f:
            f.write('{"id": "1", "type": "t", "query": "q", "relevant": {"A": 2}}\n\n')
        self.assertEqual(load_qrels(path)[0]["relevant"], {"A": 2})
        with open(path, "w", encoding="utf-8") as f:
            f.write("not json\n")
        with self.assertRaises(ValueError):
            load_qrels(path)


class FixtureTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = self.tmp.name + "/vault"
        shutil.copytree(str(FIXTURE / "vault"), self.root)   # the index writes .sb/

    def test_fixture_shape(self):
        qrels = load_qrels(FIXTURE / "qrels.jsonl")
        counts = {}
        for row in qrels:
            counts[row["type"]] = counts.get(row["type"], 0) + 1
        self.assertEqual(counts, {"lexical": 12, "accent": 8, "alias": 8, "implicit": 6, "negative": 6})
        names = {p.stem for p in (FIXTURE / "vault" / "wiki").rglob("*.md")}
        for row in qrels:
            self.assertLessEqual(set(row["relevant"]), names, row["id"])

    def test_fixture_meets_the_gate(self):
        result = evaluate(SearchIndex(self.root), load_qrels(FIXTURE / "qrels.jsonl"))
        self.assertGreaterEqual(result["overall"]["recall@10"], 0.85)
        self.assertGreaterEqual(result["overall"]["mrr"], 0.6)

    def test_cli_prints_a_table_and_json(self):
        out, err = io.StringIO(), io.StringIO()
        code = cli.main(["eval", "--qrels", str(FIXTURE / "qrels.jsonl"), "--vault", self.root], out, err)
        self.assertEqual(code, 0)
        self.assertIn("overall", out.getvalue())
        out = io.StringIO()
        cli.main(["eval", "--qrels", str(FIXTURE / "qrels.jsonl"), "--vault", self.root, "--json"], out, err)
        self.assertIn("recall@10", json.loads(out.getvalue())["overall"])
        self.assertEqual(cli.main(["eval", "--qrels", "/nonexistent", "--vault", self.root],
                                  io.StringIO(), io.StringIO()), 2)


if __name__ == "__main__":
    unittest.main()
