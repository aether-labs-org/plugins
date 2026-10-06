"""Command-line interface for the second-brain vault (spec section 5)."""
import argparse
import json
import re
import sys
from pathlib import Path

from . import index as index_mod
from . import logfile
from .fsutil import write_atomic
from .lint import check_note, lint as run_lint
from .links import WIKILINK, extract, prose_lines, target_name
from .vault import MARKER, VaultError, find_vault, load_config, load_note, load_notes

EXIT_OK, EXIT_FINDINGS, EXIT_USAGE = 0, 1, 2


def _vault(args, err):
    if args.vault:
        root = Path(args.vault).resolve()
        if not (root / MARKER).is_file():
            print("sb: %s is not a second-brain vault (%s not found)" % (root, MARKER), file=err)
            return None
        return root
    root = find_vault(Path.cwd())
    if root is None:
        print("sb: no %s found from %s upward; run /second-brain:init" % (MARKER, Path.cwd()),
              file=err)
    return root


def _emit(args, out, payload, text=""):
    if args.json:
        json.dump(payload, out, ensure_ascii=False, indent=2)
        out.write("\n")
    elif text:
        out.write(text.rstrip("\n") + "\n")


def cmd_index(args, out, err):
    root = _vault(args, err)
    if root is None:
        return EXIT_USAGE
    notes = load_notes(root)
    if args.write:
        write_atomic(root / "_index.md", index_mod.build(notes))
        _emit(args, out, {"notes": len(notes), "written": True},
              "wrote _index.md (%d notes)" % len(notes))
        return EXIT_OK
    diff = index_mod.drift(root, notes)
    _emit(args, out, {"in_sync": not diff, "diff": diff}, diff)
    return EXIT_FINDINGS if diff else EXIT_OK


def cmd_lint(args, out, err):
    root = _vault(args, err)
    if root is None:
        return EXIT_USAGE
    try:
        config = load_config(root)
    except VaultError as exc:
        print("sb: %s" % exc, file=err)
        return EXIT_USAGE
    findings = run_lint(root, config)
    _emit(args, out, [f.as_dict() for f in findings], "\n".join(str(f) for f in findings))
    return EXIT_FINDINGS if findings else EXIT_OK


def cmd_validate(args, out, err):
    root = _vault(args, err)
    if root is None:
        return EXIT_USAGE
    wiki = root / "wiki"
    findings = []
    for name in args.files:
        path = Path(name).resolve()
        try:
            path.relative_to(wiki)
        except ValueError:
            continue
        if path.suffix == ".md":
            findings += check_note(load_note(root, path))
    _emit(args, out, [f.as_dict() for f in findings], "\n".join(str(f) for f in findings))
    return EXIT_FINDINGS if findings else EXIT_OK


def _suggestions(note, notes):
    linked = {target for _, target in extract(note.body, note.body_line)}
    found = []
    for other in notes:
        if other.name == note.name or other.name in linked:
            continue
        terms = {other.name, str(other.data.get("title", "")).strip()} - {""}
        pairs = [(t, re.compile(r"(?<!\w)%s(?!\w)" % re.escape(t))) for t in sorted(terms)
                 if len(t) >= 3]
        hit = None
        for number, line in prose_lines(note.body, note.body_line):
            text = WIKILINK.sub("", line)
            term = next((t for t, pattern in pairs if pattern.search(text)), None)
            if term:
                hit = (number, term)
                break
        if hit:
            found.append({"name": other.name, "term": hit[1], "line": hit[0]})
    return found


