# keel-harness v0.3 — F3c-1 Consequence map and protection: Implementation Plan

> **For agentic workers:** read `docs/plans/2026-10-29-keel-harness-v0.3-agent-rules.md` first. Phase id: `f3c1`. Free; no eval. Starts after F2c is merged. F2d and F3b run in parallel with you. Add your `harness-check` checks as new functions placed just before `# --- review-due`, and their calls just before `check_review_due`.

**Goal:** component C7 plus R; spec §5.3, §2.3 "review by consequence". The repository declares which paths are consequential, and the agent's tools respect it:
- a consequence map;
- a PreToolUse hook that denies edits to harness files outside an approved flow;
- deny rules for secrets;
- CODEOWNERS for consequential paths.

`ENFORCEMENT_LEVEL` (D43) is F3c-2, not this phase.

## Facts to rely on (Claude Code hooks docs, `https://code.claude.com/docs/en/hooks`, read 2026-10-29)

- PreToolUse gets JSON on stdin with `tool_name` and `tool_input`. Write and Edit carry `tool_input.file_path`; **check in the docs which field NotebookEdit uses** (`notebook_path` is expected) before relying on it, and cite it in the report.
- To decide, print `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny|ask|allow","permissionDecisionReason":"…"}}` and exit 0. Exit 0 with no output means "no opinion" (the normal permission flow runs). Exit 2 blocks, with stderr as the message.
- A matcher of only letters and `|` is an exact list: `"matcher": "Write|Edit|NotebookEdit"`.
- The docs advise the permission system, not a hook, for a hard deny. So secrets use `permissions.deny`. Harness files use the hook, because the hook can allow writes during an approved `build`/`rules` flow.

## The consequence map

`contracts/consequence.md` documents `.agents/consequence.yml` (committed). It uses a line format a bash parser can read, with no YAML library: one `category: glob` per line, `#` comments, globs matched against repo-relative paths. A pattern ending in `/**` covers everything under the directory.

| Category | Policy | Default globs (`build` proposes; the user confirms) |
| --- | --- | --- |
| `harness` | hook: deny unless a `build`/`rules` approval is current | `.agents/**` minus `.agents/run/**` and `.agents/plans/**` and `.agents/progress.md`; `scripts/gate.sh`, `scripts/harness-check.sh`, `scripts/sensors/**`, `scripts/lib/**`, `scripts/hooks/**`, `.github/workflows/keel.yml` |
| `secrets` | `permissions.deny` for Read and Edit | `.env`, `.env.*` (not `.env.example`), `**/*.pem`, `**/*.key` |
| `auth`, `data`, `infra`, `public-contract` | hook: `ask`, with the reason naming the category | discovered: `**/auth/**`, `**/migrations/**`, `terraform/**`/`infra/**`, `openapi*.y*ml`, `**/*.proto`; only what exists |

- Negation: lines `!glob` remove matches from the category declared above them.
- "Current approval": `.agents/run/flow/<skill>.applied` exists for `build` or `rules`, is newer than its `.approved`, and is at most 2 hours old. The hash in `.approved` must still be the current proposal's (`git hash-object`). That links the F2c-2 flow to the hook: the agent cannot write harness files without having recorded an approval.

## Tasks

- [ ] **Task 1 — `assets/adapters/claude/claude-protect.sh`** (bash 3.2, no `jq`), tests first in `tests/keel_protect_test.sh`.
  - Read stdin; extract `tool_name` and the path field with `sed`/`grep`, robust to spacing and escaped quotes, and covered by tests. Make the path repo-relative using `CLAUDE_PROJECT_DIR` or `PWD`.
  - Match it against `.agents/consequence.yml`. Apply the policy:
    - `harness` with no current approval → `deny`, reason `"<path> is part of the agent harness (<category>). Change it through /keel-harness:build or /keel-harness:rules, or record the decision in an ADR and ask the user."`;
    - `harness` with a current approval → no output;
    - other categories → `ask`, with the reason naming the category;
    - no match, or no map → exit 0 with no output.
  - Never exit non-zero on a parse problem: print nothing and exit 0, and say why in a comment. A broken hook must not block all editing. The deny decision is the protection.
  - Test with JSON fixtures for Write, Edit and NotebookEdit, inside and outside each category, with and without an approval, an expired approval (`touch -d`), and a stale hash.
  - Commit `feat(keel-harness): claude-protect PreToolUse hook denies harness edits outside an approved flow`.
- [ ] **Task 2 — `assets/adapters/claude/settings-protect.json`**, the fragment to merge:
  - the PreToolUse entry (`matcher` `Write|Edit|NotebookEdit`, command `"${CLAUDE_PROJECT_DIR}"/scripts/hooks/claude-protect.sh`, timeout 10);
  - `permissions.deny` for the `secrets` globs (`Read(./.env)`, `Edit(./.env)`, `Read(./.env.*)`, …). Check the permission-rule syntax in `https://code.claude.com/docs/en/permissions` and cite it.

  Commit with Task 3.
- [ ] **Task 3 — `build` installs it.** A new `authority` layer in the proposal, between hook and enforcement:
  - `.agents/consequence.yml` (generated from discovery, shown, confirmed);
  - `scripts/hooks/claude-protect.sh`;
  - the settings fragment, merged like the Stop hook (keep every key; `${CLAUDE_PROJECT_DIR}` literal);
  - **CODEOWNERS:** propose lines for the `harness` and consequential categories and ask who owns each. Never invent an owner: an unanswered line stays out.

  Also:
  - Record `authority: installed | not_installed` in `layers`, documented in `contracts/state.md`.
  - `keel verify build` checks the PreToolUse entry and the executable hook when the layer is installed (update `scripts/keel` and its tests).
  - New `harness-check` check `protect-missing`: the layer is installed but the hook or map is missing. Add it to the checks table and update the count.
  - Detail lives in `skills/build/references/authority.md`. `build/SKILL.md` stays within its limits.
  - Commit `feat(keel-harness): build installs the consequence map, protect hook and CODEOWNERS proposal`.
- [ ] **Task 4 — sandbox for profile L (documentation only).** In `skills/build/references/authority.md`, a short section on running long autonomous sessions in Claude Code's sandbox or a devcontainer: the trade-off, and links to the sandboxing docs. keel installs nothing for it. Commit `docs(keel-harness): sandbox option for profile L`.
- [ ] **Task 5 — master plan:** tick the F3c consequence, deny, protect, CODEOWNERS and sandbox items, and mark the status row "◐ F3c-1 done". Commit `docs(keel-harness): F3c-1 done`.

## Acceptance

- Hook tests:
  - an Edit of `.agents/baselines/x.tsv` with no approval → `deny`, and the reason names the route;
  - with a current approval → no output;
  - `src/auth/x.ts` → `ask`;
  - `src/a.ts` → nothing;
  - malformed stdin → nothing, exit 0.
- `keel verify build` and `protect-missing` cover the new layer.
- The settings fragment cites the permission syntax source; CODEOWNERS is never written with an invented owner.
- `./tests/run.sh` exits 0; `validate --strict` passes; `shellcheck` is clean; the size limits hold.
- Known limit, written in `contracts/consequence.md`: Bash commands that write harness paths are not caught by this hook. `guard` in the gate, pre-commit and CI still catches loosenings.
