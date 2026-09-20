# keel-harness — Design Spec (v0.1)

**Date:** 2026-09-19
**Status:** approved for planning
**Repository:** `aether-labs-org/plugins` (monorepo; marketplace `aether-labs`)
**Source material:** the *Keel Harness Kit* study (`docs/references/` in `aether-labs-org/skills`) and
its executable cut, the *Keel Harness Plugin* build note.

---

## 1. What this is

A Claude Code plugin that installs and maintains an **AI-agent harness** in a repository: a
one-command bootstrap, a short `AGENTS.md` index, a fast gate of deterministic sensors, and an
output contract that turns each sensor's exit code into guidance an agent can act on.

**The rule that defines v0.1: it informs, it does not block.** The gate runs, reports failures and
returns guidance. No action is barred, no commit is refused. The only hook installed is
`PostToolUse`, which fires *after* the tool already ran and therefore cannot block by construction.

This makes false positives cheap: a wrong signal costs one message, not blocked work. Blocking —
`PreToolUse`, `pre-commit`, sandbox policy — waits for real usage showing which rules deserve that
power.

## 2. Scope

The study describes twelve phases (0–11). v0.1 cuts at **phase 4**, the point where the harness
starts being worth its cost: phases 1–3 install checks, phase 4 is what makes each check speak.

| Study phase | v0.1 | Reason |
| --- | --- | --- |
| 0 · Diagnosis | **in** | Rewritten as a deterministic internal scan; no third-party tool |
| 1 · One-command bootstrap | **in** | Without it every later check reports on a build that may not run |
| 2 · Minimal guides | **in** | `AGENTS.md` ≤ 100 lines, pointer files, `docs/` |
| 3 · Fast-gate sensors + the hook that fires them | **in** | Types, style, affected tests, secret scanning, plus `PostToolUse` |
| 4 · Output contract | **in** | **The core.** Without it phase 3 is noise |
| 5 · Mutation testing | out | Expensive and slow; no measured budget |
| 6 · Fitness functions | out | Depends on layer inference, the main open question |
| 7 · pre-commit and blocking | out | v0.1 does not block |
| 8 · Sandbox and approval policy | out | Security config written by a young tool is needless risk |
| 9 · CI | out | The generated `Makefile` already gives parity to whoever wants it |
| 10 · Behaviour harness | out | Least settled part of the field |
| 11 · Episodic memory | out | Needs accumulated sessions to distil |

### Which existence tests apply

Of the seven harness existence tests in §11 of the study, four apply to v0.1 and three do not, by
design — recorded here so nobody tries to make v0.1 pass all seven.

| Test | v0.1 | Form that counts here |
| --- | --- | --- |
| Bootstrap | applies | Clean clone, `make bootstrap`, green build, wall-clock timed |
| Self-correction | applies | The done criterion of phase 5 below |
| Portability | applies | Uninstall the plugin; `make gate-fast` still runs identically |
| Removal | applies | Disable one heuristic sensor and see whether anything gets worse |
| Blocking | no | v0.1 blocks nothing. Returns in v0.2 with `PreToolUse` |
| Context reset | no | Handoff is phase 11 |
| Documentation freshness | no | Requires comparing docs against code, which `doctor` v0.1 does not do |

## 3. Repository topology

One monorepo holds the marketplace and every Aether Labs plugin.

```
aether-labs-org/plugins
├── .claude-plugin/marketplace.json      # marketplace name: aether-labs
├── plugins/
│   └── keel-harness/
│       ├── .claude-plugin/plugin.json
│       ├── skills/
│       │   ├── assess/
│       │   │   ├── SKILL.md
│       │   │   └── references/{rubric.md, harness-model.md}
│       │   ├── build/
│       │   │   ├── SKILL.md
│       │   │   └── references/{agents-md-template.md, sensors-by-language.md,
│       │   │                  sensor-contract.md, context-engineering.md}
│       │   └── doctor/SKILL.md
│       ├── evals/
│       │   ├── assess-mature-repo/{prompt.md, graders/*.md, scaffold.sh}
│       │   ├── build-<lang>/          # one per supported language
│       │   ├── gate-catches-defect/
│       │   └── should-not-trigger/
│       └── README.md
├── docs/specs/
├── .github/workflows/validate.yml
├── README.md
└── LICENSE                              # Apache-2.0
```

