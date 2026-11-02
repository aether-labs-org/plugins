"""Deterministic, accent-insensitive vault search (spec 4.2).

The index is a SQLite FTS5 table in `<vault>/.sb/search.db`, refreshed incrementally from file
`(mtime_ns, size)` on every query. Without FTS5 (or when the database cannot be used) the same
fields are scored in memory. Text is folded (NFKD, no combining marks, casefolded) before it is
indexed and before it is queried, so "Repetição" and "repeticao" meet.
"""
import math
import os
import re
import sqlite3
import sys
import unicodedata
from contextlib import closing
from pathlib import Path
from typing import Optional

from .sanitize import clean_inline
from .trust import label
from .vault import is_note_rel, load_note

SCHEMA = "1"
WORD_RE = re.compile(r"\w+")
HEADING_RE = re.compile(r"^#{1,6}[ \t]+(.+)$", re.MULTILINE)
PREFIX_MIN = 5
FIELDS = ("name", "title", "aliases", "summary", "headings", "body")
WEIGHTS = {"name": 10.0, "title": 10.0, "aliases": 8.0, "summary": 5.0, "headings": 3.0,
           "body": 1.0}
SUMMARY_LIMIT = 160


def fold(text):
    """NFKD, drop combining marks, casefold."""
    decomposed = unicodedata.normalize("NFKD", str(text))
    return "".join(c for c in decomposed if not unicodedata.combining(c)).casefold()


_STOPWORDS_RAW = """
a o as os um uma uns umas de do da dos das no na nos nas em ao aos num numa por pelo pela
pelos pelas para pra pro com sem sob sobre entre ate e ou mas nem se que quem qual quais
quando onde como porque porem tambem so ja nao sim mais menos muito muita muitos muitas
eu tu ele ela nos vos eles elas me te lhe lhes meu minha meus minhas teu tua seu sua seus
suas nosso nossa voce voces vc vcs isso isto aquilo esse essa esses essas este esta estes
estas aquele aquela aqueles aquelas aqui ali la ca
ser sou es e somos sao era eram foi foram fui sera seria estar estou esta estao estava
estavam estive ter tenho tem temos tinha tinham tive haver ha havia ir vou vai vamos fui
pode podem posso mesmo tudo todo toda todos todas outro outra depois antes entao assim
to ta tao
i me my mine we us our you your he him his she her it its they them their the an and or but
nor of to in on at for with from by as is are was were be been being am do does did done have
has had having can could should would will shall may might must not no yes if then so than
too very just this that these those there here what how when where why who whom which about
into over under again also all any some such own same other
"""
STOPWORDS = frozenset(fold(w) for w in _STOPWORDS_RAW.split())


def tokenize(text, cap=64):
    """Folded `\\w+` tokens without stopwords or duplicates, in order, at most `cap`."""
    seen, out = set(), []
    for token in WORD_RE.findall(fold(text)):
        if token in STOPWORDS or token in seen:
            continue
        seen.add(token)
        out.append(token)
        if len(out) >= cap:
            break
    return out


def fts5_available():
    try:
        with closing(sqlite3.connect(":memory:")) as conn:
            conn.execute("CREATE VIRTUAL TABLE temp.t USING fts5(x)")
        return True
    except sqlite3.Error:
        return False


def _text(value):
    if isinstance(value, (list, tuple)):
        return " ; ".join(str(v) for v in value)
    return "" if value is None else str(value)


def _entry(note):
    """Everything the index keeps for one note: raw values for output, folded text to search."""
    data = note.data
    parts = note.rel.split("/")                 # wiki/<folder>/.../<file>.md
    title = _text(data.get("title")).strip() or note.name
    summary = _text(data.get("summary"))
    return {
        "rel": note.rel,
        "name": note.name,
        "title": title,
        "folder": parts[1] if len(parts) > 2 else "",
        "dir": "/".join(parts[1:-1]),
        "summary": clean_inline(summary, SUMMARY_LIMIT),
        "trust": label(data, note.body),
        "text": {
            "name": fold(note.name),
            "title": fold(title),
            "aliases": fold(_text(data.get("aliases"))),
            "summary": fold(summary),
            "headings": fold("\n".join(HEADING_RE.findall(note.body))),
            "body": fold(note.body),
        },
    }


