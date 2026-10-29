# Consequence contract — `.agents/consequence.yml`

The repository declares which paths are consequential, and the agent's tools respect it (spec §2.3
"review by consequence", §5.3). `.agents/consequence.yml` is committed. `build` writes it from discovery
and the user's confirmation (`skills/build/references/authority.md`); the installed hook and the
settings read it; the installed scripts never reach this file in the plugin.
Skills reach this file as `${CLAUDE_PLUGIN_ROOT}/contracts/consequence.md`.

## Format

A line format a bash parser reads, with no YAML library:

```
# a comment
harness: .agents/**
!.agents/run/**
secrets: **/.env
```

- One `category: glob` per line. `#` starts a comment (a whole line, or after a space). Blank lines and
  lines the parser does not understand are ignored; a broken line never stops the others.
- A category name is lowercase letters, digits, `_` or `-`. The same category may appear on many lines.
- `!glob` removes matches from the category declared **above** it. The last line that matches a path wins,
  so a later `category: glob` line can add it back.
- A glob is matched against the **repository-relative** path of the file (no leading `./`, never absolute):
  - `*` and `?` stay inside one path segment (they do not match `/`);
  - `**` crosses segments, and `**/` at the start or in the middle means "zero or more directories";
  - a pattern ending in `/**` covers everything under the directory (`.agents/**`);
  - a pattern with no slash is anchored at the repository root. Write `**/.env` for any depth;
  - every other character is literal, `[` and `]` included.

## Categories

| Category | Policy | Default globs (`build` proposes, the user confirms) |
| --- | --- | --- |
| `harness` | The hook denies the edit unless a `build` or `rules` approval is current (below) | `.agents/**` minus `.agents/run/**`, `.agents/plans/**` and `.agents/progress.md`; `scripts/gate.sh`, `scripts/harness-check.sh`, `scripts/sensors/**`, `scripts/lib/**`, `scripts/hooks/**`, `.github/workflows/keel.yml`, `.claude/settings.json` |
| `secrets` | `permissions.deny` blocks Read and Edit (`settings-protect.json`); the hook asks as a fallback | `**/.env`, `**/.env.*` minus `**/.env.example`, `**/*.pem`, `**/*.key` |
| `auth`, `data`, `infra`, `public-contract` | The hook asks, the reason naming the category | Discovered, only what exists: `**/auth/**`, `**/migrations/**`, `terraform/**` or `infra/**`, `openapi*.y*ml`, `**/*.proto` |

Any other category name behaves like the last row: the hook asks. `.claude/settings.json` is in `harness`
because it holds the hook entry; without it the agent could remove the protection it is under.

## The hook (`assets/adapters/claude/claude-protect.sh`)

Installed as `scripts/hooks/claude-protect.sh` and run by Claude Code before `Write`, `Edit` and
`NotebookEdit` (matcher `Write|Edit|NotebookEdit`, an exact list of tool names).

**Input.** The hook reads the PreToolUse JSON on stdin: `tool_name` and `tool_input`. `Write` and `Edit`
carry `tool_input.file_path`, which Claude Code makes absolute before the hook runs;
`NotebookEdit` carries `tool_input.notebook_path`. A relative path is read against the repository root
(`CLAUDE_PROJECT_DIR`, else the git top level, else the current directory). The path is resolved
lexically (`.`, `..`, `//`) and through symlinked directories before it is matched.

**Output.** A decision is one JSON object on stdout, exit 0:
`{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"…"}}`
with `permissionDecision` `deny` or `ask`. Exit 0 with no output means "no opinion": the normal permission
flow runs and a hook never approves anything by staying silent. The hook never exits 2 and never
exits non-zero: a payload it cannot parse, a missing map, a missing `git` all end in no output, because
a broken hook must not block every edit in the session. The deny decision is the protection.

| Path | Result |
| --- | --- |
| `harness`, no current approval | `deny`: `<path> is part of the agent harness (harness). Change it through /keel-harness:build or /keel-harness:rules, or record the decision in an ADR and ask the user.` |
| `harness`, current approval | no output |
| any other category | `ask`, the reason naming every category the path is in |
| no match, or no `.agents/consequence.yml` | no output |

**A current approval** links the flow of `scripts/keel` (`contracts/flow.md`) to the hook, so the agent
cannot write harness files without having recorded an approval. In `.agents/run/flow/` there is a
`build` or `rules` flow with:

1. `<skill>.applied`, written by `keel apply`, and not older than `<skill>.approved`;
2. `<skill>.applied` last written at most 2 hours ago;
3. the hash in `<skill>.approved` equal to `git hash-object .agents/run/flow/<skill>.proposal`.

Any other skill name, a missing file, an empty record or a changed proposal is "no approval".

## Why permissions for secrets and a hook for the harness

The hooks documentation (`https://code.claude.com/docs/en/hooks`) advises the permission system, not a
hook, for a hard allow or deny. So `secrets` uses `permissions.deny`
(`https://code.claude.com/docs/en/permissions`, "Read and Edit": a `Read` deny rule also blocks `Write`;
`NotebookEdit` is covered only by an `Edit` rule, so the fragment carries both). The harness uses the hook
because only a hook can let the same write through during an approved `build` or `rules` flow.

## Known limit

- **Bash commands that write harness paths are not caught by this hook** (`echo x > .agents/gate.env`,
  `sed -i`, a formatter). `guard` in the gate, pre-commit and CI still catches loosenings of baselines,
  limits, lists, budgets and the sensor set (`contracts/sensor.md`, spec §5.3).
- The approval is a record the agent itself writes with `keel approve`. It proves that what was approved is
  what got applied, not that a human said yes; the same limit as `contracts/flow.md`.
- A symlink as the file itself (not a directory) and a case-insensitive file system that spells a
  protected path differently are not resolved.
- The hook and the map only cover Claude Code. Other agents, and people, are covered by `guard` and CI,
  and by CODEOWNERS on the same paths (`skills/build/references/authority.md`).