Install path for users:

```
/plugin marketplace add aether-labs-org/plugins
/plugin install keel-harness@aether-labs
```

Skills are namespaced by plugin name: `/keel-harness:assess`, `/keel-harness:build`,
`/keel-harness:doctor`.

**Monorepo constraint:** an installed plugin is copied into a cache directory and cannot reference
paths outside itself (`../shared/`). Every plugin in this repo is self-contained; shared reference
material is duplicated, not linked.

### Plugin layout rules

| Item | Rule |
| --- | --- |
| Manifest | `.claude-plugin/plugin.json`. Only `name` is required; `description`, `version`, `author`, `license`, `repository`, `keywords` are optional |
| Directory placement | Component directories live at the **plugin root**. Only the two `.json` files live in `.claude-plugin/` |
| Skills | `skills/<name>/SKILL.md`; the folder name becomes the skill name |
| No `commands/` | Legacy format; new plugins use `skills/` |
| No `hooks/`, `.mcp.json`, `bin/` | Security posture, §9 |
| Path variables | `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PLUGIN_DATA}`, `${CLAUDE_PROJECT_DIR}` |
| Versioning | With `version` set, users only get an update when the field increases |

Local development: `claude --plugin-dir ./plugins/keel-harness` loads the plugin without installing
it; `/reload-plugins` picks up changes without restarting the session.

## 4. The three skills

The `description` is not documentation — it is the trigger mechanism, and it is what the eval's Δ
measures. All skill content, including bodies, is written in English.

**`skills/assess/SKILL.md`**

```yaml
name: assess
description: >
  Diagnoses how ready a repository is for AI coding agents. Scans the repo against a
  six-axis rubric — bootstrap, guides, fast sensors, slow sensors, enforcement, context —
  reporting each axis as absent, partial or present with the file that proves it, plus the
  cost of closing each gap in setup minutes and seconds added to the gate. Writes nothing.
  Use when someone asks whether their repository is ready for AI agents, what is missing to
  work with coding agents, for an agent-readiness assessment or a harness diagnosis — and
  always before the build skill.
```

**`skills/build/SKILL.md`**

```yaml
name: build
description: >
  Installs an AI-agent harness in a repository: one-command bootstrap, an AGENTS.md index of
  at most 100 lines with pointer files, a fast gate of computational sensors (types, lint,
  affected tests, secret scanning) behind a single Makefile target, sensor wrappers that emit
  pass signal, guidance, scope, class and cost, and the PostToolUse hook that runs the gate.
  Infers from the repository and confirms before writing; installs one layer at a time and is
  resumable. Use when someone asks to set up or build a harness, configure their repository
  for AI agents, add agent guardrails or quality gates, or make a repo agent-friendly.
```

**`skills/doctor/SKILL.md`**

```yaml
name: doctor
description: >
  Checks whether an installed harness has drifted from the repository it guards: AGENTS.md
  over 100 lines, commands cited there that no longer exist, sensors declared in the Makefile
  whose tool is missing or fails to run, and a model_baseline that has fallen behind. Reports
  and proposes; writes nothing. Use when someone asks whether their harness is out of date,
  stale or still valid, or wants a harness health check.
```

### Read/write boundaries

