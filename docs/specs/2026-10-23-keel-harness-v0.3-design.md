# keel-harness — Design Spec (v0.3)

**Date:** 2026-10-23
**Status:** proposed — not implemented. The incremental plan is
`docs/plans/2026-10-23-keel-harness-v0.3-plan.md`.
**Supersedes:** parts of `2026-10-20-keel-harness-v0.2-design.md`. Decisions D5, D6 and D7 are revised
in §3; every v0.2 decision not mentioned here stays.
**Origin:** a harness-engineering review of v0.2.0 against an evaluation criterion agreed with the
owner in rounds of questions (2026-10-23). Evidence is in §9.

---

## 1. What this is

v0.3 keeps what v0.2 got right (tested bash for everything deterministic, a sensor contract that
teaches the fix, baselines with a ratchet, the "none" confidence outcome, a portable core) and
closes the gaps an agreed criterion exposed: no authority layer, no CI or pre-commit enforcement,
plans outside git, nothing stopping an agent from loosening its own baseline, and flows that live
only as prose. It also reorganises the plugin so that what is copied into a target repository,
what runs from the plugin, and what every skill shares are separate and visible.

The verdict of the review was **evolve with a refactor, not rewrite**: the central contracts are
compatible with the criterion, the gaps are additive, and 946 passing assertions make a refactor
safe (§6).

## 2. The evaluation criterion

The **harness** is the user layer around a coding agent (guides, sensors, gates, rules, authority,
feedback) plus the *configuration* of its runtime (component R). The agent's implementation is out
of scope. The core is agent-agnostic; agent-specific parts are adapters.

### 2.1 Profiles

| Profile | How the agent works | Human review |
| --- | --- | --- |
| **A — Assisted** | Interactive session; the human follows each step | Continuous |
| **S — Supervised** | The agent delivers a complete, verified pull request | Pre-merge, by consequence |
| **L — Autonomous/long** | Hours, several sessions, one agent owns the whole job | Pre-merge for consequential paths; post-merge for reversible ones, with canary and rollback |

### 2.2 Components by profile

● required · ○ recommended · – optional. **N** = agnostic core (make, scripts, CI, files) ·
**Ad** = adapter.

| # | Component | Lives in | A | S | L |
| --- | --- | --- | --- | --- | --- |
| C0 | Operable project (one command to set up, build, test) | N | ● | ● | ● |
| C1 | Context map (`AGENTS.md` as an index + `docs/`) | N + Ad | ● | ● | ● |
| C1b | Exemplary code (one canonical pattern per concept; legacy zones marked) | N | ○ | ● | ● |
| C2 | Computational sensors (fast in the inner loop, slow in CI) + baseline/ratchet | N | ● | ● | ● |
| C3 | Inferential sensors (evaluator or a different model) | N + Ad | – | ○ | ● |
| C4 | Architecture fitness functions, derived from ADRs | N | ○ | ● | ● |
| C5 | Proof of outcome: acceptance before code, gate in layers | N + Ad | ● light | ● | ● |
| C6 | State across sessions (plans, progress) | N | – | ○ | ● |
| C7 | Capability × authority + a consequence map | N + Ad | ● | ● | ● |
| C8 | Legibility and traces | N | – | ○ | ● |
| C9 | Tuning loop: **the plugin proves** (with/without evals), **the project verifies** (adherence check) | plugin / N | ● | ● | ● |
| C10 | Multi-agent orchestration | Ad | – | – | ○ |
| R | Runtime configuration; each item has an N equivalent or is marked adapter-only | Ad | ● | ● | ● |

### 2.3 Cross-cutting policies

- **Review by consequence**, driven by the C7 consequence map.
- **Legacy:** baseline + ratchet, canonical exemplars and cleanup loops. A baseline or limit may be
  **loosened only with a justification recorded in the same diff** (§5.3).
- **Portability:** Claude Code adapter only for now (D5 kept); the core must run with no agent at
  all (make, pre-commit, CI).
- **Scoring:** 0 absent · 1 documented · 2 implemented · 3 implemented and verified (test or eval),
  each score backed by `file:line`.

## 3. Decisions

### 3.1 Revised v0.2 decisions

