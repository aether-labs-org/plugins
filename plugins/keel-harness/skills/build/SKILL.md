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

**Scope of this skill today: phases 1–4** — bootstrap, guides, the fast gate and the output
contract — with the sensor wrappers implemented end to end for **TypeScript / Node only**. For the
other five languages in `references/sensors-by-language.md`, propose what that file documents, say
plainly that the wrappers for that stack are not written yet, and install only the layers that are.
Each phase installs independently and is resumable.

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
cite it bare, so every repository this kit touches shares one command, and so Phase 3's
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

Create only the `docs/` stub files the user confirmed in the proposal (Section 7). A stub is a
heading and a one-line TODO — never invented content, never a filled-in guess at what the doc
should eventually say.

## 4. Phase 3 — fast-gate sensors

Read `references/sensors-by-language.md` and `references/sensor-contract.md` before proposing
anything here. The first says which **tool** answers each of the four questions (types, style,
affected tests, secrets) in this repository's ecosystem; the second fixes the shape every wrapper
must emit and carries the templates to copy.

**Propose only the sensors whose tool the repository actually has.** A tool named in the table but
absent from `node_modules/`, the lockfile or the `PATH` is not a sensor this repo can run: either
leave it out, or install a wrapper that honestly reports `skip` (exit 2) with what is missing —
never one that passes silently. The same "never invent a command" rule from Section 1 applies to the
invocation: take it from `package.json` scripts, the existing `Makefile`, or the binary in
`node_modules/.bin`, never from memory of what the stack "usually" runs.

**Measure the cost before installing.** Run each candidate once, by hand, and record the wall
seconds:

```bash
time node_modules/.bin/tsc --noEmit -p tsconfig.json
```

A sensor that **alone** blows `gate.fast.ceiling_seconds` (from `.agents/state.yml`, default 5) is
**not installed**. Say which one, its measured seconds, and the ceiling it blew — in the proposal
and again under `not_installed` in the state file. This is the ceiling rule working, not a failure:
a Java compile or a full Next.js build is the usual case.

For every accepted sensor, write:

- `scripts/sensors/<id>.sh` — one file per sensor, following the wrapper protocol in
  `references/sensor-contract.md` §3 and adapted from the worked examples in §4–§6. **Copy the
  line-1 `printf` verbatim** (`id`, then `class`, then `status`, then `summary` — in that order,
  never the wrapper's own elapsed time) **and make the wrapper actually read `$SCOPE`** rather than
  printing a fixed scope string; only the tool invocation, its output parsing and the guidance text
  are genuinely repository-specific. `chmod +x` it.
- `scripts/gate.sh` — the runner, from `references/sensor-contract.md` §7, **copied byte-for-byte,
  not rewritten from memory.** It reads the sensor list from `.agents/state.yml`, so adding or
  removing a sensor later is a state edit, not a script edit. A `gate.sh` that runs the sensors but
  skips their per-sensor millisecond timing, the 40-line truncation, or the `✓/✗/○` report shape is
  a defect even when `make gate-fast` still exits with the right code.
- the `gate-fast` target in the `Makefile`, added beside `bootstrap` without touching it:

  ```make
  gate-fast:
  	@bash scripts/gate.sh
  ```

Everything written here is plain `bash` that lives in the user's repository and must run with this
plugin absent — no `${CLAUDE_*}` variable, no path into the plugin directory, no `claude`
invocation, no network call. Verify that by running `make gate-fast` before reporting success.

## 5. Phase 4 — the output contract

Every wrapper emits the **seven fields** of `references/sensor-contract.md` §1 — pass signal,
guidance, scope, cost, bounded verbosity, class, ceiling. Three of them are where wrappers usually
go wrong:

- **class** — `security` and `correctness` fail on the first problem and are **never** given a
  snapshot or a raisable threshold. Only `heuristic` sensors ratchet, and the ratchet must be a real
  comparison against `snapshot:` in `.agents/state.yml` (`fail` only when the count rose above it,
  per `sensor-contract.md` §6) — a `heuristic` wrapper that reports `fail` on the tool's raw non-zero
  exit, without reading and comparing the snapshot, has no ratchet at all, whatever its `guidance:`
  text claims. Putting a ratchet on a secret scanner, or forgetting to implement the one a heuristic
  sensor is supposed to have, are the two mistakes the class column exists to prevent.
- **bounded verbosity** — cap the detail lines inside the wrapper (`head -5`), indented by two
  spaces. The full tool output belongs in `.agents/last-run.log`, which `gate.sh` writes.
- **guidance** — on `fail`, a block starting `guidance: ` that says what to do **in this
  repository's own terms**: which file, which decision, what to do next. **Never a restatement of
  the tool's error.** "3 type errors found" is the summary; guidance is "fix the first error and
  re-run, the rest cascade from it; do not widen the type to `any`". Write it so that an agent that
  sees nothing but the gate's output can act on it correctly and knows which of the plausible fixes
  is the wrong one — telling it not to edit the test to match a changed number is worth more than
  telling it the test failed.

## 6. The hook

The gate is wired to fire after each edit through a **`PostToolUse`** hook in the repository's own
`.claude/settings.json`. `PostToolUse` fires **after** the tool has already run, so it **blocks
nothing** — it reports. That is deliberate (spec §9): v0.1 installs no blocking hook anywhere.

Show the user this exact block before writing it:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "cd \"${CLAUDE_PROJECT_DIR}\" && make gate-fast"
          }
        ]
      }
    ]
  }
}
```

**`${CLAUDE_PROJECT_DIR}` is copied literally, not resolved.** It is a real environment variable
Claude Code sets when it runs the hook, not a placeholder standing in for this repository's path —
do **not** substitute it with the repository's actual absolute path (e.g.
`cd "/home/user/project"`). A hardcoded path works on this machine today and breaks the moment the
repository is cloned, moved, or run in CI under a different path; `${CLAUDE_PROJECT_DIR}` is what
keeps the hook portable. Write the `command` string exactly as shown above, backslash-escaped
quotes included.

**Merge; never overwrite.** If `.claude/settings.json` already exists, read it, add the
`PostToolUse` entry to the existing `hooks` object (appending to the array if one is already there),
and keep every other key byte-for-byte. If it does not exist, create it with exactly the block
above. Write it **only after the user accepts** — the hook is the one item most worth declining
independently, so it is a separate line in the proposal.

## 7. The single confirmation gate

Present one structured proposal covering every file to be created or changed — the bootstrap
target (if any), the full `AGENTS.md` content, the list of `docs/` stubs, every sensor with its
class and measured cost, and the hook — organized so the user can accept, drop, or amend items in
one pass:

```
Proposed for this repository:

BOOTSTRAP
  make bootstrap → {{real install command}} && {{real build command}}
  (or: could not infer an install/build pair — bootstrap will not be installed)

GUIDES
  AGENTS.md ({{N}} lines) — preview below
  docs/ stubs to create: {{list, or "none"}}

FAST GATE (ceiling {{N}}s)
  scripts/sensors/typecheck.sh  [correctness]  {{tool}}   measured {{N}}s
  scripts/sensors/lint.sh       [heuristic]    {{tool}}   measured {{N}}s, snapshot {{N}} problems
  scripts/sensors/tests.sh      [correctness]  {{tool}}   measured {{N}}s
  scripts/sensors/secrets.sh    [security]     {{tool}}   measured {{N}}s (skips if not installed)
  left out: {{sensor}} — measured {{N}}s, over the {{N}}s ceiling
  scripts/gate.sh + `make gate-fast`

HOOK
  .claude/settings.json — PostToolUse on Edit|Write|MultiEdit runs `make gate-fast`
  (fires after the edit; it reports, it does not block)

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

## 8. Write `.agents/state.yml`

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
  fast_gate: installed
  contract: installed
not_installed:                       # layer -> the reason, in the kit's own words
  fitness_functions: "could not infer module boundaries"
sensors:                             # one entry per installed sensor, in gate run order
  - id: typecheck
    class: correctness               # no snapshot: correctness never ratchets
  - id: lint
    class: heuristic
    snapshot: { problems: 34, measured_at: 2026-09-19 }
    review_by: 2027-03-19            # install day + six months
  - id: tests
    class: correctness
  - id: secrets
    class: security                  # no snapshot: security never ratchets
