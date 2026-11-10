import io
import json
import sqlite3
import tempfile
import unittest
from unittest import mock

from sb_helpers import make_vault, note
from sb import cli
from sb.search import STOPWORDS, SearchIndex, fold, tokenize
from sb.vault import CACHE_DIR


class TokenizerTests(unittest.TestCase):
    def test_fold(self):
        self.assertEqual(fold("Repetição Ç"), "repeticao c")

    def test_tokenize_drops_stopwords_duplicates_and_caps(self):
        self.assertEqual(tokenize("Como o Repetição repeticao ESPAÇADA"), ["repeticao", "espacada"])
        self.assertEqual(len(tokenize(" ".join("w%d" % i for i in range(100)), cap=64)), 64)

    def test_stopwords_are_folded(self):
        self.assertIn("nao", STOPWORDS)
        self.assertNotIn("não", STOPWORDS)


class SearchTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def test_accent_folding_both_directions(self):
        root = make_vault(self.tmp.name, {
            "Resources/Repetição Espaçada.md": note("Repetição Espaçada", summary="Revisar em intervalos."),
            "Resources/Interleaving.md": note("Interleaving", body="mistura de topicos e repeticao")})
        names = [r["name"] for r in SearchIndex(root).search("repeticao espacada")]
        self.assertEqual(names[0], "Repetição Espaçada")
        self.assertIn("Interleaving", [r["name"] for r in SearchIndex(root).search("tópicos")])

    def test_title_outranks_body_and_alias_matches(self):
        root = make_vault(self.tmp.name, {
            "Resources/Active Recall.md": note("Active Recall", summary="Testing yourself.", body="aliases below"),
            "Resources/Other.md": note("Other", body="active recall is mentioned in passing")})
        (root / "wiki/Resources/Active Recall.md").write_text(
            note("Active Recall", summary="Testing yourself.").replace(
                "source:", "aliases:\n  - flashcards\nsource:"), encoding="utf-8")
        idx = SearchIndex(root)
        self.assertEqual(idx.search("active recall")[0]["name"], "Active Recall")
        self.assertEqual(idx.search("flashcards")[0]["name"], "Active Recall")

    def test_incremental_refresh(self):
        root = make_vault(self.tmp.name, {"Resources/A.md": note("A", body="alpha")})
        idx = SearchIndex(root)
        self.assertEqual(idx.refresh(), 1)
        self.assertEqual(idx.refresh(), 0)
        (root / "wiki/Resources/B.md").write_text(note("B", body="beta"), encoding="utf-8")
        (root / "wiki/Resources/A.md").unlink()
        self.assertEqual(idx.refresh(), 2)
        self.assertEqual([r["name"] for r in idx.search("alpha beta")], ["B"])

    def test_edit_is_picked_up(self):
        root = make_vault(self.tmp.name, {"Resources/A.md": note("A", body="alpha")})
        idx = SearchIndex(root)
        self.assertEqual(len(idx.search("alpha")), 1)
        (root / "wiki/Resources/A.md").write_text(note("A", body="omega changed"), encoding="utf-8")
        self.assertEqual(idx.search("alpha"), [])
        self.assertEqual(len(idx.search("omega")), 1)

    def test_result_shape_and_trust(self):
        root = make_vault(self.tmp.name, {"Areas/X.md": note("X", summary="S.", origin="agent", body="gamma"),
                                          "Areas/Y.md": note("Y", summary="S.", origin="mixed", body="gamma")})
        trusts = {r["name"]: r["trust"] for r in SearchIndex(root).search("gamma")}
        self.assertEqual(trusts, {"X": "unreviewed", "Y": "reviewed"})
        r = SearchIndex(root).search("gamma")[0]
        r = next(x for x in SearchIndex(root).search("gamma") if x["name"] == "X")
        self.assertEqual({k: r[k] for k in ("rel", "folder", "summary", "trust", "matched")},
                         {"rel": "wiki/Areas/X.md", "folder": "Areas", "summary": "S.",
                          "trust": "unreviewed", "matched": 1})
        self.assertEqual(r["trust"], "unreviewed")

    def test_stopword_only_query_returns_nothing(self):
        root = make_vault(self.tmp.name, {"Resources/A.md": note("A")})
        self.assertEqual(SearchIndex(root).search("como o que"), [])

    def test_fallback_matches_fts_top_result(self):
        root = make_vault(self.tmp.name, {"Resources/Repetição.md": note("Repetição"),
                                          "Resources/B.md": note("B", body="outra coisa")})
        self.assertEqual(SearchIndex(root, use_fts=False).search("repeticao")[0]["name"], "Repetição")
        self.assertEqual(SearchIndex(root, use_fts=True).search("repeticao")[0]["name"], "Repetição")

    def test_folder_boost_reorders(self):
        root = make_vault(self.tmp.name, {"Projects/P.md": note("P", body="delta"),
                                          "Resources/R.md": note("R", body="delta")})
        self.assertEqual(SearchIndex(root).search("delta")[0]["name"], "P")  # tie -> name
        self.assertEqual(SearchIndex(root).search("delta", folder_boost={"Resources": 2.0})[0]["name"], "R")

    def test_corrupt_db_is_rebuilt(self):
        root = make_vault(self.tmp.name, {"Resources/A.md": note("A", body="alpha")})
        (root / CACHE_DIR).mkdir(parents=True)
        (root / CACHE_DIR / "search.db").write_bytes(b"not a database")
        self.assertEqual(SearchIndex(root).search("alpha")[0]["name"], "A")

    def test_malformed_note_is_indexed(self):
        root = make_vault(self.tmp.name, {
            "Resources/Bad.md": "---\ntitle: Bad\nsummary: |\n  x\n---\nepsilon body\n",
            "Resources/NoFm.md": "just zeta text\n"})
        self.assertEqual(SearchIndex(root).search("epsilon")[0]["name"], "Bad")
        self.assertEqual(SearchIndex(root).search("zeta")[0]["name"], "NoFm")

    def test_cache_lives_under_agents_second_brain_cache(self):
        root = make_vault(self.tmp.name, {"Resources/A.md": note("A", body="alpha")})
        SearchIndex(root).search("alpha")
        self.assertEqual(CACHE_DIR, ".agents/second-brain/cache")
        self.assertTrue((root / CACHE_DIR / "search.db").is_file())
        self.assertEqual((root / CACHE_DIR / ".gitignore").read_text(), "*\n")
        self.assertFalse((root / ".sb").exists())

    def test_underscore_paths_are_not_indexed(self):
        root = make_vault(self.tmp.name, {"Resources/A.md": note("A"), "Resources/_about.md": "theta"})
        self.assertEqual(SearchIndex(root).search("theta"), [])

    def test_prefix_matching_for_long_tokens(self):
        root = make_vault(self.tmp.name, {"Resources/A.md": note("A", body="repetitions everywhere")})
        self.assertEqual(len(SearchIndex(root).search("repetition")), 1)
        self.assertEqual(SearchIndex(root).search("rep"), [])

    def test_result_has_hits_in_query_order(self):
        root = make_vault(self.tmp.name, {
            "Resources/Circuit Breaker.md": note("Circuit Breaker", body="open state"),
            "Resources/Other.md": note("Other", body="nothing")})
        r = SearchIndex(root).search("state circuit pizza", limit=1)[0]
        self.assertEqual(r["hits"], ["state", "circuit"])
        self.assertEqual(r["matched"], 2)

    def _freq_vault(self):
        return make_vault(self.tmp.name, {
            "Resources/A.md": note("A", body="semana de plantao e fermentacao"),
            "Resources/B.md": note("B", body="outra semana com fermentacoes"),
            "Resources/C.md": note("C", body="semana qualquer"),
            "Resources/D.md": note("D", body="nada")})

    def test_doc_freq_counts_notes_and_total(self):
        df, total = SearchIndex(self._freq_vault()).doc_freq(["semana", "plantao", "inexistente"])
        self.assertEqual((df, total), ({"semana": 3, "plantao": 1, "inexistente": 0}, 4))

    def test_doc_freq_counts_prefix_like_hits(self):
        # same rule as hits: "fermentacao" does not prefix-match "fermentacoes"
        df, _ = SearchIndex(self._freq_vault()).doc_freq(["fermentacao", "ferme"])
        self.assertEqual(df, {"fermentacao": 1, "ferme": 2})

    def test_doc_freq_fallback_matches_fts(self):
        root = self._freq_vault()
        tokens = ["semana", "plantao", "ferme"]
        self.assertEqual(SearchIndex(root, use_fts=False).doc_freq(tokens),
                         SearchIndex(root, use_fts=True).doc_freq(tokens))

    def test_doc_freq_on_locked_db_uses_memory(self):
        index = SearchIndex(self._freq_vault())
        with mock.patch.object(index, "_db", side_effect=sqlite3.OperationalError("database is locked")):
            df, total = index.doc_freq(["semana"])
        self.assertEqual((df["semana"], total), (3, 4))

    def test_doc_freq_after_search_does_not_rescan(self):
        index = SearchIndex(self._freq_vault())
        index.search("semana plantao", limit=5)
        with mock.patch.object(index, "_scan", side_effect=AssertionError("rescanned")):
            df, total = index.doc_freq(["semana"], refresh=False)
        self.assertEqual((df["semana"], total), (3, 4))

    def test_cli_json_and_exit_codes(self):
        root = make_vault(self.tmp.name, {"Resources/A.md": note("A", summary="Sum.", body="alpha")})
        out, err = io.StringIO(), io.StringIO()
        self.assertEqual(cli.main(["search", "alpha", "--json", "--vault", str(root)], out, err), 0)
        self.assertEqual(json.loads(out.getvalue())[0]["name"], "A")
        out = io.StringIO()
        self.assertEqual(cli.main(["search", "alpha", "--vault", str(root)], out, err), 0)
        self.assertEqual(out.getvalue(), "wiki/Resources/A.md  [reviewed]  Sum.\n")
        out = io.StringIO()
        self.assertEqual(cli.main(["search", "nothinghere", "--json", "--vault", str(root)], out, err), 1)
        self.assertEqual(json.loads(out.getvalue()), [])
        self.assertEqual(cli.main(["search", "x", "--folder-boost", "bad", "--vault", str(root)],
                                  io.StringIO(), io.StringIO()), 2)


if __name__ == "__main__":
    unittest.main()