| ID | v0.2 | v0.3 | Why |
| --- | --- | --- | --- |
| D5 | Target agents: Claude Code, Copilot, Devin | **Kept.** Codex is backlog (plan F4); the layout leaves room for `.codex-plugin/` | Owner decision, 2026-10-23 |
| D6 | Execution plans live outside git | **Revised.** Plans and progress are versioned, each plan with a small, verifiable **Acceptance** section | C6 and C5: another session, agent or reviewer must see the plan and its acceptance |
| D7 | Gate feedback only through the Claude Code Stop hook; no CI | **Revised.** keel installs a CI workflow and a pre-commit hook that run the fast gate, `harness-check` and `guard` | C5 for profiles S and L; pre-commit is the agent-agnostic enforcement layer |

### 3.2 New decisions

| ID | Decision | Owner or builder |
| --- | --- | --- |
| D29 | Evolve with a refactor (§4); never a rewrite. Each skill migrates on its own and is measured against the v0.2 eval baseline | owner |
| D30 | All three profiles are covered: A and S first, L in the final phases, inside keel | owner |
| D31 | The plugin carries the with/without evals that prove each intervention; the project carries only the adherence check (`harness-check`) | owner |
| D32 | A `guard` sensor fails when a baseline count rises, a rule limit loosens or `gate.env` budgets grow relative to `HEAD`, unless the same diff adds a decision record named by `LOOSENED_BY=` | owner |
| D33 | No `eval` of configuration files: rule `.env` files are parsed as `KEY=value` and validated, like `gate.env` already is | builder |
| D34 | No `bin/` directory: the CLI lives in `scripts/keel` and skills call it as `${CLAUDE_PLUGIN_ROOT}/scripts/keel` | builder (§9.4) |
| D35 | No plugin-level hooks. Hooks are copied into the target repository, where they are readable and reviewed | builder (§9.5) |
| D36 | Read-only skills (`assess`, `doctor`) declare `disallowed-tools`; `allowed-tools` is never used as a restriction | builder (§9.4) |
| D37 | Every `never`/`always` in a skill maps to a code check or an eval grader (traceability matrix) | builder |
| D38 | Each SKILL.md stays under 20,000 bytes, enforced by a test | builder (§9.5) |

## 4. Plugin layout (v0.3)

```
plugins/keel-harness/
├── .claude-plugin/plugin.json    # manifest; no hooks, no bin/, no .mcp.json
├── README.md
├── skills/                       # judgment only; each SKILL.md under 20 KB
│   ├── assess/   SKILL.md + references/   # disallowed-tools: Write Edit NotebookEdit
│   ├── build/    SKILL.md + references/
│   ├── rules/    SKILL.md + references/
│   └── doctor/   SKILL.md + references/   # disallowed-tools: Write Edit NotebookEdit
├── scripts/                      # runs from the plugin
│   ├── keel                      # phase CLI: plan | approve | apply | verify | measure | check
│   └── lib/                      # KEY=value parser, JSON helpers, flow state
├── assets/                       # copied into the target repository; runs without the plugin
│   ├── core/                     # agent-agnostic
│   │   ├── gate/                 # gate.sh, gate.env, lib/ (baseline, junit, envparse)
│   │   ├── sensors/              # typescript/ python/ jvm/ common/ rules/ slow/ guard/
│   │   ├── check/                # harness-check.sh
│   │   ├── ci/                   # GitHub Actions workflow
│   │   ├── precommit/            # lefthook / pre-commit / husky configs
│   │   └── templates/            # AGENTS.md, nested AGENTS.md, ADR, plan with Acceptance, rule section, topics
│   └── adapters/
│       └── claude/               # claude-stop.sh, claude-protect.sh (PreToolUse), settings fragment
├── contracts/                    # single source referenced by every skill
│   └── sensor.md rule-env.md state.md flow.md plan.md consequence.md
└── evals/                        # per skill (with/without) + process (adherence) + triggering
```

- **`assets/` vs `scripts/`** makes visible what goes into the target repository and what runs from
  the plugin. Today the boundary is only the "Managed by keel" header.
- **`contracts/` at the root** removes the two cross-skill paths
  (`${CLAUDE_SKILL_DIR}/../build/assets`). The plugin reference places shared resources at the
  plugin root, reached through `${CLAUDE_PLUGIN_ROOT}`.
- **The installed contract is stable.** In the target repository `scripts/gate.sh`,
  `scripts/sensors/` and `.agents/` keep their paths; v0.3 only adds files. `state.yml` moves to
  `schema_version: 3` and `build` upgrades v0.2 installs in place, under confirmation.

## 5. Flows that are followed

No mechanism makes an LLM follow a flow every time. v0.3 stacks four layers, strongest first.

### 5.1 Code enforces the order