| Skill | Reads | Writes |
| --- | --- | --- |
| `assess` | Stack markers, real scripts, configured sensors, `docs/`, directory structure | **Nothing.** This is what makes diagnosis cheap and risk-free |
| `build` | The `assess` picture, `.agents/state.yml` if present, the user's confirmations | `AGENTS.md`, pointer docs, `docs/` stubs, `Makefile`, `scripts/sensors/`, `.agents/state.yml`, the gate hook in `.claude/settings.json` |
| `doctor` | `.agents/state.yml` and current project state | **Nothing.** Reports and proposes; fixes go through `build` |

### Absorbing `agents-md-architect`

The existing skill is absorbed, not discarded. It is phases 0+2 already implemented.

| Existing part | Becomes |
| --- | --- |
| Steps 1–2: stack detection, discovery of **real** commands ("never invent commands"), harnessability, 2×2 grid with gaps | The engine of `assess` |
| Steps 3–4: structured proposal, single confirmation gate, writing `AGENTS.md` and `docs/` stubs | `build` phases 1–2 |
| Step 5: eight-check self-verify | The base of `doctor` |
| `references/harness-model.md`, `context-engineering.md` | Copied as-is |
| `references/agents-md-template.md` | Copied, ceiling adjusted 120 → **100 lines** |
| `references/harness-cheatsheet.md` | Absorbed and widened into `sensors-by-language.md` |
| `references/multi-agent-orchestration.md` | **Not carried over.** Orchestration is outside the installed harness |
| `evals/evals.json` | **Not carried over as a file** (skill-creator format, distinct from `claude plugin eval`); source material for the cases in §8 |

It loses its standalone `description`: two skills competing for "configure my repo for agents" is a
known failure mode. It is currently untracked in `aether-labs-org/skills` and was never published,
so absorbing it costs nothing.

## 5. The rubric, and the right to say "I don't know"

Phase 0 of the study depended on two open agent-readiness tools that were never executed — the kit's
only external dependency, sitting in the first interaction. It is dropped. In its place: a short
rubric, versioned in `references/rubric.md`, with **three states per axis** and mandatory evidence.

| Axis | Present | Partial | Absent |
| --- | --- | --- | --- |
| **Bootstrap** | Lockfile, and a single target that installs and builds — and it runs | Lockfile without a single target, or a target that exists and fails | Neither |
| **Guides** | `AGENTS.md` at root ≤ 100 lines, and `docs/` with content | One of the two, or `AGENTS.md` over the ceiling | Neither |
| **Fast sensors** | Types and style configured *and* runnable | Configured, but one does not run | No configuration |
| **Slow sensors** | A suite that runs, and coverage configuration | Suite without coverage, or a suite that fails | No suite |
| **Enforcement** | `.pre-commit-config.yaml` and a CI workflow running the same commands | One of the two, or divergent local/CI commands | Neither |
| **Context** | Pointers to the other tools, and `.mcp.json` declared (even empty) | Missing pointers, or connectors without declaration | Nothing |

**There is no aggregate score, and that is a decision.** A score suggests the ruler measures quality;
it measures presence of evidence. Summing axes would require weights no source justifies.

### Two cost units, and only two

- **setup minutes** — how long `build` takes to close that gap, confirmations included;
- **seconds added to the gate** — how much that sensor adds to every edit, measured by running the
  tool once on the real repository, never estimated.

When the tool is not installed and cannot be measured, the cost is reported as **not measured** —
never as a guess.

### The third inference outcome

The study's rule — "never an open question, always a confirmation of an inference" — had only two
states and therefore no exit when the inference failed. It gets three:

| Confidence | The kit does | Example |
| --- | --- | --- |
| **High** — consistent evidence | States the inference and asks for acceptance | "I see `api/`, `domain/` and `db/`, and `domain/` never imports `db/`. Is that the rule?" |
| **Low** — partial or contradictory | Narrow question with the options seen — never an open one | "I found two plausible layerings. Is it (a) or (b)? Or neither?" |
| **None** | Declares it could not infer, **does not install the layer**, records the reason in `.agents/state.yml` | "I could not identify module boundaries here. Without them a fitness function would be an invented rule — leaving it out." |

