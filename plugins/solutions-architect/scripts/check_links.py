#!/usr/bin/env python3
"""Check that the links of the discovery benchmark catalog still open.

Usage: check_links.py [--offline] [catalog.md]
Needs network, so it is NOT part of the test suite: run it by hand or on a schedule.
--offline only checks the shape of the catalog (columns, https links, dates, no duplicates).
Line 1 follows the sensor contract: id<TAB>class<TAB>status<TAB>summary. Exit 0 pass, 1 fail.
A 401/403/406/429 answer or a redirect to another host is a warning (open it by hand), not a fail.
"""
import os
import re
import sys
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT = os.path.join(HERE, "..", "skills", "discovery", "references", "benchmarks.md")
KINDS = {"pattern", "strategy", "anti-case"}
DATE = re.compile(r"^(\d{4}(-\d{2}(-\d{2})?)?|undated)$")
SOFT = {401, 403, 406, 429}


def parse(path):
    """Return (entries, problems). An entry is a dict; classes come from the H2 headings."""
    entries, problems, cls = [], [], None
    with open(path, encoding="utf-8") as fh:
        for n, line in enumerate(fh, 1):
            if line.startswith("## "):
                cls = line[3:].strip()
                continue
            if not line.startswith("|") or cls is None:
                continue
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if cells[0] in ("Title", "") or set(cells[0]) <= set("-: "):
                continue
            if len(cells) != 7:
                problems.append(f"line {n}: {len(cells)} columns, expected 7")
                continue
            title, kind, company, published, accessed, link, when = cells
            if kind not in KINDS:
                problems.append(f"line {n}: kind '{kind}' must be one of {sorted(KINDS)}")
            if not link.startswith("https://"):
                problems.append(f"line {n}: link must be https")
            if not DATE.match(published):
                problems.append(f"line {n}: published '{published}' must be a date or 'undated'")
            if not re.match(r"^\d{4}-\d{2}-\d{2}$", accessed):
                problems.append(f"line {n}: accessed '{accessed}' must be YYYY-MM-DD")
            if not when:
                problems.append(f"line {n}: 'Open when' is empty")
            entries.append({"line": n, "class": cls, "title": title, "kind": kind, "company": company,
                            "published": published, "accessed": accessed, "link": link})
    links = [e["link"] for e in entries]
    for dup in sorted({x for x in links if links.count(x) > 1}):
        problems.append(f"duplicate link {dup}")
    return entries, problems


def check(url):
    """Return (status, detail): ok, warn or fail."""
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (link check)"})
    try:
        with urllib.request.urlopen(req, timeout=25) as resp:
            final = resp.geturl()
            host = lambda u: re.sub(r"^https?://([^/]+).*", r"\1", u)
            if host(final) != host(url):
                return "warn", f"redirected to {final}"
            return "ok", str(resp.status)
    except urllib.error.HTTPError as exc:
        return ("warn" if exc.code in SOFT else "fail"), f"HTTP {exc.code}"
    except Exception as exc:  # network down, DNS, timeout
        return "fail", str(exc)[:80]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    offline = "--offline" in sys.argv
    path = args[0] if args else DEFAULT
    try:
        entries, problems = parse(path)
    except OSError as exc:
        print(f"check-links\tcorrectness\tfail\tcannot read {path}: {exc}")
        sys.exit(1)
    if not entries:
        problems.append("no entries found")
    failed, warned = [], []
    if not offline and not problems:
        for e in entries:
            status, detail = check(e["link"])
            if status == "fail":
                failed.append(f"{e['title']}: {detail} ({e['link']})")
            elif status == "warn":
                warned.append(f"{e['title']}: {detail} ({e['link']})")
    bad = problems + failed
    if bad:
        print(f"check-links\tcorrectness\tfail\t{len(bad)} problem(s) in {len(entries)} entries")
        for b in bad[:20]:
            print(f"  {b}")
        print("  guidance: fix or replace the entry; never keep a link that was not opened.")
        sys.exit(1)
    mode = "shape only" if offline else f"{len(warned)} warning(s)"
    print(f"check-links\tcorrectness\tpass\t{len(entries)} entries ok ({mode})")
    for w in warned:
        print(f"  warning: {w}")
    sys.exit(0)


if __name__ == "__main__":
    main()
