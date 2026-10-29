# Authority: the consequence map, the protect hook and CODEOWNERS

The repository declares which paths are consequential, and the agent's tools respect it
(spec §2.3 "review by consequence", §5.3; component C7). This is the `authority` layer in
`.agents/state.yml`. The Stop hook reaches the gate; this layer reaches the agent's edits.

| Piece | Where it lives | What it does |
| --- | --- | --- |
| Consequence map | `.agents/consequence.yml` (committed) | Paths by category. Format and policies: `${CLAUDE_PLUGIN_ROOT}/contracts/consequence.md` |
| Protect hook | `scripts/hooks/claude-protect.sh` + a `PreToolUse` entry in `.claude/settings.json` | Denies `Write`, `Edit` and `NotebookEdit` on `harness` paths unless a `build` or `rules` approval is current; asks on the other categories |
| Deny rules | `permissions.deny` in `.claude/settings.json` | Blocks Read and Edit of `secrets` paths |
| CODEOWNERS | `.github/CODEOWNERS` | Review by consequence for people and for other agents |

The layer is one proposal line and one `installed` or `not_installed`. The map, the hook and the
settings go together (a hook without a map says nothing, a map without the hook protects nothing).
CODEOWNERS is its own accept-or-drop item inside it.

## 1. The map

Copy `${CLAUDE_PLUGIN_ROOT}/assets/core/consequence.yml` to `.agents/consequence.yml`. It already has the
`harness` and `secrets` categories. Then **discover** the consequential categories; add a line only for a
path that exists in this repository, using the read-only commands below (they respect `.gitignore`):

```bash
git ls-files | grep -E '(^|/)(auth|authn|authz|security)/' | head -20      # auth
git ls-files | grep -E '(^|/)(migrations?|db/migrate)/' | head -20         # data
git ls-files | grep -E '^(terraform|infra|infrastructure|deploy|k8s|helm)/|\.tf$' | head -20   # infra
git ls-files | grep -E '(^|/)openapi[^/]*\.ya?ml$|\.proto$|(^|/)schema\.graphql$' | head -20     # public-contract
```

Write one `category: glob` line per hit group (`auth: **/auth/**`, `data: **/migrations/**`,
`infra: terraform/**`, `public-contract: openapi*.y*ml`, `public-contract: **/*.proto`), using the
globs of the contract. Show the whole file, including the defaults, and let the user remove or add lines.
**Never add a line for a path nothing in the repository matches**, and never invent a category from a
guess: no hit means no line. A repository with no hit has just `harness` and `secrets`, which is correct.

## 2. The hook and the settings fragment

1. Copy `${CLAUDE_PLUGIN_ROOT}/assets/adapters/claude/claude-protect.sh` to `scripts/hooks/claude-protect.sh`
   (`chmod +x`).
2. Show the user `${CLAUDE_PLUGIN_ROOT}/assets/adapters/claude/settings-protect.json` and, once they accept,
   **merge** it into `.claude/settings.json` exactly as the Stop entry is merged (read the file, keep every
   other key, create the file if it is missing):
   - append the `PreToolUse` entry (matcher `Write|Edit|NotebookEdit`, timeout 10) to `hooks.PreToolUse`;
   - append each `permissions.deny` rule that is not already there, keeping the order (a `!` carve-out
     must stay after the rule it carves from);
   - leave out the fragment's `_source` key: it is a note for you, not a setting.
3. `${CLAUDE_PROJECT_DIR}` is copied literally, backslash-escaped quotes included, as for the Stop hook.

Sources, read on 2026-10-29: the hook's input and decision JSON are in the hooks reference,
`https://code.claude.com/docs/en/hooks` (PreToolUse; `Write` and `Edit` carry `tool_input.file_path`); the
rule syntax (`Read(**/.env)`, gitignore-style paths, `!` carve-outs, a `Read` deny also blocks `Write`,
`NotebookEdit` only through an `Edit` rule) is in `https://code.claude.com/docs/en/permissions`, section
"Read and Edit". The permissions page says `notebook_path` is the primary field of `NotebookEdit`; the
hooks page documents no schema for it, so the hook reads `notebook_path` and falls back from `file_path`.

The `secrets` rules are `permissions.deny`, not the hook, because the hooks page advises the
permission system for a hard deny. If the map's `secrets` globs differ from the defaults, change the
fragment's rules to match before merging them (one `Read(...)` and one `Edit(...)` per glob).

## 3. CODEOWNERS

Propose a line for the `harness` category and for each consequential category the map has (not
`secrets`: `.env` files are not tracked). **Ask who owns each; never invent an owner.** An owner is
whatever the user names (`@user`, `@org/team`, an email). A line they do not answer stays out of the
file, and the proposal says so ("no owner given for `auth`").

- File: the repository's existing `CODEOWNERS` (`.github/CODEOWNERS`, `CODEOWNERS` or `docs/CODEOWNERS`,
  in that order of preference), else `.github/CODEOWNERS`. Append; keep every existing line. The last
  matching pattern wins, so new lines go at the end.
- Pattern: CODEOWNERS uses gitignore-style patterns. `.agents/**` is `/.agents/`, `scripts/sensors/**` is
  `/scripts/sensors/`, `**/auth/**` is `auth/`, `terraform/**` is `/terraform/`, `openapi*.y*ml` is
  `/openapi*.y*ml`, a single file is `/<path>`.
- Owners that already appear in the file are the suggested options when asking; a name seen in `git log`
  is not an owner until the user says so.
- Tell the user to turn on "Require review from Code Owners" in the branch protection; keel cannot.

## 4. The proposal line and the state

```
AUTHORITY  .agents/consequence.yml (harness, secrets, {{discovered categories or none}}), scripts/hooks/claude-protect.sh
           + a protect-hook entry and secrets deny rules in .claude/settings.json; CODEOWNERS: {{N lines, owners as given}} (no owner given for: {{list}})
```

Declined, or nothing to protect yet: `layers: { ..., authority: not_installed }` and
`not_installed: { authority: "<the user's reason>" }`. Installed: `authority: installed`. A state with no
`authority` key was written before this layer existed: propose it on the next run.

## 5. Verify

`${CLAUDE_PLUGIN_ROOT}/scripts/keel verify build` checks the layer when `authority: installed`:
the map parses and declares `harness`, `.claude/settings.json` is valid JSON with a `PreToolUse` entry
that names `scripts/hooks/claude-protect.sh` and the literal `${CLAUDE_PROJECT_DIR}`, and the hook is
executable. `make harness-check` warns `protect-missing` when the layer is installed and any of these is
gone. Two things stay by hand: the CODEOWNERS owners are the ones the user gave, and a smoke test of
the hook:

```bash
printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/.agents/state.yml"}}' "$PWD" | CLAUDE_PROJECT_DIR="$PWD" bash scripts/hooks/claude-protect.sh
```

must print a `deny` decision outside an approved flow, and nothing for `src/anything.ts`.

**Known limit.** The hook does not see Bash commands that write harness paths; `guard` in the gate,
pre-commit and CI still catches loosenings (`${CLAUDE_PLUGIN_ROOT}/contracts/consequence.md`).