`scripts/keel` runs each phase of a skill. `keel plan <skill>` writes the proposal; `keel approve`
records the user's answer with the proposal's hash in `.agents/flow/<skill>.approved` (git-ignored);
`keel apply` refuses without a matching approval; `keel verify <skill>` replaces the prose
self-verify checklists (today `build/SKILL.md` §10) and exits non-zero on any unmet item.

### 5.2 Tools are removed, not just pre-approved

`assess` and `doctor` declare `disallowed-tools: Write Edit NotebookEdit`. `allowed-tools` only
pre-approves; it does not restrict (§9.4).

### 5.3 The target repository enforces what the agent touches

The `guard` sensor (D32) compares baselines, rule limits and gate budgets with `HEAD`. Loosening
passes only when the diff also adds the record named by `LOOSENED_BY=`, so review by consequence
sees the justification. Pre-commit and CI run the same gate (D7 revised). `claude-protect.sh`
(PreToolUse) denies edits to harness files the consequence map marks as protected.

### 5.4 Adherence is measured

Process evals grade trajectories ("asked before writing?", "ran the gate?"), and a transcript
diagnosis in the style of superpowers' `plan-adherence` prompt reports the adherence rate over
time. This layer measures; it promises nothing.

### 5.5 Skill template

Each rule is written in the form that fits its failure (superpowers' "Match the Form to the
Failure", §9.5): output-shape failures get a recipe or required slots; discipline failures get a
prohibition plus a rationalization table, and preferably a code check.

```
---
name / description ("Use when…") / disallowed-tools (read-only skills only)
---
## 0. Precondition       → keel check pre <skill>
## Phases                → each: goal · keel command · output · question to the human
## Output contract       → recipe / slots (shape failures)
## Discipline            → prohibition + rationalization table (discipline failures only)
## Done when             → keel verify <skill> (generated from contracts/)
```

## 6. Assessment of v0.2.0

Suite: `make check` → 946 `ok`, exit 0 (with `shellcheck` on `PATH`; without it, 25 assertions
report FAIL instead of skip — D-5).

| # | Score | Evidence |
| --- | --- | --- |
| C0 | 2 | `make bootstrap` (`skills/build/SKILL.md` §3); v0.2 evals not run |
| C1 | 3 | Template of at most 100 lines, no overviews (`build/references/agents-md-template.md`); size, command and pointer checks in `harness-check.sh`; the `CLAUDE.md` → `@AGENTS.md` bridge matches the memory docs |
| C1b | 1 | Only `adopted-patterns`, inferential (`rules/references/catalog.md`) |
| C2 | 3 | Seven-field contract with guidance that names the wrong fix (`build/references/sensor-contract.md`); tested assets — but see D-1 |
| C3 | 0 | Out of scope in v0.2 (`2026-10-20-keel-harness-v0.2-design.md` §13) |
| C4 | 3 | `render.sh` generates ArchUnit / dependency-cruiser / import-linter with native baselines (`tests/keel_render_test.sh`) |
| C5 | 2 | Stop hook with loop guard, fingerprint and lock (`build/assets/hooks/claude-stop.sh`); fast/slow gates; no CI (D7), no acceptance before code |
| C6 | 1 | Plans are git-ignored (D6; `build/SKILL.md` §7) |
| C7 | 0 | No permissions, sandbox or PreToolUse; protection is prose only (`claude-stop.sh`, header text) |
| C8 | 1 | Log-format guidance only (`build/references/context-engineering.md`) |
| C9 | 2 | Project side: `harness-check.sh` (12 checks), `harness_review_by`. Plugin side: 15 cases including the `rules-effect` with/without pair, none run for v0.2 (`README.md`) |
| R | 1 | Stop-hook merge into `.claude/settings.json` only |

### Defects

- **D-1 (high, reproduced).** The gate accepts the agent loosening its own baseline in the same
  diff. A 20-line file with `LIMIT=10` fails `file-size`; appending `src/big.txt<TAB>20` to
  `.agents/baselines/file-size.tsv` makes the gate pass. Nothing compares the baseline with `HEAD`;
  the same holds for `LIMIT=` and for edited tests.
- **D-2 (medium).** Nine rule sensors `eval` their `.env` file (e.g.
  `rules/assets/sensors/code-language.sh:24`), while `gate.sh:37` reads `gate.env` "never sourced".
- **D-3 (low).** `assess/references/harness-model.md:58,85` points at `reasoning-framework.md`, which
  does not exist.
- **D-4 (low).** `build/SKILL.md:148` says `PostToolUse` output never reaches Claude; with exit 2 its
  stderr does (v0.2 spec §14.1 states it correctly). Choosing the Stop hook remains right.
- **D-5 (low).** Without `shellcheck`, `tests/keel_assets_test.sh:9` reports FAIL instead of skip.

### Strengths kept

Deterministic code ships as tested bash; guidance teaches the right fix and names the wrong one;
baselines carry `review_by`; the "none" confidence outcome never installs an invented rule; the
installed core runs without the plugin; the README states eval confounders honestly.

## 7. Out of scope for v0.3

- Executing migrations (v0.2 D4 stands).
- A Codex adapter (backlog, D5).
- Multi-agent orchestration beyond documentation (C10).
- Glob-scoped adapters (`.claude/rules`, `.github/instructions`).

## 8. Risks and open questions

| Risk | Mitigation |
| --- | --- |
| The F1 baseline needs eval budget and a host without the nested-sandbox restriction | Run it before F2; without it, F2–F5 have no "did not get worse" ruler |
| The F2 refactor is large | One skill at a time (doctor → assess → build → rules), evals after each |
| `guard` blocks a legitimate loosening | It never blocks a recorded one; the record is one file in the same diff |
| PreToolUse protection adds friction | Scoped to paths the consequence map marks; the deny reason names the approved route |
| Inferential sensors (F5) are costly and non-deterministic | Optional, budgeted, and removed when the ablation shows Δ ≤ 0 |
| Every harness component encodes an assumption about the model that expires | `harness_review_by` plus re-running the ablations on each model change |

## 9. Evidence

1. **Guides and sensors, computational and inferential**; recurring issues should improve the
   controls (Böckeler, [martinfowler.com](https://martinfowler.com/articles/harness-engineering.html), 2026-04-02).
2. **AGENTS.md as a map, not an encyclopedia**; review comments and bugs become documentation and
   tooling (Lopopolo, [OpenAI](https://openai.com/index/harness-engineering/), 2026-02-11;
   [lopopolo/harness-engineering](https://github.com/lopopolo/harness-engineering): `docs/feedback/`,
   `docs/proof/`, `docs/authority/`, `playbooks/improve-harness.md`).
3. **Long-running harnesses**: progress files, feature lists in JSON, a separate sceptical evaluator,
   and removing components that stopped being load-bearing
   ([Anthropic, 2025-11-26](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents);
   [Rajasekaran, 2026-03-24](https://www.anthropic.com/engineering/harness-design-long-running-apps)).
4. **Plugin conventions** ([plugins reference](https://code.claude.com/docs/en/plugins-reference)):
   "claude.ai and Cowork don't install a plugin that has this directory" (`bin/`); shared resources
   at the plugin root through `${CLAUDE_PLUGIN_ROOT}`; `userConfig` for per-user values.
   [Skills docs](https://code.claude.com/docs/en/skills): `allowed-tools` "does not restrict which
   tools are available"; `disallowed-tools` removes tools while the skill is active.
   `anthropics/claude-code` `plugins/plugin-dev/skills/plugin-structure` and `plugin-settings`
   (v0.1.0): parse settings without executing them, validate values, provide defaults.
5. **superpowers** (`obra/superpowers` v7.0.1): one `skills/` with per-platform manifests; TDD for
   skills (RED baseline, GREEN, close loopholes) and "Match the Form to the Failure"
   (`skills/writing-skills/SKILL.md`); a 20,000-byte skill-size test because skills are re-attached
   truncated after compaction (`tests/skill-size/`); transcript diagnosis of plan adherence
   (`skills/diagnosing-superpowers/prompts/plan-adherence.md`). Its SessionStart injection hook is
   deliberately not adopted (D35).
6. **Context files**: LLM-generated files slightly lower success at more than 20 % cost;
   developer-written files help a little (Gloaguen et al., [arXiv 2602.11988](https://arxiv.org/abs/2602.11988)).
7. **Scepticism with data**: verification between steps is what makes chains work
   (0.9¹⁰ ≈ 35 % without it); the harness can make a model worse; test the model + harness
   combination (Akita, *Competente o Suficiente*, `book/pt/ch03.md`, `ch06.md`, `ch14.md`,
   [akitaonrails/ai-book-2026](https://github.com/akitaonrails/ai-book-2026)).
8. **Sandboxing** cut permission prompts by 84 % internally
   ([Anthropic, 2025-10-20](https://www.anthropic.com/engineering/claude-code-sandboxing)).
9. **Memory belongs with the harness, in open files** (Chase, "Your harness, your memory",
   LangChain, 2026-04-11 — read through secondary summaries).
