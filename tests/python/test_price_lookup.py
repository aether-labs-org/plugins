import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest

ROOT = os.environ["SA_PLUGIN_ROOT"]
SCRIPT = os.path.join(ROOT, "providers/aws/scripts/price_lookup.py")
spec = importlib.util.spec_from_file_location("price_lookup", SCRIPT)
pl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pl)


def product(sku, usagetype, tiers):
    dims = {f"{sku}.{i}": {"beginRange": str(b), "endRange": "Inf" if e is None else str(e),
                           "unit": "GB-Mo", "pricePerUnit": {"USD": str(p)}, "description": "t"}
            for i, (b, e, p) in enumerate(tiers)}
    return {"product": {"sku": sku, "attributes": {"usagetype": usagetype}},
            "terms": {"OnDemand": {f"{sku}.T": {"priceDimensions": dims}}}}


MAP = {"schema": 1, "region_prefix_regex": "^(?:[A-Z]{2,4}[0-9]-)?", "cloudfront_locations": {},
       "no_cost_types": ["aws_vpc"],
       "resources": {
           "aws_s3_bucket": {"service_code": "AmazonS3", "filters": {"storageClass": "General Purpose"},
                             "lines": [{"name": "storage", "usagetype": "TimedStorage-ByteHrs",
                                        "quantity": {"usage": "storage_gb"}}]},
           "aws_dynamodb_table": {"service_code": "AmazonDynamoDB",
                                  "lines": [{"name": "reads", "usagetype": "ReadRequestUnits",
                                             "quantity": {"usage": "reads"}}]},
           "aws_eks_cluster": {"service_code": "AmazonEKS",
                               "lines": [{"name": "hours", "usagetype": "AmazonEKS-Hours:perCluster",
                                          "quantity": {"hours": True}}]},
           "aws_lb": {"service_code": "AWSELB",
                      "lines": [{"name": "hours", "usagetype": "LoadBalancerUsage", "quantity": {"hours": True}}]}}}


class PriceLookupTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.cache = os.path.join(self.dir, "cache")
        os.makedirs(self.cache)
        with open(os.path.join(self.dir, "map.json"), "w") as fh:
            json.dump(MAP, fh)

    def seed(self, service, filters, products):
        with open(pl.cache_path(self.cache, service, filters), "w") as fh:
            json.dump({"service_code": service, "filters": filters, "price_list": products}, fh)

    def run_lookup(self, resources, usage, side="after"):
        plan = {"resource_changes": [
            {"address": a, "mode": "managed", "type": t, "change": {"actions": act, "before": {}, "after": {}}}
            for a, t, act in resources]}
        comps = [{"id": a.split(".")[1], "decision": "ADR-0001", "terraform": [a]} for a, _, _ in resources]
        manifest = {"regions": ["sa-east-1"], "components": comps,
                    "assumptions": {"hours_per_month": 730, "usage": usage}}
        for name, obj in (("plan.json", plan), ("manifest.json", manifest)):
            with open(os.path.join(self.dir, name), "w") as fh:
                json.dump(obj, fh)
        out = os.path.join(self.dir, "lines.json")
        proc = subprocess.run([sys.executable, SCRIPT, "--plan", os.path.join(self.dir, "plan.json"),
                               "--manifest", os.path.join(self.dir, "manifest.json"),
                               "--map", os.path.join(self.dir, "map.json"), "--cache", self.cache,
                               "--mode", "offline", "--side", side, "--out", out],
                              capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertTrue(proc.stdout.startswith("price-lookup\tcorrectness\tpass\t"), proc.stdout)
        with open(out) as fh:
            return {(l["address"], l.get("line")): l for l in json.load(fh)["lines"]}

    def test_graduated_tiers(self):
        self.seed("AmazonS3", {"regionCode": "sa-east-1", "storageClass": "General Purpose"},
                  [product("S1", "SAE1-TimedStorage-ByteHrs", [(0, 51200, 0.0405), (51200, None, 0.039)])])
        lines = self.run_lookup([("aws_s3_bucket.assets", "aws_s3_bucket", ["create"])],
                                {"assets": {"storage_gb": 60000}})
        line = lines[("aws_s3_bucket.assets", "storage")]
        self.assertEqual(line["status"], "estimated")
        self.assertAlmostEqual(line["monthly_usd"], 51200 * 0.0405 + 8800 * 0.039, places=2)
        self.assertTrue(line["usage_based"])

    def test_region_prefix_excludes_infrequent_access(self):
        self.seed("AmazonDynamoDB", {"regionCode": "sa-east-1"},
                  [product("D1", "SAE1-ReadRequestUnits", [(0, None, 0.0000001875)]),
                   product("D2", "SAE1-IA-ReadRequestUnits", [(0, None, 0.00000047)])])
        lines = self.run_lookup([("aws_dynamodb_table.t", "aws_dynamodb_table", ["create"])],
                                {"t": {"reads": 1000000}})
        line = lines[("aws_dynamodb_table.t", "reads")]
        self.assertEqual(line["usagetype"], "SAE1-ReadRequestUnits")
        self.assertAlmostEqual(line["monthly_usd"], 0.1875, places=4)

    def test_several_products_with_different_prices_are_not_estimated(self):
        self.seed("AmazonEKS", {"regionCode": "sa-east-1"},
                  [product("E1", "SAE1-AmazonEKS-Hours:perCluster", [(0, None, 0.10)]),
                   product("E2", "AmazonEKS-Hours:perCluster", [(0, None, 0.60)])])
        lines = self.run_lookup([("aws_eks_cluster.k", "aws_eks_cluster", ["create"])], {})
        line = lines[("aws_eks_cluster.k", "hours")]
        self.assertEqual(line["status"], "not-estimated")
        self.assertIn("different prices", line["reason"])
        self.assertNotIn("monthly_usd", line)

    def test_identical_duplicates_are_estimated_with_a_note(self):
        self.seed("AmazonEKS", {"regionCode": "sa-east-1"},
                  [product("E1", "SAE1-AmazonEKS-Hours:perCluster", [(0, None, 0.10)]),
                   product("E2", "AmazonEKS-Hours:perCluster", [(0, None, 0.10)])])
        line = self.run_lookup([("aws_eks_cluster.k", "aws_eks_cluster", ["create"])], {})[
            ("aws_eks_cluster.k", "hours")]
        self.assertEqual(line["status"], "estimated")
        self.assertAlmostEqual(line["monthly_usd"], 73.0, places=2)
        self.assertIn("identical prices", line["note"])

    def test_missing_assumption_is_not_estimated(self):
        self.seed("AmazonS3", {"regionCode": "sa-east-1", "storageClass": "General Purpose"},
                  [product("S1", "SAE1-TimedStorage-ByteHrs", [(0, None, 0.0405)])])
        line = self.run_lookup([("aws_s3_bucket.assets", "aws_s3_bucket", ["create"])], {})[
            ("aws_s3_bucket.assets", "storage")]
        self.assertEqual(line["status"], "not-estimated")
        self.assertIn("missing assumption storage_gb", line["reason"])

    def test_offline_without_recording_is_not_estimated(self):
        line = self.run_lookup([("aws_lb.web", "aws_lb", ["create"])], {})[("aws_lb.web", "hours")]
        self.assertEqual(line["status"], "not-estimated")
        self.assertIn("no recorded price response", line["reason"])

    def test_unmapped_and_no_cost_types(self):
        lines = self.run_lookup([("aws_sqs_queue.q", "aws_sqs_queue", ["create"]),
                                 ("aws_vpc.v", "aws_vpc", ["create"])], {})
        self.assertEqual(lines[("aws_sqs_queue.q", None)]["status"], "not-mapped")
        self.assertNotIn(("aws_vpc.v", None), lines)

    def test_before_side_skips_creates(self):
        self.seed("AmazonEKS", {"regionCode": "sa-east-1"},
                  [product("E1", "SAE1-AmazonEKS-Hours:perCluster", [(0, None, 0.10)])])
        lines = self.run_lookup([("aws_eks_cluster.new", "aws_eks_cluster", ["create"]),
                                 ("aws_eks_cluster.old", "aws_eks_cluster", ["delete"])], {}, side="before")
        self.assertIn(("aws_eks_cluster.old", "hours"), lines)
        self.assertNotIn(("aws_eks_cluster.new", "hours"), lines)


if __name__ == "__main__":
    unittest.main()