def cmd_links(args, out, err):
    root = _vault(args, err)
    if root is None:
        return EXIT_USAGE
    notes = load_notes(root)
    by_name = {n.name: n for n in notes}
    wanted = target_name(args.note)
    note = by_name.get(wanted)
    if note is None:
        print("sb: note not found: %s" % args.note, file=err)
        return EXIT_USAGE
    outgoing = [{"target": t, "line": line, "resolved": t in by_name}
                for line, t in extract(note.body, note.body_line)]
    backlinks = sorted(n.name for n in notes if n.name != wanted and
                       any(t == wanted for _, t in extract(n.body, n.body_line)))
    payload = {"note": note.rel, "outgoing": outgoing, "backlinks": backlinks,
               "unresolved": sorted({o["target"] for o in outgoing if not o["resolved"]})}
    if args.suggest:
        payload["suggestions"] = _suggestions(note, notes)
    text = ["%s" % note.rel,
            "outgoing: %s" % (", ".join(o["target"] for o in outgoing) or "-"),
            "backlinks: %s" % (", ".join(backlinks) or "-"),
            "unresolved: %s" % (", ".join(payload["unresolved"]) or "-")]
    for s in payload.get("suggestions", []):
        text.append("suggest [[%s]] (line %d, matched %r)" % (s["name"], s["line"], s["term"]))
    _emit(args, out, payload, "\n".join(text))
    return EXIT_OK


def cmd_log(args, out, err):
    root = _vault(args, err)
    if root is None:
        return EXIT_USAGE
    try:
        logfile.append(root, args.event, args.title)
    except ValueError as exc:
        print("sb: %s" % exc, file=err)
        return EXIT_USAGE
    return EXIT_OK


def cmd_init(args, out, err):
    from . import init as init_mod

    target = Path(args.vault).resolve() if args.vault else Path.cwd()
    parent = find_vault(target)
    if parent is not None and parent != target:
        print("sb: %s is inside the existing vault %s" % (target, parent), file=err)
        return EXIT_USAGE
    areas = [a for a in args.areas.split(",") if a.strip()]
    result = init_mod.run(target, language=args.language, areas=areas, git=args.git)
    lines = ["%s: %s" % (result["status"], target)]
    if result["created"]:
        lines.append("created: " + ", ".join(result["created"]))
    if result["kept"]:
        lines.append("kept: " + ", ".join(result["kept"]))
    lines += ["warning: " + w for w in result["warnings"]]
    _emit(args, out, result, "\n".join(lines))
    return EXIT_OK


def build_parser():
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--vault", help="vault root (default: nearest %s upward)" % MARKER)
    common.add_argument("--json", action="store_true", help="machine-readable output")

    parser = argparse.ArgumentParser(prog="sb", description="second-brain vault tooling")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("index", parents=[common], help="rebuild or check _index.md")
    group = p.add_mutually_exclusive_group(required=True)
    group.add_argument("--write", action="store_true")
    group.add_argument("--check", action="store_true")
    p.set_defaults(func=cmd_index)

    p = sub.add_parser("lint", parents=[common], help="run the lint rules")
    p.set_defaults(func=cmd_lint)

    p = sub.add_parser("links", parents=[common], help="links and backlinks of a note")
    p.add_argument("note", help="note name or path")
    p.add_argument("--suggest", action="store_true", help="list unlinked exact title mentions")
    p.set_defaults(func=cmd_links)

    p = sub.add_parser("validate", parents=[common], help="validate frontmatter of notes")
    p.add_argument("files", nargs="+")
    p.set_defaults(func=cmd_validate)

    p = sub.add_parser("log", parents=[common], help="append to _log.md")
    p.add_argument("event", choices=logfile.EVENTS)
    p.add_argument("title")
    p.set_defaults(func=cmd_log)

    p = sub.add_parser("init", parents=[common], help="create a vault in the target directory")
    p.add_argument("--language", default="en")
    p.add_argument("--areas", default="", help="comma-separated initial areas")
    p.add_argument("--git", action="store_true", help="run git init if there is no .git")
    p.set_defaults(func=cmd_init)
    return parser


def main(argv=None, out=None, err=None):
    out = out or sys.stdout
    err = err or sys.stderr
    try:
        args = build_parser().parse_args(argv)
    except SystemExit as exc:
        return exc.code if isinstance(exc.code, int) else EXIT_USAGE
    return args.func(args, out, err)
