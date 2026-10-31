"""Vault scaffolding: the backend of /second-brain:init (spec sections 6.3 and 7)."""
import json
import subprocess
from pathlib import Path

from . import index as index_mod
from . import logfile
from .fsutil import write_atomic
from .vault import MARKER, SCHEMA_VERSION

TEMPLATES = Path(__file__).resolve().parents[2] / "templates"
PROFILES = ("personal", "work", "project", "squad")
BASE_DIRS = ("_inbox/_done", "_raw", "_meta", "_views", ".claude")
GITIGNORE_LINES = (".sb/", ".obsidian/workspace*", ".smart-env/")
SQUAD_GITIGNORE_LINES = ("_index.md", "_log.md")
# (path in the vault, template file) written when absent
EXTRA_FILES = ((".claude/settings.json", "settings.json"),
               ("_meta/web-clipper-template.json", "web-clipper-template.json"),
               ("_views/unreviewed.base", "unreviewed.base"))


def load_profile(name):
    if name not in PROFILES:
        raise ValueError("unknown profile %r (expected one of %s)" % (name, ", ".join(PROFILES)))
    return json.loads((TEMPLATES / "profiles" / ("%s.json" % name)).read_text(encoding="utf-8"))


def enclosing_repo(target):
    """The git work tree that contains `target` without being `target` itself, or None."""
    here = Path(target).resolve()
    for candidate in (here, *here.parents):
        if (candidate / ".git").exists():
            return None if candidate == here else candidate
    return None


def about_text(folder):
    parts = ["---", "description: %s" % folder["description"],
             "protected: %s" % ("true" if folder.get("protected") else "false"), "---", ""]
    for heading, key in (("Conventions", "conventions"), ("Examples", "examples"),
                         ("Anti-examples", "anti_examples")):
        parts += ["## %s" % heading, folder.get(key, "").strip(), ""]
    return "\n".join(parts)


def gitignore_lines(sync):
    return GITIGNORE_LINES + (SQUAD_GITIGNORE_LINES if sync == "squad" else ())


def _clean_area(area):
    name = " ".join(str(area).split())
    if not name or name.startswith(".") or "/" in name or "\\" in name:
        return ""
    return name


def _write_new(root, name, text, created, kept):
    path = root / name
    if path.exists():
        kept.append(name)
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        write_atomic(path, text)
        created.append(name)


def _append_gitignore(root, lines, created, kept):
    path = root / ".gitignore"
    existed = path.exists()
    existing = path.read_text(encoding="utf-8") if existed else ""
    present = set(existing.splitlines())
    missing = [line for line in lines if line not in present]
    if not missing:
        kept.append(".gitignore")
        return
    if existing and not existing.endswith("\n"):
        existing += "\n"
    write_atomic(path, existing + "".join(line + "\n" for line in missing))
    (kept if existed else created).append(".gitignore")


def run(root, language="en", profile="personal", remote=None, git=False, areas=()):
    root = Path(root)
    spec = load_profile(profile)
    if (root / MARKER).exists():
        return {"status": "exists", "root": str(root), "created": [], "kept": [MARKER],
                "warnings": []}
    root.mkdir(parents=True, exist_ok=True)
    created, kept, warnings = [], [], []
    folder_names = [f["path"] for f in spec["folders"]]

    clean = []
    for area in areas:
        if not str(area).strip():
            continue
        name = _clean_area(area)
        if not name:
            warnings.append("ignored invalid area name %r" % area)
        elif "Areas" not in folder_names:
            warnings.append("ignored area %r: the %s profile has no Areas folder" % (area, profile))
        else:
            clean.append(name)
    for rel in (*BASE_DIRS, *("wiki/%s" % n for n in folder_names),
                *("wiki/Areas/%s" % a for a in clean)):
        (root / rel).mkdir(parents=True, exist_ok=True)
    for folder in spec["folders"]:
        _write_new(root, "wiki/%s/_about.md" % folder["path"], about_text(folder), created, kept)

    template = (TEMPLATES / "CLAUDE.md").read_text(encoding="utf-8")
    _write_new(root, "CLAUDE.md", template.replace("{{language}}", language), created, kept)
    for rel, source in EXTRA_FILES:
        _write_new(root, rel, (TEMPLATES / source).read_text(encoding="utf-8"), created, kept)
    _append_gitignore(root, gitignore_lines(spec["sync"]), created, kept)
    _write_new(root, "_index.md", index_mod.build([]), created, kept)
    _write_new(root, "_log.md", "", created, kept)

    if git and not (root / ".git").exists():
        try:
            subprocess.run(["git", "init", "-q", str(root)], check=True, capture_output=True)
            created.append(".git")
        except (OSError, subprocess.CalledProcessError) as exc:
            warnings.append("git init failed: %s" % exc)
    if remote and (root / ".git").exists():
        done = subprocess.run(["git", "-C", str(root), "remote", "add", "origin", remote],
                              capture_output=True, text=True)
        if done.returncode != 0:
            warnings.append("git remote add failed: %s" % (done.stderr.strip() or done.stdout.strip()))

    marker = {"schema_version": SCHEMA_VERSION, "language": language, "profile": profile,
              "sync": spec["sync"], "areas": clean}
    write_atomic(root / MARKER, json.dumps(marker, ensure_ascii=False, indent=2) + "\n")
    created.append(MARKER)
    logfile.append(root, "init", "vault created")
    return {"status": "created", "root": str(root), "created": created, "kept": kept,
            "warnings": warnings}


SETTINGS = ".claude/settings.json"