The third state prevents the most expensive failure mode of this category of tool: installing a rule
the kit invented and presenting it as the project's. A layer left out costs one line of explanation;
an invented rule costs trust in every other rule.

## 6. Sensor contract, state, and the command file

### The seven fields

Five come from the study — pass signal, guidance, scope, cost, bounded verbosity. Two are new, and
their absence had a concrete consequence: the ratchet ("only don't get worse") and the raisable
threshold would otherwise apply to a leaked credential too.

| Class | v0.1 sensors | Ratchet? | Raisable threshold? |
| --- | --- | --- | --- |
| **security** | secret scanning | never | never |
| **correctness** | types, affected tests | never | never |
| **heuristic** | style, size, complexity | yes | yes |

The seventh field is the **ceiling**. The fast gate declares a limit in seconds; a sensor that blows
it is not installed, and the kit says what was left out and why. The money ceiling for v0.1 is
**zero**, and that is not a target: no v0.1 sensor calls a language model.

The ratchet gets an expiry: each heuristic sensor records the install-day snapshot **and a review
date**, six months out by default. Without an expiry, "don't get worse" freezes a bad state forever
and the ratchet stops being a ratchet.

### Where state lives

```yaml
# .agents/state.yml — committed
model_baseline: claude-opus-5
installed_at: 2026-09-19
runner: Makefile

layers:
  bootstrap: installed
  guides: installed
  fast_gate: installed
  contract: installed

not_installed:
  fitness_functions: "could not infer module boundaries"

sensors:
  - id: lint
    class: heuristic
    snapshot: { problems: 34, measured_at: 2026-09-19 }
    review_by: 2027-03-19
  - id: secrets
    class: security      # no snapshot: security has no ratchet

# .agents/last-run.log — gitignored
```

`.agents/` is this project's convention, **not** a ratified part of the `AGENTS.md` standard, which
defines a single file (root `AGENTS.md`, plus nested ones in a monorepo) and no state or config
directory. It was chosen for being vendor-neutral — unlike `.claude/` — and for not polluting
`docs/`, which the study reserves for long-lived truth read on demand. If the ecosystem standardises
another name, the change costs a rename and one more check in `doctor`.

### `make`, not `just`

The kit's first promise is to install no new tool. `just` is a new install; `make` is already on
practically every Unix machine and every CI runner. `just` has the better syntax, and not by enough
to cost the whole proposal a prerequisite.

v0.1 writes **two targets**: `make bootstrap` and `make gate-fast`. `gate-slow` arrives in v0.2.

```
$ make gate-fast

✓ typecheck   [correctness]  Found 0 errors in 12 files.          312ms
✓ secrets     [security]     No leaks found in 12 staged files.   118ms
✓ lint        [heuristic]    0 problems. same as snapshot (34).   840ms
✗ tests       [correctness]  3 passed, 1 failed.                  2.1s
   └ src/ledger/posting.test.ts:41 — expected 1200, received 1180
     guidance: rounding changed in applyFee(). If the change was intentional,
     update the test and record a new ADR in docs/decisions/ — never edit an
     accepted ADR. If it was not, the bug is in the calculation.

scope: 12 files changed since last commit
gate: fast — FAILED (1 of 4) · ceiling 5s, spent 3.4s · model cost: US$0.00
output truncated at 40 lines · full log in .agents/last-run.log
```

## 7. Languages

v0.1 covers six languages. This is a scope decision with a known cost, stated here: **six fixture scaffolds and six sets
of eval cases** instead of one.

Supporting a language means three things: `build` knows which sensors to propose, knows how to write
the wrapper that translates the tool's output into the §6 contract, and there is a fixture repository
proving each sensor catches what it should.

