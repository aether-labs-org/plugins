---
name: build
description: >
  Installs an AI-agent harness in a repository: one-command bootstrap, an AGENTS.md index of
  at most 100 lines with pointer files, a fast gate of computational sensors (types, lint,
  affected tests, secret scanning) behind a single Makefile target, sensor wrappers that emit
  pass signal, guidance, scope, class and cost, and the PostToolUse hook that runs the gate.
  Infers from the repository and confirms before writing; installs one layer at a time and is
  resumable. Use when someone asks to set up or build a harness, configure their repository
  for AI agents, add agent guardrails or quality gates, or make a repo agent-friendly.
---

# Build

Writes nothing before the user confirms.

**Scope of this skill today: phases 1–2 only — bootstrap and guides.** Phases 3–4 (the fast gate,
sensor wrappers, the `PostToolUse` hook) are not implemented yet; they land in a later task. If
someone asks for the full harness — sensors, a gate, enforcement — say so plainly: install
bootstrap and guides now, and that the rest is not available yet.

## 1. Read the picture

If `assess` already ran in this session, reuse its report table (`references/rubric.md` axis
states, evidence paths, costs) — do not re-derive it silently. If it did not run, perform the same
read-only discovery yourself before proposing anything:

```bash
# Real scripts / targets
cat package.json 2>/dev/null | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('scripts',{}))" 2>/dev/null
grep -E "^[a-zA-Z_-]+:" Makefile 2>/dev/null | head -30
ls mvnw gradlew pnpm-lock.yaml yarn.lock package-lock.json uv.lock poetry.lock 2>/dev/null

# Docs and structure
ls docs/ 2>/dev/null; find docs/ -maxdepth 2 -name "*.md" 2>/dev/null | sort
ls src/ lib/ app/ packages/ services/ cmd/ internal/ 2>/dev/null

# Existing sensors / CI / context pointers
ls .eslintrc* eslint.config* .prettierrc* tsconfig.json ruff.toml mypy.ini pyrightconfig.json \
   .pre-commit-config.yaml .github/workflows/ checkstyle.xml spotbugs* .golangci.yml deny.toml 2>/dev/null
ls AGENTS.md .mcp.json .agents/state.yml 2>/dev/null
```

**Never invent a command.** Every command that ends up in the proposal, in `AGENTS.md`, or in
`.agents/state.yml` must be one you found in this discovery — never one you assume a stack
"usually" has. If `.agents/state.yml` already exists, read it first: a layer marked `installed`
is not re-proposed; a layer marked `not_installed` may be retried if new evidence appeared.

## 2. Phase 1 — bootstrap

The bootstrap layer is always exposed as a single, uniform entry point: **`make bootstrap`**
(spec §6 — `make`, not `just`; it is already on practically every machine, so it introduces no
new tool). This holds even when a single existing script already does everything: wrap it, do not
cite it bare, so every repository this kit touches shares one command, and so Phase 3's future
`make gate-fast` target has a `Makefile` to live in.

Look for the real, discovered install and (if applicable) build command(s) — a `package.json`
script, an `mvnw`/`gradlew` goal, a `pip install` + build step, whatever discovery actually found.
If a `Makefile` does not exist yet, propose creating one with just the `bootstrap` target. If one
exists, propose adding `bootstrap` to it without touching existing targets. The target body only
calls commands already found in discovery — it never introduces a new tool. State the exact
target body in the proposal so the user sees precisely what will be written, e.g.:

```make
bootstrap:
	npm install
```

If the stack has no build step at all (e.g. a type-only library that ships source as-is), the
target legitimately only installs — say so in the proposal rather than inventing a build line.