def merge_settings(existing_text, template_text):
    """Additive merge of the settings template into an existing `.claude/settings.json`.

    Adds missing `enabledPlugins` keys, `extraKnownMarketplaces` entries and `permissions.deny`
    rules; never changes or removes an existing value, keeps the order of existing keys and
    appends new ones. A section of an unexpected type is left alone. Returns
    `(new_text, added)` (`added == 0`: nothing to write), or `None` when `existing_text` is not
    a JSON object."""
    try:
        data = json.loads(existing_text)
    except ValueError:
        return None
    if not isinstance(data, dict):
        return None
    template = json.loads(template_text)
    added = 0
    for section in ("enabledPlugins", "extraKnownMarketplaces"):
        wanted = template.get(section) or {}
        if section not in data:
            data[section] = dict(wanted)
            added += len(wanted)
        elif isinstance(data[section], dict):
            for key, value in wanted.items():
                if key not in data[section]:
                    data[section][key] = value
                    added += 1
    wanted = (template.get("permissions") or {}).get("deny") or []
    if "permissions" not in data:
        data["permissions"] = {"deny": list(wanted)}
        added += len(wanted)
    elif isinstance(data["permissions"], dict):
        if "deny" not in data["permissions"]:
            data["permissions"]["deny"] = list(wanted)
            added += len(wanted)
        elif isinstance(data["permissions"]["deny"], list):
            for rule in wanted:
                if rule not in data["permissions"]["deny"]:
                    data["permissions"]["deny"].append(rule)
                    added += 1
    if not added:
        return existing_text, 0
    return json.dumps(data, ensure_ascii=False, indent=2) + "\n", added


def _known_folders(profile):
    """Top-level folder specs by name; the chosen profile wins over the others."""
    found = {}
    for name in ([profile] if profile in PROFILES else []) + list(PROFILES):
        for folder in load_profile(name)["folders"]:
            found.setdefault(folder["path"], folder)
    return found


def _tracked(root, rel):
    done = subprocess.run(["git", "-C", str(root), "ls-files", "--error-unmatch", rel],
                          capture_output=True, text=True)
    return done.returncode == 0


def upgrade(root, profile=None, yes=False):
    """Bring a v0.1 (or partial) vault up to schema 2. Adds missing files only; with
    `yes=False` it only reports the plan. Returns `{"actions", "kept", "applied"}`."""
    from .tree import flatten, load as load_tree
    from .vault import load_config

    root = Path(root)
    if profile is not None and profile not in PROFILES:
        raise ValueError("unknown profile %r (expected one of %s)" % (profile, ", ".join(PROFILES)))
    config = load_config(root)
    actions, kept, warnings = [], [], []
    writes = []                                     # (path, text) applied when `yes`
    post = []                                       # callables applied after the writes

    chosen = profile or config.get("profile") or "personal"
    known = _known_folders(chosen)
    for _, folder in flatten(load_tree(root)):
        rel = "wiki/%s/_about.md" % folder["path"]
        if (root / rel).exists():
            continue
        spec = known.get(folder["path"]) if "/" not in folder["path"] else None
        if spec is None:
            spec = {"description": "(describe this folder)", "protected": False}
            actions.append("add %s (placeholder description)" % rel)
        else:
            actions.append("add %s" % rel)
        writes.append((root / rel, about_text(spec)))

    for rel, source in EXTRA_FILES:
        if rel == SETTINGS and (root / rel).is_file():
            template_text = (TEMPLATES / source).read_text(encoding="utf-8")
            try:
                merged = merge_settings((root / rel).read_text(encoding="utf-8"), template_text)
            except (OSError, UnicodeDecodeError):
                merged = None
            if merged is None:
                kept.append(rel)
                warnings.append("%s is not a valid JSON object: left untouched; fix it by hand "
                                "(templates/settings.json in the plugin is the reference)" % rel)
            elif merged[1] == 0:
                kept.append(rel)
            else:
                actions.append("merge %s (+%d entries)" % (rel, merged[1]))
                writes.append((root / rel, merged[0]))
        elif (root / rel).exists():
            kept.append(rel)
        else:
            actions.append("add %s" % rel)
            writes.append((root / rel, (TEMPLATES / source).read_text(encoding="utf-8")))
    if (root / "CLAUDE.md").exists():
        kept.append("CLAUDE.md")

    sync = load_profile(profile)["sync"] if profile else (config.get("sync") or "local")
    lines = gitignore_lines(sync)
    path = root / ".gitignore"
    existing = path.read_text(encoding="utf-8") if path.exists() else ""
    missing = [line for line in lines if line not in set(existing.splitlines())]
    if missing:
        actions.append("add to .gitignore: %s" % ", ".join(missing))
        text = existing + ("\n" if existing and not existing.endswith("\n") else "")
        writes.append((path, text + "".join(line + "\n" for line in missing)))

    if sync == "squad" and (root / ".git").exists():
        for rel in ("_index.md", "_log.md"):
            if _tracked(root, rel):
                actions.append("git rm --cached %s (stays on disk; local in squad vaults)" % rel)
                post.append(lambda rel=rel: subprocess.run(
                    ["git", "-C", str(root), "rm", "--cached", "-q", rel],
                    capture_output=True, text=True, check=True))

    wanted = dict(config, schema_version=SCHEMA_VERSION, profile=chosen, sync=sync)
    if wanted != config:
        actions.append("update %s: schema_version %s, profile %s, sync %s"
                       % (MARKER, SCHEMA_VERSION, chosen, sync))

    if yes and actions:
        for target, text in writes:
            target.parent.mkdir(parents=True, exist_ok=True)
            write_atomic(target, text)
        for step in post:
            step()
        if wanted != config:
            write_atomic(root / MARKER, json.dumps(wanted, ensure_ascii=False, indent=2) + "\n")
    return {"actions": actions, "kept": kept, "warnings": warnings,
            "applied": bool(yes and actions)}