| Language | Types | Style | Affected tests | Secrets |
| --- | --- | --- | --- | --- |
| TypeScript / Node | `tsc` strict | ESLint or Biome | Vitest or Jest | GitLeaks |
| Next.js / React | `tsc` strict | ESLint | Vitest or Jest | GitLeaks |
| Python | mypy | ruff | pytest | GitLeaks |
| Go | `go vet` | staticcheck | `go test` | GitLeaks |
| Java | compiler | Checkstyle | JUnit | GitLeaks |
| Terraform | `validate` | `fmt -check`, tflint | — *no unit tests* | GitLeaks |

**The table names tools, never commands.** The exact command comes from discovery in the repository —
the "never invent commands" rule. Writing `npx vitest related` here would be inventing the invocation
of a project nobody looked at.

Two consequences of the six-language choice: **Terraform has no test sensor**, so its fast gate has
three sensors, not four. And **in Java compilation usually exceeds the seconds ceiling** — in which
case the ceiling rule fires and the sensor stays out of the fast gate, which is the mechanism working,
not an exception.

### Planted defects, per language

The study lists seven; three exercise sensors v0.1 does not install (fitness functions, flakiness,
mutation). Four remain, plus the bootstrap case — this is what each fixture repository must contain.

| Planted defect | Exercises | Applies to |
| --- | --- | --- |
| An API key written into the code | secret scanning | all six |
| A module escaping strict typing | type check | all six |
| A function over the complexity limit | the raisable threshold and the ratchet | all six |
| A test failing from a behaviour change | affected tests, and the guidance | five — not Terraform |
| A dependency with no lockfile, or a build that fails from a clean clone | all of phase 1 | all six |

Fixtures are **generated by each case's `scaffold.sh`**, not committed: six languages without six
repositories in git. Who plants the defects matters — if the same author writes the kit and the
fixtures, the test is self-confirmation. Defect definitions are reviewed independently before a
language is considered done.

## 8. Validation

Two verifications with two costs:

| Command | Verifies | Costs |
| --- | --- | --- |
| `claude plugin validate .` | Syntax and schema of the plugin files. `--strict` treats warnings as errors | Nothing |
| `claude plugin eval .` | Behaviour: whether the skill is chosen from a natural sentence and whether the result passes the graders | Real model calls, on the account that runs it |

`claude plugin eval` runs each case three times **with** the plugin loaded and three times **with no
plugin** (adjustable via `--runs`), reporting `WITH`, `W/OUT` and `Δ`. A case scoring 1.0 in both arms
was not made to pass by the plugin. **Δ is the efficacy metric**, applied at the layer where
measurement is possible. Requires Claude Code v2.1.269 or newer.

Four grader types read the transcript and the files and cost nothing — `regex`, `tool_used`,
`tool_order`, `file_exists`. Two call a judge model and cost money — `llm`, `baseline`. For a tool
that generates files this is convenient: nearly everything worth checking is written file content.

### The Δ trap

A `tool_used` grader whose `tool` is `Skill` is **excluded from the score in both arms** — it would
never pass without the plugin and would inflate Δ. It appears as an indicator, not a grade.

The consequence is easy to miss: if a case's only relevant grader is "the skill fired", its Δ is zero
by construction. And a Claude without the plugin also produces a reasonable portrait of a repository
and also writes no files — so the `assess` case would tie in both arms.

**The grader that produces real Δ** must demand something only the rubric delivers. For `assess`: a
`regex` over the response requiring, simultaneously, the six axis names, one of the three states per
axis, and at least one file path as evidence. A model without the plugin does not produce that format.

### Cases and graders

| Case | Proves | Graders |
| --- | --- | --- |
| `assess-mature-repo` | The rubric is applied, and nothing is written | `regex` for six axes + state + evidence *(this is what scores)*; negative `file_exists`; `tool_used` on the skill *(indicator)* |
| `build-<language>` (one per language) | Writes `AGENTS.md` ≤ 100 lines, a `Makefile` with both targets, and `.agents/state.yml` | `regex` over each generated file; `file_exists` on all three |
| `gate-catches-defect` | The installed sensor detects what was planted | Prompt runs `make gate-fast` and writes output to a file; `regex` over that file; `tool_used` with `input_match` on the command |
| `should-not-trigger` | The skill is not invoked when nobody asked | `tool_used` with `min: 0`, `max: 0`, `arm: both` |