Apply the three-confidence rule (see `assess`'s `references/rubric.md`):
- **High** — a single install+build path is unambiguous: state the inference and ask for
  acceptance ("I see `pnpm install && pnpm build`; wrap that as `make bootstrap`?").
- **Low** — more than one plausible pairing (e.g. two workspaces, two package managers): ask a
  narrow question listing the options seen, never an open one.
- **None** — no install or build command can be found anywhere in discovery: declare that,
  do not install the bootstrap layer, and record the reason under `not_installed` in
  `.agents/state.yml`.

## 3. Phase 2 — guides

Fill `references/agents-md-template.md` with real, confirmed values only:

- Every command cell comes from discovery (Phase 1's bootstrap command, and any other real
  command found) — never a placeholder left unfilled, never an invented one.
- Any topic that needs more than one sentence becomes a `→ docs/X.md` pointer instead of inline
  prose.
- Omit sections for which nothing was found; do not pad with filler.
- Read `references/context-engineering.md` before writing the Context Engineering section — the
  file must stay a lean index, never a manual.
- The rendered file must be **100 lines** or fewer, header included.

Create only the `docs/` stub files the user confirmed in the proposal (Section 4). A stub is a
heading and a one-line TODO — never invented content, never a filled-in guess at what the doc
should eventually say.

## 4. The single confirmation gate

Present one structured proposal covering every file to be created or changed — the bootstrap
target (if any), the full `AGENTS.md` content, and the list of `docs/` stubs — organized so the
user can accept, drop, or amend items in one pass:

```
Proposed for this repository:

BOOTSTRAP
  make bootstrap → {{real install command}} && {{real build command}}
  (or: could not infer an install/build pair — bootstrap will not be installed)

GUIDES
  AGENTS.md ({{N}} lines) — preview below
  docs/ stubs to create: {{list, or "none"}}

Accept, drop an item, or tell me what's wrong. Before writing anything, I wait for your answer.
```

**Write nothing before the user accepts.** This is the one rule in this skill with no exception
and no flag. Apply the three-confidence rule per layer as in Section 2: high states the inference
and asks for acceptance; low asks a narrow question with the options seen; none declares the
layer cannot be installed and records why under `not_installed` — it is never installed on a
guess. The user's own request can itself grant that acceptance up front, in the same message that
asked for setup — a request that explicitly says not to pause for confirmation counts as accepting
every high- or low-confidence layer named in the proposal, so present the proposal and proceed
within that same reply rather than stopping to wait for a second message. A `none`-confidence
layer stays uninstalled regardless — no acceptance covers a layer that was never proposed.

## 5. Write `.agents/state.yml`

Once the user accepts, write the files, then record the outcome:

```yaml
model_baseline: claude-opus-5        # the model that installed the harness
installed_at: 2026-09-19             # ISO date, today
runner: Makefile                     # always Makefile once bootstrap is installed (spec §6)
gate:
  fast:
    ceiling_seconds: 5               # a sensor that blows the ceiling is not installed
layers:                              # installed | not_installed
  bootstrap: installed
  guides: installed
  fast_gate: not_installed
  contract: not_installed
not_installed:                       # layer -> the reason, in the kit's own words
  fitness_functions: "could not infer module boundaries"
sensors: []                          # filled by a later task
```

`fast_gate` and `contract` are always `not_installed` today — this skill does not implement them
yet (Section 0). Use the real reason for any Phase 1/2 layer that came out `not_installed` (e.g.
`bootstrap: "no install and build command could be found"`); never leave the reason generic.

Add `.agents/last-run.log` to the project's `.gitignore` if it is not already ignored;
`.agents/state.yml` itself is committed.

## 6. Self-verify

Before reporting success, check every one of these — all eleven, not a subset:

- [ ] `AGENTS.md` is **100 lines or fewer**.
- [ ] Deep content is replaced by `→ docs/X.md` pointers, not inlined.
- [ ] Every command in `AGENTS.md` is **real** (from discovery) — none invented.
- [ ] Every sensor mentioned has a **pass signal**.
- [ ] Any Shift-Left gate mentioned states what runs **per step** vs **before done**.
- [ ] Empty sections were removed; no placeholder filler (`{{...}}`) remains.
- [ ] The Context Engineering section is present (log format + first-error-is-root-cause, at
      minimum).
- [ ] `Last updated: YYYY-MM-DD` is set in the header.
- [ ] Nothing was written before the user confirmed in Section 4.
- [ ] Every command cited anywhere in `AGENTS.md` actually exists and runs in this repository —
      re-check each one by hand, not from memory of the proposal.
- [ ] `.agents/state.yml` parses as valid YAML.

If any check fails, fix it and re-verify before telling the user the layer is installed. Each
phase installed this way is **resumable**: a repository that already has `bootstrap: installed`
is not re-proposed on a later run, only the missing layers are.