```

`scripts/gate.sh` reads `sensors:` to decide what to run, so this list is the gate's real
definition — an id here with no `scripts/sensors/<id>.sh` beside it is skipped silently, and a
wrapper not listed here never runs. Keep them in step.

**Only `heuristic` sensors get `snapshot:` and `review_by:`** — `review_by` is the install date
plus six months, the ratchet's expiry. A `security` or `correctness` sensor gets neither; giving one
a snapshot is a defect, not a nicety (`references/sensor-contract.md` §2).

Use the real reason for any layer that came out `not_installed` — a Phase 1/2 layer
(`bootstrap: "no install and build command could be found"`), a sensor left out by the ceiling
(`fast_gate: "compile measured 21s, over the 5s ceiling"`), or a stack whose wrappers this version
does not implement (`fast_gate: "only TypeScript wrappers exist in v0.1"`). Never leave the reason
generic.

Add `.agents/last-run.log` to the project's `.gitignore` if it is not already ignored;
`.agents/state.yml` itself is committed.

## 9. Self-verify

Before reporting success, check every one of these — the whole list, not a subset:

- [ ] `AGENTS.md` is **100 lines or fewer**.
- [ ] Deep content is replaced by `→ docs/X.md` pointers, not inlined.
- [ ] Every command in `AGENTS.md` is **real** (from discovery) — none invented.
- [ ] Every sensor mentioned has a **pass signal**.
- [ ] Any Shift-Left gate mentioned states what runs **per step** vs **before done**.
- [ ] Empty sections were removed; no placeholder filler (`{{...}}`) remains.
- [ ] The Context Engineering section is present (log format + first-error-is-root-cause, at
      minimum).
- [ ] `Last updated: YYYY-MM-DD` is set in the header.
- [ ] Nothing was written before the user confirmed in Section 7.
- [ ] Every command cited anywhere in `AGENTS.md` actually exists and runs in this repository —
      re-check each one by hand, not from memory of the proposal.
- [ ] `.agents/state.yml` parses as valid YAML.
- [ ] `make gate-fast` was **actually run** and its output read — not assumed.
- [ ] Every sensor's line 1 is exactly `id<TAB>class<TAB>status<TAB>summary`, **in that order** —
      check by running `cut -f1` on it and confirming it prints the sensor's own id (`typecheck`,
      `lint`, ...), not `pass`/`fail`/`skip`, and that `cut -f3` prints the status, not the class or
      the elapsed time. Exit code matches status (0 pass / 1 fail / 2 skip). Check by running each
      wrapper once on its own.
- [ ] Every wrapper reads `$SCOPE` (never a hardcoded scope string) and `scripts/gate.sh` is the
      **unmodified** copy from `references/sensor-contract.md` §7 — per-sensor millisecond timing,
      40-line truncation, the terminal-conditional `✓/✗/○` marks, and the exact verdict line. Check
      it concretely, not by eye: `bash scripts/gate.sh 2>&1 | grep -qE 'gate: fast - (PASSED|FAILED)
      \([0-9]+ of [0-9]+\) \| ceiling [0-9]+s, spent .* \| model cost: US\$0\.00'`. A gate.sh that
      was rewritten from a simpler idea of what a runner should do, instead of copied, is a defect
      even when it happens to exit with the right code.
- [ ] The `lint` (or any other `heuristic`) wrapper's `pass`/`fail` comes from comparing the current
      count to `snapshot:` in `.agents/state.yml`, not from the linter's raw exit code — confirm by
      reading the wrapper's source, not just by running it once. If the repo genuinely has zero
      problems today this distinction cannot be observed by running the gate alone.
- [ ] Every installed sensor appears in `sensors:` in `.agents/state.yml`, and only `heuristic`
      ones carry `snapshot:` and `review_by:`.
- [ ] A sensor that blew the ceiling is named, with its measured seconds, in `not_installed`.
- [ ] `make gate-fast` runs with the plugin absent — no `${CLAUDE_*}`, no plugin path, no `claude`
      call anywhere in `scripts/`.
- [ ] `.claude/settings.json` parses as JSON, contains the `PostToolUse` block, kept every key it
      already had, and contains **no** blocking hook.
- [ ] The hook's `command` contains the literal string `${CLAUDE_PROJECT_DIR}` — not this
      repository's actual absolute path. Grep for it: `grep -q '\${CLAUDE_PROJECT_DIR}'
      .claude/settings.json`.

If any check fails, fix it and re-verify before telling the user the layer is installed. Each
phase installed this way is **resumable**: a repository that already has `bootstrap: installed`
is not re-proposed on a later run, only the missing layers are.