### Running `build` without a human

Each eval run is an isolated non-interactive session, and `build` writes nothing before the person
confirms. **The fix lives in the case prompt, not in the skill:** the case text explicitly
pre-authorises — "set up the harness here and install everything you recommend, without asking me".
The confirmation gate stays the skill's single rule; the user waives it in their own sentence. No
special mode, no back door in the code.

### In v0.1, and after

- **In:** the four case types above, run manually, plus `claude plugin validate --strict` in CI on
  every PR. While tuning graders, `--ablation none` runs only the plugin arm and halves the cost.
- **Out:** the noise-floor study (five runs of the unchanged suite to learn Δ's dispersion) and a Δ
  regression gate in CI. Both are recorded for v0.2.
- **No absolute Δ threshold is invented.** Two rules apply from the first run: a case with Δ ≤ 0 in
  three consecutive runs is rewritten or deleted (either the case is badly built or the plugin does
  not contribute there); and once a noise floor exists, CI fails when a case's Δ drops more than that
  floor against the last recorded value on the main branch — the plugin measured against itself.

`context.scaffold_script` runs **as you, outside the agent sandbox**, and only with `--scaffold`.
Use it only on suites you wrote yourself.

## 9. Security posture

An installed plugin is third-party code running with the permissions of whoever installed it. v0.1
takes the most conservative posture available, by choice.

| Surface | v0.1 | Why |
| --- | --- | --- |
| `hooks/hooks.json` in the plugin | **Absent** | The plugin installs no hook of its own. The gate hook is written into the user's repository, under confirmation, versioned there where they read and review it |
| `.mcp.json` in the plugin | **Absent** | No external connector. The plugin talks to nothing off the machine |
| `bin/` | **Absent** | Executables there enter the Bash `PATH` while the plugin is active |
| What the plugin writes | Readable text only | Config and Markdown. Nothing binary, nothing the person cannot read before accepting |
| Distribution | Own marketplace, controlled repository | `claude plugin validate` before publishing; no third-party store by default |

A plugin that installs no hooks and blocks nothing has little that can be subverted. When blocking
arrives in v0.2, the hooks the plugin *writes* deserve review with production-code rigour — that has
to be settled before the first `PreToolUse` is written.

## 10. Implementation phases

Each phase is one PR with an observable done criterion. This is the order for building the **tool**,
which differs from the order in which the tool installs a harness.

| # | Deliverable | Done when |
| --- | --- | --- |
| 0 | Repo `plugins` scaffolded: `marketplace.json`, `LICENSE` (Apache-2.0), `README.md`, `validate.yml` | `/plugin marketplace add ./` resolves the marketplace locally |
| 1 | Skeleton: `plugin.json` and the three `SKILL.md` files with final descriptions and minimal bodies | `claude plugin validate .` passes; `claude --plugin-dir` lists the three skills in `/help` |
| 2 | `assess` complete: rubric of six axes × three states, both cost units, three-state inference | Runs on a mature public TypeScript repo, classifies all six axes citing an evidence file for each, and `git status` stays clean afterwards |
| 3 | Minimal eval suite: `assess-mature-repo` and `should-not-trigger` | `claude plugin eval .` runs to completion and the `assess` case shows positive Δ on the rubric grader — not on the skill-invoked grader, which does not score |
| 4 | `build` phases 1–2: bootstrap and minimal guides | On a repo with no `AGENTS.md`, produces a file ≤ 100 lines in which every cited command really exists, and writes `.agents/state.yml` with the installed layers |
| 5 | `build` phases 3–4, TypeScript only: `Makefile`, `scripts/sensors/` wrappers with the seven fields, `PostToolUse` hook in `.claude/settings.json` | A planted error is fixed by the agent *guided only by the sensor message*, with no human help |
| 6 | The other five languages — Python, Go, Java, Next.js, Terraform — one PR each, each with its own scaffold and eval case | Per language: the four or five planted defects exist, and each is caught by its sensor and by no other |
| 7 | `doctor`: the four checks that work without history | On a repo where `build` ran, breaking each of the four conditions on purpose produces exactly one warning each — not zero, not two |
| 8 | Release: `README.md`, marketplace entry, versioning decision | `claude plugin validate . --strict` passes with no warnings, and installing from the marketplace works on a clean machine |

### What `doctor` checks in v0.1

Most drift detection described in the study depends on history — "a sensor that never fails" only
exists after weeks of runs. v0.1 keeps the four checks that work in a single look:

- `AGENTS.md` over 100 lines;
- a command cited in `AGENTS.md` that no longer exists in the project;
- a sensor declared in the `Makefile` whose tool is not installed or does not run;
- `model_baseline` in `.agents/state.yml` behind by one version or more.

The rest — capture rate per sensor, documents older than the code — are recorded as what v0.2 gains
once there is history to read.

## 11. Out of scope for v0.1

- **Any blocking** — `PreToolUse`, `pre-commit`, sandbox, approval policy.
- **Inferential sensors** — LLM-as-judge, modularity review, evaluator subagent. Keeps money cost at zero.
- **Mutation testing and fitness functions** — dependent on a measured budget and on layer inference.
- **Handoff and episodic memory** — need accumulated sessions to distil.
- **`make gate-slow` and CI generation** — the `Makefile` already gives parity to whoever wants it.

## 12. Open questions

| Question | What answers it |
| --- | --- |
| The name `keel-harness` collides with an existing npm package of the same category (`keel-harness`, "local-first governed agent harness") and with `keel-hq/keel` | **Risk accepted by the owner on 2026-09-19.** Revisit before any wider promotion |
| Does layer inference get it right often enough to be worth a confirmation? | The `assess-mature-repo` case. If it is always wrong, the third state ("I don't know") becomes the common path and v0.1 stays useful without fitness functions |
| How much Δ is "good enough" to ship? | No absolute number is invented; see §8 |
| What does maintaining a harness cost? | Measured on our own repository, n=1: the unit is a *touch* — commits touching `Makefile`, `scripts/sensors/`, `AGENTS.md`, `.agents/` — read straight from git. Worth instrumenting: a field per sensor in `.agents/state.yml` recording every threshold raise or rule suppression, which is what separates harness maintenance from code maintenance. Publish as *touches per month per sensor, n=1, six months* |
| Will `.agents/` become an ecosystem convention? | Today it is our choice; see §6 |

## 13. Decisions that changed from the source build note

| Change | Reason |
| --- | --- |
| Name `keel` → `keel-harness` | Owner's decision on 2026-09-19, collision risk accepted |
| Single-plugin repo → monorepo `aether-labs-org/plugins` with marketplace `aether-labs` | The repo hosts this plugin and future ones |
| Skill bodies allowed in Portuguese → **everything in English** | Project rule: all code, docs and naming in English |
| `.agents/state.yml` keys in Portuguese → English keys | Same rule |
| Fixture repositories committed → generated by `scaffold.sh` | Six languages without six repos in git |
| Full §8 validation → minimal suite in v0.1 | Noise floor and Δ regression gate cost recurring model calls; deferred to v0.2 |

## 14. Sources

Claude Code official documentation — *Create plugins*, *Plugins reference*, *Plugin marketplaces*,
*Test plugins with evals* — consulted 2026-09-19. Conceptual model, parts catalogue and criteria: the
*Keel Harness Kit* study.