def _word_matches(token, words):
    if token in words:
        return True
    if len(token) >= PREFIX_MIN:
        return any(w.startswith(token) for w in words)
    return False


def _matched_tokens(tokens, text):
    """The query tokens that match the note (exact word, or word prefix for long tokens)."""
    words = set()
    for field in FIELDS:
        words.update(WORD_RE.findall(text[field]))
    return [token for token in tokens if _word_matches(token, words)]


def _boost_factor(folder_boost, directory):
    if not folder_boost:
        return 1.0
    best = None
    for key, weight in folder_boost.items():
        key = key.strip("/")
        if directory == key or directory.startswith(key + "/"):
            if best is None or len(key) > len(best[0]):
                best = (key, weight)
    return 1.0 + (best[1] if best else 0.0)


def _is_locked(exc):
    return "locked" in str(exc).lower() or "busy" in str(exc).lower()


class SearchIndex:
    def __init__(self, root, use_fts: Optional[bool] = None):
        self.root = Path(root)
        self.dir = self.root / ".sb"
        self.db_path = self.dir / "search.db"
        self._warned = False
        self._mem = {}                          # rel -> {"sig": (mtime_ns, size), "entry": {...}}
        self.use_fts = use_fts
        if use_fts is None:
            self.use_fts = fts5_available()
            if not self.use_fts:
                self._warn()
        self._prepare_dir()

    # -- plumbing -----------------------------------------------------------------------------

    def _warn(self):
        if not self._warned:
            self._warned = True
            print("sb: FTS5 unavailable, using slow search", file=sys.stderr)

    def _prepare_dir(self):
        try:
            self.dir.mkdir(exist_ok=True)
            gitignore = self.dir / ".gitignore"
            if not gitignore.exists():
                gitignore.write_text("*\n", encoding="utf-8")
        except OSError:
            self.use_fts = False                # read-only vault: stay in memory

    def _scan(self):
        """{rel: (mtime_ns, size, path)} for every note under wiki/."""
        wiki = self.root / "wiki"
        found = {}
        if not wiki.is_dir():
            return found
        for current, dirs, files in os.walk(str(wiki)):
            dirs[:] = sorted(d for d in dirs if not d.startswith((".", "_")))
            for fname in files:
                if not fname.endswith(".md"):
                    continue
                path = Path(current) / fname
                if not is_note_rel(path.relative_to(wiki).as_posix()):
                    continue
                try:
                    st = path.stat()
                except OSError:
                    continue
                found[path.relative_to(self.root).as_posix()] = (st.st_mtime_ns, st.st_size, path)
        return found

    def _connect(self):
        conn = sqlite3.connect(str(self.db_path), timeout=2.0)
        try:
            conn.execute("PRAGMA synchronous = OFF")
            conn.execute("CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT)")
            row = conn.execute("SELECT value FROM meta WHERE key = 'schema'").fetchone()
            if row is None:
                with conn:
                    conn.execute("CREATE TABLE IF NOT EXISTS files(id INTEGER PRIMARY KEY, "
                                 "rel TEXT UNIQUE, mtime_ns INTEGER, size INTEGER, name TEXT, "
                                 "title TEXT, folder TEXT, dir TEXT, summary TEXT, trust TEXT)")
                    conn.execute("CREATE VIRTUAL TABLE IF NOT EXISTS notes USING fts5("
                                 "rel UNINDEXED, name, title, aliases, summary, headings, body, "
                                 "tokenize = 'unicode61 remove_diacritics 2')")
                    conn.execute("INSERT OR REPLACE INTO meta VALUES ('schema', ?)", (SCHEMA,))
            elif row[0] != SCHEMA:
                raise sqlite3.DatabaseError("search index schema mismatch")
            return conn
        except BaseException:
            conn.close()
            raise

    def _reset_db(self):
        for suffix in ("", "-journal", "-wal", "-shm"):
            try:
                os.unlink(str(self.db_path) + suffix)
            except OSError:
                pass

    def _db(self, operation):
        """Run `operation(conn)` on the database; rebuild a damaged file once; return the
        result, or raise sqlite3.Error when the database cannot be used at all."""
        for attempt in (0, 1):
            try:
                with closing(self._connect()) as conn:
                    return operation(conn)
            except sqlite3.DatabaseError as exc:
                if _is_locked(exc) or attempt:
                    raise
                self._reset_db()
        raise sqlite3.DatabaseError("unreachable")

    # -- refresh --------------------------------------------------------------------------------

    def refresh(self):
        """Bring the index in line with wiki/. Returns how many notes were added, changed or
        removed."""
        if self.use_fts:
            try:
                return self._db(self._refresh_fts)
            except sqlite3.Error:
                self.use_fts = False            # unusable or locked: score in memory
        return self._refresh_mem()

    def _refresh_fts(self, conn):
        current = self._scan()
        stored = {rel: (mt, size, fid) for fid, rel, mt, size in
                  conn.execute("SELECT id, rel, mtime_ns, size FROM files")}
        stale = [rel for rel in stored if rel not in current]
        changed = [rel for rel, (mt, size, _) in current.items()
                   if rel not in stored or stored[rel][:2] != (mt, size)]
        if not stale and not changed:
            return 0
        with conn:
            for rel in stale + [r for r in changed if r in stored]:
                fid = stored[rel][2]
                conn.execute("DELETE FROM notes WHERE rowid = ?", (fid,))
                conn.execute("DELETE FROM files WHERE id = ?", (fid,))
            for rel in changed:
                mtime_ns, size, path = current[rel]
                e = _entry(load_note(self.root, path))
                cur = conn.execute(
                    "INSERT INTO files(rel, mtime_ns, size, name, title, folder, dir, summary, "
                    "trust) VALUES (?,?,?,?,?,?,?,?,?)",
                    (rel, mtime_ns, size, e["name"], e["title"], e["folder"], e["dir"],
                     e["summary"], e["trust"]))
                t = e["text"]
                conn.execute("INSERT INTO notes(rowid, rel, name, title, aliases, summary, "
                             "headings, body) VALUES (?,?,?,?,?,?,?,?)",
                             (cur.lastrowid, rel, t["name"], t["title"], t["aliases"],
                              t["summary"], t["headings"], t["body"]))
        return len(stale) + len(changed)

    def _refresh_mem(self):
        current = self._scan()
        stale = [rel for rel in self._mem if rel not in current]
        changed = [rel for rel, (mt, size, _) in current.items()
                   if rel not in self._mem or self._mem[rel]["sig"] != (mt, size)]
        for rel in stale:
            del self._mem[rel]
        for rel in changed:
            mtime_ns, size, path = current[rel]
            self._mem[rel] = {"sig": (mtime_ns, size), "entry": _entry(load_note(self.root, path))}
        return len(stale) + len(changed)

    # -- search ---------------------------------------------------------------------------------

    def search(self, query, limit=10, folder_boost: Optional[dict] = None):
        tokens = tokenize(query)
        if not tokens or limit < 1:
            return []
        self.refresh()
        pool = limit * 3 if not folder_boost else max(limit * 10, 50)
        if self.use_fts:
            try:
                rows = self._db(lambda conn: self._query_fts(conn, tokens, pool))
            except sqlite3.Error:
                self.use_fts = False
                rows = self._query_mem(tokens)
        else:
            rows = self._query_mem(tokens)
        results = []
        for score, entry in rows:
            score *= _boost_factor(folder_boost, entry["dir"])
            hits = _matched_tokens(tokens, entry["text"])
            results.append({
                "rel": entry["rel"], "name": entry["name"], "title": entry["title"],
                "folder": entry["folder"], "summary": entry["summary"], "score": score,
                "hits": hits, "matched": len(hits), "trust": entry["trust"]})
        results.sort(key=lambda r: (-r["score"], r["name"]))
        return results[:limit]

    def doc_freq(self, tokens):
        """({token: number of notes matching it}, total notes indexed). A token matches a note
        the same way it does in `search` (exact word, or word prefix for long tokens)."""
        self.refresh()
        if self.use_fts:
            try:
                return self._db(lambda conn: self._doc_freq_fts(conn, tokens))
            except sqlite3.Error:
                self.use_fts = False
        return self._doc_freq_mem(tokens)

    def _doc_freq_fts(self, conn, tokens):
        total = conn.execute("SELECT count(*) FROM files").fetchone()[0]
        df = {token: conn.execute("SELECT count(*) FROM notes WHERE notes MATCH ?",
                                  (self._expression([token]),)).fetchone()[0]
              for token in tokens}
        return df, total

    def _doc_freq_mem(self, tokens):
        df = {token: 0 for token in tokens}
        for item in self._mem.values():
            text = item["entry"]["text"]
            words = set()
            for field in FIELDS:
                words.update(WORD_RE.findall(text[field]))
            for token in tokens:
                if _word_matches(token, words):
                    df[token] += 1
        return df, len(self._mem)

    @staticmethod
    def _expression(tokens):
        terms = []
        for token in tokens:
            terms.append('"%s"' % token)
            if len(token) >= PREFIX_MIN:
                terms.append('"%s"*' % token)
        return " OR ".join(terms)

    def _query_fts(self, conn, tokens, pool):
        weights = ", ".join(str(w) for w in (0.0,) + tuple(WEIGHTS[f] for f in FIELDS))
        sql = ("SELECT files.rel, files.name, files.title, files.folder, files.dir, "
               "files.summary, files.trust, bm25(notes, %s), notes.aliases, notes.headings, "
               "notes.body, notes.summary, notes.title, notes.name "
               "FROM notes JOIN files ON files.id = notes.rowid WHERE notes MATCH ? "
               "ORDER BY bm25(notes, %s) LIMIT ?" % (weights, weights))
        rows = []
        for (rel, name, title, folder, directory, summary, trust, rank, aliases, headings,
             body, fsummary, ftitle, fname) in conn.execute(sql, (self._expression(tokens), pool)):
            entry = {"rel": rel, "name": name, "title": title, "folder": folder,
                     "dir": directory, "summary": summary, "trust": trust,
                     "text": {"name": fname, "title": ftitle, "aliases": aliases,
                              "summary": fsummary, "headings": headings, "body": body}}
            rows.append((-rank, entry))
        return rows

    def _query_mem(self, tokens):
        docs = []
        for item in self._mem.values():
            entry = item["entry"]
            docs.append((entry, {f: WORD_RE.findall(entry["text"][f]) for f in FIELDS}))
        total = len(docs)
        counts = {}                             # token -> per-document {field: occurrences}
        idf = {}
        for token in tokens:
            counts[token] = [
                {f: sum(1 for w in words[f]
                        if w == token or (len(token) >= PREFIX_MIN and w.startswith(token)))
                 for f in FIELDS} for _, words in docs]
            df = sum(1 for c in counts[token] if any(c.values()))
            idf[token] = math.log(1.0 + (total - df + 0.5) / (df + 0.5))
        scored = []
        for index, (entry, words) in enumerate(docs):
            score = 0.0
            for token in tokens:
                for f in FIELDS:
                    tf = counts[token][index][f]
                    if not tf:
                        continue
                    length = 0.25 + 0.75 * len(words[f]) / 100.0 if f == "body" else 1.0
                    score += WEIGHTS[f] * idf[token] * tf / (tf + 1.2 * length)
            if score > 0:
                scored.append((score, entry))
        return scored
